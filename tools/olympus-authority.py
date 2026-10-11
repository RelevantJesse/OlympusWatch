"""Owner-controlled OlympusWatch authority and credential-free addon bridge.

Secrets live outside the addon/release. The authority serializes every mutation
in SQLite, authenticates callers, enforces policy, and signs its ordered history.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3
import time
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from contextlib import closing
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from urllib.parse import urlparse, parse_qs
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding

FIELDS = ('domain','seq','prev','time','actor','kind','target','name','faction','map','x','y','start','expires','reason','contact','layer','ref','override')
TEXT_FIELDS = {'actor','target','name','reason','contact','layer'}
LIMITS = {'actor':64,'target':96,'name':96,'reason':160,'contact':96,'layer':48}
NUMBERS = {'seq','time','map','x','y','start','expires','ref','override'}
DEFAULT_HOME = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'OlympusWatchAuthority'

def safe_text(value, limit, required=False):
    if not isinstance(value, str) or len(value.encode('utf-8')) > limit or any(ord(c)<32 or c=='|' for c in value) or (required and not value.strip()):
        raise ValueError('Invalid text field')
    return value.strip()

def encode(event):
    parts=[]
    for field in FIELDS:
        value=event.get(field, 0 if field in NUMBERS else '')
        parts.append(str(value).encode('utf-8').hex() if field in TEXT_FIELDS else str(value))
    return '|'.join(parts)

def decode(wire):
    payload,signature=wire.rsplit('.',1)
    parts=payload.split('|')
    if len(parts)!=len(FIELDS): raise ValueError('Invalid event')
    result={}
    for field,value in zip(FIELDS,parts):
        result[field]=bytes.fromhex(value).decode('utf-8') if field in TEXT_FIELDS else int(value) if field in NUMBERS else value
    return result,payload,signature

def request_decode(value):
    parts=value.strip().split('|')
    if len(parts)!=15 or parts[0]!='OWREQ1': raise ValueError('Invalid addon request')
    keys=('kind','target','name','faction','map','x','y','start','expires','reason','contact','layer','ref','override')
    out={}
    for key,value in zip(keys,parts[1:]):
        out[key]=bytes.fromhex(value).decode('utf-8') if key in TEXT_FIELDS else int(value) if key in NUMBERS else value
    return out

def private_write(path, data):
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w',encoding='utf-8') as handle: handle.write(data)

class Authority:
    def __init__(self, home=DEFAULT_HOME, clock=time.time, ruleset="pvp"):
        self.home=Path(home); self.clock=clock
        if ruleset not in {'pvp','pve','rp','hardcore'}: raise ValueError('Invalid ruleset')
        self.ruleset=ruleset
        self.db_path=self.home/('history.sqlite3' if ruleset=='pvp' else 'history-'+ruleset+'.sqlite3')
        if ruleset!='pvp':
            with closing(sqlite3.connect(self.home/'history.sqlite3')) as source:
                owner=source.execute("SELECT tokenhash FROM actors WHERE id='owner'").fetchone()[0]
            with closing(sqlite3.connect(self.db_path)) as db:
                db.executescript('CREATE TABLE IF NOT EXISTS actors (id TEXT PRIMARY KEY, tokenhash TEXT UNIQUE NOT NULL, active INTEGER NOT NULL); CREATE TABLE IF NOT EXISTS events (seq INTEGER PRIMARY KEY, wire TEXT NOT NULL);')
                db.execute("INSERT OR IGNORE INTO actors VALUES ('owner',?,1)",(owner,)); db.commit()
        self.lock=threading.RLock()
        self.key=serialization.load_pem_private_key((self.home/'owner-key.pem').read_bytes(),password=None)
        self.modulus=format(self.key.public_key().public_numbers().n,'0512x')

    @staticmethod
    def initialize(home, addon=None):
        home=Path(home)
        if (home/'owner-key.pem').exists(): raise ValueError('Authority already exists; refusing to replace its identity')
        home.mkdir(parents=True,exist_ok=True)
        key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
        private_write(home/'owner-key.pem',key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()).decode())
        token=secrets.token_urlsafe(32)
        private_write(home/'owner-client.json',json.dumps({'url':'http://127.0.0.1:8766','token':token,'actor':'owner'},indent=2))
        db=sqlite3.connect(home/'history.sqlite3')
        db.executescript('''
            CREATE TABLE actors (id TEXT PRIMARY KEY, tokenhash TEXT UNIQUE NOT NULL, active INTEGER NOT NULL);
            CREATE TABLE events (seq INTEGER PRIMARY KEY, wire TEXT NOT NULL);
            INSERT INTO actors VALUES ('owner', '', 1);
        ''')
        db.execute('UPDATE actors SET tokenhash=? WHERE id="owner"',(hashlib.sha256(token.encode()).hexdigest(),)); db.commit(); db.close()
        result=Authority(home)
        if addon: result.export_anchor(addon)
        return result

    def export_anchor(self, addon):
        Path(addon,'AuthorityKey.lua').write_text('-- Public verification key only. Never copy the authority profile into AddOns.\nOlympusWatchAuthorityKey = {owner="owner", modulus="'+self.modulus+'", id="'+hashlib.sha256(self.modulus.encode()).hexdigest()+'"}\n',encoding='utf-8')

    def catalogue(self):
        with closing(sqlite3.connect(self.db_path)) as db:
            db.execute('CREATE TABLE IF NOT EXISTS catalogue (name TEXT PRIMARY KEY, alliance INTEGER NOT NULL, horde INTEGER NOT NULL)'); db.commit()
            return 'OWG2|'+self.ruleset+'\n'+'\n'.join(name.encode().hex()+'|'+('Both' if a and h else 'Alliance' if a else 'Horde' if h else 'Unknown') for name,a,h in db.execute('SELECT name,alliance,horde FROM catalogue ORDER BY name'))

    def dashboard(self, token):
        with closing(sqlite3.connect(self.db_path)) as db:
            row=db.execute('SELECT id,active FROM actors WHERE tokenhash=?',(hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
            wires=[r[0] for r in db.execute('SELECT wire FROM events ORDER BY seq')]
            roles,guilds,battles,last_exclude,history=self.projection(wires)
            if not row or not row[1] or not roles.get(row[0]): raise PermissionError('Invalid or revoked credential')
            rows={}
            for line in self.catalogue().splitlines()[1:]:
                encoded,faction=line.split('|'); name=bytes.fromhex(encoded).decode()
                rows[name]={'name':name,'faction':faction,'status':'Discovered'}
            for key,status in guilds.items():
                if status: rows.setdefault(key,{'name':key,'faction':'Unknown'})['status']='Excluded' if status=='exclude' else 'Watched'
            return {'ruleset':self.ruleset,'actor':row[0],'revision':len(wires),'guilds':list(rows.values()),
                'users':[{'name':name,'role':'Owner' if name=='owner' else 'Privileged','active':active} for name,active in roles.items()],
                'battles':[e for e in battles.values() if e['expires']>int(self.clock())],
                'history':[h['event'] for h in reversed(list(history.values()))]}

    def events(self, after=0, limit=32):
        with closing(sqlite3.connect(self.db_path)) as db:
            return [r[0] for r in db.execute('SELECT wire FROM events WHERE seq>? ORDER BY seq LIMIT ?',(after,min(32,max(1,limit))))]

    @staticmethod
    def projection(wires):
        roles={'owner':True}; guilds={}; battles={}; last_exclude={}; history={}
        for wire in wires:
            e,_,_=decode(wire); kind=e['kind']; target=e['target']
            before=guilds.get(target) if kind in ('add','exclude','restore','rollback') else None
            if kind=='grant': roles[target]=True
            elif kind=='revoke': roles[target]=False
            elif kind in ('add','restore'): guilds[target]='watch'
            elif kind=='exclude': guilds[target]='exclude'; last_exclude[e['actor']]=e['time']
            elif kind=='rollback': guilds[target]=e['name'] or None
            elif kind=='battle': battles[target]=e
            elif kind=='cancel': battles.pop(target,None)
            history[e['seq']]={'event':e,'before':before}
        return roles,guilds,battles,last_exclude,history

    def act(self, token, operation):
        with self.lock:
            if operation.get('kind')=='rollback-user':
                with closing(sqlite3.connect(self.db_path)) as db:
                    row=db.execute('SELECT id,active FROM actors WHERE tokenhash=?',(hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
                if not row or row[0]!='owner' or not row[1]: raise PermissionError('Only the owner can roll back a user\'s changes')
                preview=self.preview_actor_rollback(operation.get('target',''),int(operation.get('since',0)))
                result=[]
                for item in preview:
                    result.append(self._act(token,{'kind':'rollback','target':item['guild'],'ref':item['revision'],'expected':item['latest'],'reason':'Owner rollback of '+operation['target']}))
                return {'wire':'\n'.join(r['wire'] for r in result),'revision':result[-1]['revision'] if result else 0,'credential':None}
            return self._act(token,operation)

    def _act(self, token, operation):
        # BEGIN IMMEDIATE prevents parallel requests from forking the signed log
        # or forking history. Tokens are never included in events.
        with closing(sqlite3.connect(self.db_path,timeout=10)) as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT id,active FROM actors WHERE tokenhash=?',(hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
            if not row or not row[1]: raise PermissionError('Invalid or revoked credential')
            actor=row[0]
            wires=[r[0] for r in db.execute('SELECT wire FROM events ORDER BY seq')]
            if len(wires)>=10000: raise ValueError('History capacity reached; archival/checkpoint migration is required before further changes')
            roles,guilds,battles,last_exclude,history=self.projection(wires)
            if operation.get('kind')=='catalogue':
                if actor!='owner' and not roles.get(actor): raise PermissionError('Privileged access required')
                raw=operation.get('catalogue','')
                if not isinstance(raw,str) or len(raw)>6000 or not raw.startswith('OWG2|'+self.ruleset+'\n'): raise ValueError('Invalid catalogue; upload at most 25 rows at a time')
                db.execute('CREATE TABLE IF NOT EXISTS catalogue (name TEXT PRIMARY KEY, alliance INTEGER NOT NULL, horde INTEGER NOT NULL)')
                for line in raw.splitlines()[1:]:
                    encoded,faction=line.split('|')
                    name=bytes.fromhex(encoded).decode('utf-8')
                    if len(name.encode())>96 or not name or any(ord(c)<32 or c=='|' for c in name) or 'olympus' not in name.lower() or faction not in {'Alliance','Horde','Both','Unknown'}: raise ValueError('Invalid guild discovery')
                    key=name.translate(str.maketrans('ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'))
                    if db.execute('SELECT COUNT(*) FROM catalogue').fetchone()[0]>=2000 and not db.execute('SELECT 1 FROM catalogue WHERE name=?',(key,)).fetchone(): raise ValueError('Catalogue capacity reached')
                    db.execute('INSERT INTO catalogue VALUES (?,?,?) ON CONFLICT(name) DO UPDATE SET alliance=MAX(alliance,excluded.alliance),horde=MAX(horde,excluded.horde)',(key,int(faction in {'Alliance','Both'}),int(faction in {'Horde','Both'})))
                db.commit()
                return {'wire':self.catalogue(),'credential':None}

            if actor!='owner' and not roles.get(actor): raise PermissionError('Privileged access required')
            kind=operation.get('kind','')
            if kind not in {'grant','revoke','add','exclude','restore','rollback','battle','cancel'}: raise ValueError('Unknown action')
            now=int(self.clock())
            if wires and now<decode(wires[-1])[0]['time']: raise ValueError('Authority clock moved backwards; retry after clock recovery')
            e={k:0 if k in NUMBERS else '' for k in FIELDS}
            e.update(domain='OWA1:'+self.ruleset,seq=len(wires)+1,prev=hashlib.sha256(wires[-1].encode()).hexdigest() if wires else '0'*64,time=now,actor=actor,kind=kind)
            e['reason']=safe_text(operation.get('reason',''),160)
            target=safe_text(operation.get('target',''),96,True)
            credential=None
            if kind in {'grant','revoke'}:
                if actor!='owner': raise PermissionError('Only the owner can manage privileged users')
                target=safe_text(target,64,True)
                if target=='owner': raise ValueError('Owner access cannot be changed through a role action')
                if kind=='grant':
                    if roles.get(target): raise ValueError('User already privileged; revoke before rotating credentials')
                    raw=secrets.token_urlsafe(32)
                    db.execute('INSERT INTO actors VALUES (?,?,1) ON CONFLICT(id) DO UPDATE SET tokenhash=excluded.tokenhash,active=1',(target,hashlib.sha256(raw.encode()).hexdigest()))
                    credential={'actor':target,'token':raw}
                else:
                    if not roles.get(target): raise ValueError('User is not privileged')
                    db.execute('UPDATE actors SET active=0 WHERE id=?',(target,))
            elif kind in {'add','exclude','restore'}:
                e['name']=target; target=target.translate(str.maketrans('ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'))
                override=operation.get('override',False)
                if override and actor!='owner': raise PermissionError('Only the owner can override the exclusion limit')
                if kind=='exclude':
                    if guilds.get(target)=='exclude': raise ValueError('Guild already globally excluded')
                    e['override']=1 if actor=='owner' else 0  # Compatibility with older receivers' owner exemption.
                if kind=='restore' and guilds.get(target)!='exclude': raise ValueError('Guild is not globally excluded')
            elif kind=='rollback':
                if actor!='owner': raise PermissionError('Only the owner can roll back changes')
                ref=int(operation.get('ref',0)); entry=history.get(ref)
                if not entry or entry['event']['kind'] not in {'add','exclude','restore','rollback'}: raise ValueError('Select a guild-history revision')
                target=entry['event']['target']
                latest=max(n for n,h in history.items() if h['event']['target']==target and h['event']['kind'] in {'add','exclude','restore','rollback'})
                if latest!=int(operation.get('expected',ref)): raise ValueError('Guild has later changes; preview its latest revision before rollback')
                e['name']=entry['before'] or ''; e['ref']=ref; e['start']=latest
            elif kind=='battle':
                existing=battles.get(target)
                if existing and existing['actor']!=actor and actor!='owner': raise PermissionError('Cannot update another user\'s battle')
                if not existing:
                    previous=[h['event']['time'] for h in history.values() if h['event']['kind']=='battle' and h['event']['actor']==actor]
                    if previous and now-max(previous)<60: raise ValueError('Battle announcements are limited to one per minute')
                e['name']=safe_text(operation.get('name',''),96,True)
                e['contact']=safe_text(operation.get('contact',''),96,True); e['layer']=safe_text(operation.get('layer','Layer unknown'),48)
                e['faction']=operation.get('faction','')
                if e['faction'] not in {'Horde','Alliance'}: raise ValueError('Choose a battle faction')
                for field in ('map','x','y','start','expires'): e[field]=int(operation.get(field,0))
                if not (0<e['map']<=100000 and 0<=e['x']<=10000 and 0<=e['y']<=10000): raise ValueError('Invalid battle location')
                if not (now-60<=e['start']<=now+7*86400 and e['start']<e['expires']<=e['start']+7200): raise ValueError('Invalid battle start/expiration (maximum duration two hours)')
                if len([b for b in battles.values() if b['expires']>now])>=50 and not existing: raise ValueError('Too many active battles')
            elif kind=='cancel':
                if target not in battles: raise ValueError('Battle not found')
                # Every privileged user can cancel a battle under the single-role policy.
            # Prevent authorized, compromised credentials from flooding signed history.
            recent=[h['event'] for h in history.values() if h['event']['actor']==actor and now-h['event']['time']<60]
            if actor!='owner' and len(recent)>=10: raise ValueError('Privileged actions limited to ten per minute')
            e['target']=target
            payload=encode(e); signature=self.key.sign(payload.encode(),padding.PKCS1v15(),hashes.SHA256()).hex()
            wire=payload+'.'+signature
            if len(wire)>4096: raise ValueError('Event too large')
            db.execute('INSERT INTO events VALUES (?,?)',(e['seq'],wire)); db.commit()
            return {'wire':wire,'revision':e['seq'],'credential':credential}

    def preview_actor_rollback(self, actor, since):
        with closing(sqlite3.connect(self.db_path)) as db:
            wires=[r[0] for r in db.execute('SELECT wire FROM events ORDER BY seq')]
        _,_,_,_,history=self.projection(wires)
        result=[]; visited=set()
        for seq in sorted(history,reverse=True):
            e=history[seq]['event']
            if e['kind'] not in {'add','exclude','restore','rollback'} or e['target'] in visited: continue
            visited.add(e['target'])
            if e['actor']==actor and e['time']>=since:
                earliest=seq
                for older in sorted(history,reverse=True):
                    old=history[older]['event']
                    if older>=seq or old['target']!=e['target'] or old['kind'] not in {'add','exclude','restore','rollback'}: continue
                    if old['actor']!=actor or old['time']<since: break
                    earliest=older
                result.append({'revision':earliest,'latest':seq,'guild':e['target'],'restore':history[earliest]['before'] or 'discovery'})
        return result

def handler_for(authority):
    scopes={'pvp':authority}
    class Handler(BaseHTTPRequestHandler):
        def scoped(self):
            parts=self.path.split('/',3)
            if len(parts)>=4 and parts[1]=='ruleset':
                ruleset=parts[2]
                if ruleset not in {'pvp','pve','rp','hardcore'}: raise ValueError('Invalid ruleset')
                self.path='/'+parts[3]
                if ruleset not in scopes: scopes[ruleset]=Authority(authority.home,authority.clock,ruleset)
                return scopes[ruleset]
            return authority

        def log_message(self,*args): pass  # Never log Authorization headers or credentials.
        def reply(self,status,value):
            body=json.dumps(value).encode(); self.send_response(status); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
        def do_GET(self):
            try:
                selected=self.scoped()
                parsed=urlparse(self.path)
                if parsed.path=='/dashboard':
                    authorization=self.headers.get('Authorization','')
                    if not authorization.startswith('Bearer '): raise PermissionError('Credential required')
                    self.reply(200,selected.dashboard(authorization[7:]))
                elif parsed.path=='/events': self.reply(200,{'events':selected.events(int(parse_qs(parsed.query).get('after',['0'])[0]))})
                elif parsed.path=='/catalogue': self.reply(200,{'catalogue':selected.catalogue()})
                elif parsed.path=='/public': self.reply(200,{'modulus':selected.modulus,'owner':'owner'})
                else: self.reply(404,{'error':'Not found'})
            except PermissionError as exc: self.reply(403,{'error':str(exc)})
            except (ValueError,OverflowError): self.reply(400,{'error':'Invalid query'})
        def do_POST(self):
            try:
                selected=self.scoped()
                if self.path!='/action': return self.reply(404,{'error':'Not found'})
                length=int(self.headers.get('Content-Length','0'))
                if not 0<length<=8192: return self.reply(400,{'error':'Invalid body size'})
                authorization=self.headers.get('Authorization','')
                if not authorization.startswith('Bearer '): raise PermissionError('Credential required')
                data=json.loads(self.rfile.read(length)); result=selected.act(authorization[7:],data)
                self.reply(200,result)
            except PermissionError as exc: self.reply(403,{'error':str(exc)})
            except (ValueError,TypeError,KeyError,json.JSONDecodeError) as exc: self.reply(400,{'error':str(exc)})
            except Exception: self.reply(500,{'error':'Authority action failed'})
    return Handler

def client_action(profile, operation):
    parsed=urlparse(profile['url'])
    if parsed.scheme!='https' and not (parsed.scheme=='http' and parsed.hostname in {'127.0.0.1','localhost','::1'}):
        raise ValueError('Remote authority credentials require HTTPS')
    request=Request(profile['url'].rstrip('/')+'/action',json.dumps(operation).encode(),{'Authorization':'Bearer '+profile['token'],'Content-Type':'application/json'})
    try:
        with urlopen(request,timeout=15) as response: return json.load(response)
    except HTTPError as exc:
        try: message=json.loads(exc.read()).get('error','Authority rejected request')
        except (ValueError,AttributeError): message='Authority rejected request'
        raise ValueError(message) from None

def gui(profile_path):
    from olympus_dashboard import launch
    launch(profile_path,client_action)


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--home',type=Path,default=DEFAULT_HOME)
    subs=parser.add_subparsers(dest='command',required=True)
    init=subs.add_parser('init'); init.add_argument('--addon',type=Path)
    serve=subs.add_parser('serve'); serve.add_argument('--port',type=int,default=8766); serve.add_argument('--bind',default='127.0.0.1')
    action=subs.add_parser('action'); action.add_argument('--profile',type=Path); action.add_argument('--request',required=True); action.add_argument('--credential-output',type=Path)
    subs.add_parser('public').add_argument('--addon',type=Path,required=True)
    window=subs.add_parser('gui'); window.add_argument('--profile',type=Path)
    preview=subs.add_parser('preview-rollback'); preview.add_argument('--actor',required=True); preview.add_argument('--since',type=int,required=True)
    args=parser.parse_args()
    if args.command=='init': Authority.initialize(args.home,args.addon); print('Authority initialized. Private profile: '+str(args.home/'owner-client.json'))
    elif args.command=='serve':
        server=ThreadingHTTPServer((args.bind,args.port),handler_for(Authority(args.home))); print('Authority listening on localhost:'+str(args.port)); server.serve_forever()
    elif args.command=='public': Authority(args.home).export_anchor(args.addon)
    elif args.command=='gui': gui(args.profile or args.home/'owner-client.json')
    elif args.command=='preview-rollback': print(json.dumps(Authority(args.home).preview_actor_rollback(args.actor,args.since),indent=2))
    elif args.command=='action':
        profile=json.loads((args.profile or args.home/'owner-client.json').read_text())
        operation=request_decode(args.request) if args.request.startswith('OWREQ1|') else json.loads(args.request)
        if operation.get('kind')=='grant' and (not args.credential_output or args.credential_output.exists()):
            raise ValueError('Grant requires a new --credential-output filename')
        result=client_action(profile,operation)
        if result.get('credential'):
            if not args.credential_output: raise ValueError('Grant applied but credential not exported: revoke and grant again with --credential-output')
            result['credential']['url']=profile['url']; private_write(args.credential_output,json.dumps(result['credential'],indent=2))
        print(result['wire'])

if __name__=='__main__': main()
