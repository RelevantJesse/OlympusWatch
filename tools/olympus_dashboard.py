"""Owner dashboard: reads live server state and submits explicit form actions."""
import json
import time
from pathlib import Path
from urllib.request import Request, urlopen
import tkinter as tk
from tkinter import ttk, simpledialog, messagebox, filedialog


def fetch(profile):
    if not profile['url'].startswith('https://'):
        raise ValueError('Dashboard requires HTTPS')
    request=Request(profile['url'].rstrip('/')+'/dashboard',headers={'Authorization':'Bearer '+profile['token']})
    with urlopen(request,timeout=15) as response:
        return json.load(response)


def ruleset_of(profile):
    return profile['url'].rstrip('/').split('/')[-1] if '/ruleset/' in profile['url'] else 'pvp'

def saved_table(text,name):
    import re
    match=re.search(r'\["'+re.escape(name)+r'"\]\s*=\s*\{',text)
    if not match: return ''
    start=match.end(); depth=1; quoted=False; escaped=False
    for i in range(start,len(text)):
        char=text[i]
        if quoted:
            if escaped: escaped=False
            elif char=='\\': escaped=True
            elif char=='"': quoted=False
        elif char=='"': quoted=True
        elif char=='{': depth+=1
        elif char=='}':
            depth-=1
            if depth==0: return text[start:i]
    return ''

def saved_guilds(ruleset, base=None):
    """Read only the selected ruleset; personal visibility is never uploaded."""
    import re
    base=Path(base) if base is not None else Path('C:/Program Files (x86)/World of Warcraft/_classic_beta_/WTF/Account')
    found={}
    key_pattern=r'\[("(?:[^"\\]|\\.)*")\]'
    for path in base.glob('*/SavedVariables/OlympusWatch.lua'):
        text=saved_table(saved_table(path.read_text(encoding='utf-8-sig'),'rulesets'),ruleset)
        if not text: continue
        factions={}
        # Isolate the outer table before parsing its flat per-guild records.
        # Otherwise the first record is swallowed by the outer table match.
        for match in re.finditer(key_pattern+r'\s*=\s*\{([^}]*?)\}',saved_table(text,'guildFactions'),re.S):
            try: key=json.loads(match.group(1)).strip().lower()
            except ValueError: continue
            values=match.group(2)
            factions[key]=(bool(re.search(r'\["Alliance"\]\s*=\s*true',values)),bool(re.search(r'\["Horde"\]\s*=\s*true',values)))
        hidden=set()
        for match in re.finditer(key_pattern+r'\s*=\s*true',saved_table(text,'excludedGuilds')):
            try: hidden.add(json.loads(match.group(1)).strip().lower())
            except ValueError: continue
        overrides=set()
        for match in re.finditer(key_pattern+r'\s*=\s*true',saved_table(text,'showOverrides')):
            try: overrides.add(json.loads(match.group(1)).strip().lower())
            except ValueError: continue
        for match in re.finditer(key_pattern+r'\s*=\s*("(?:[^"\\]|\\.)*")',saved_table(text,'guildNames')):
            try: key,name=json.loads(match.group(1)).strip().lower(),json.loads(match.group(2))
            except ValueError: continue
            if 'olympus' not in name.lower(): continue
            normalized=name.strip().lower()
            record=found.setdefault(normalized,{'name':name,'alliance':False,'horde':False,'hidden':set(),'override':set()})
            a,h=factions.get(key,(False,False))
            record['alliance']|=a; record['horde']|=h; record['hidden'].add(key in hidden); record['override'].add(key in overrides)
    return found


def guild_view(guild, saved):
    record=saved.get(guild['name'].strip().lower())
    global_hidden=guild['status']=='Excluded'
    personal='Not saved locally'
    if record:
        personal='Hidden locally' if record['hidden']=={True} else 'Visible locally' if record['hidden']=={False} else 'Mixed across accounts'
    if record and record.get('override')=={True} and record['hidden']=={False}: personal='Shown anyway'
    return (guild['name'],guild['faction'],'Excluded' if global_hidden else 'Visible',personal,guild['status'])


def import_discoveries(profile,act,existing=None,base=None):
    found=saved_guilds(ruleset_of(profile),base)
    known={g['name'].strip().lower():g['faction'] for g in existing or []}
    rows=[]
    for key,record in found.items():
        name,a,h=record['name'],record['alliance'],record['horde']
        previous=known.get(key)
        if previous is not None and (not a or previous in {'Alliance','Both'}) and (not h or previous in {'Horde','Both'}): continue
        rows.append(name.encode().hex()+'|'+('Both' if a and h else 'Alliance' if a else 'Horde' if h else 'Unknown'))
    for offset in range(0,len(rows),25): act(profile,{'kind':'catalogue','catalogue':'OWG2|'+ruleset_of(profile)+'\n'+'\n'.join(rows[offset:offset+25])})
    return len(rows)


def update_addon(profile):
    """Write public signed data only. WoW reads it on /reload."""
    base=Path('C:/Program Files (x86)/World of Warcraft/_classic_beta_')
    addon=base/'Interface/AddOns/OlympusWatch'
    if not addon.exists(): raise ValueError('Installed OlympusWatch folder not found')
    wires=[]; after=0
    while True:
        with urlopen(profile['url'].rstrip('/')+'/events?after='+str(after),timeout=15) as response: batch=json.load(response)['events']
        if not batch: break
        wires.extend(batch); after=int(batch[-1].split('|')[1])
        if len(wires)>10000: raise ValueError('History exceeds addon capacity')
    with urlopen(profile['url'].rstrip('/')+'/catalogue',timeout=15) as response: catalogue=json.load(response)['catalogue']
    # These formats consist only of fixed ASCII syntax and hex-encoded text.
    if any(']]' in value for value in wires+[catalogue]): raise ValueError('Invalid snapshot')
    text='OlympusWatchServerSnapshot={ruleset="'+ruleset_of(profile)+'",events=[['+'\n'.join(wires)+']],catalogue=[['+catalogue+']]}\n'
    path=addon/'ServerSync.lua'; temp=addon/'ServerSync.lua.new'; temp.write_text(text,encoding='utf-8'); temp.replace(path)
    return len(wires)


def launch(profile_path, act):
    profile=json.loads(Path(profile_path).read_text())
    base_url=profile['url'].split('/ruleset/')[0].rstrip('/')
    profile['url']=base_url+'/ruleset/pvp'
    root=tk.Tk(); root.title('OlympusWatch — Owner dashboard'); root.geometry('1000x680'); root.minsize(860,580)
    style=ttk.Style(root); style.theme_use('clam'); style.configure('Treeview',rowheight=27)
    status=tk.StringVar(value='Connecting to Oracle…')
    ttk.Label(root,text='OlympusWatch',font=('Segoe UI',20,'bold')).pack(anchor='w',padx=18,pady=(14,0))
    ttk.Label(root,text='Manage the shared guild list directly on Oracle. Changes are saved to the server immediately.').pack(anchor='w',padx=18,pady=5)
    ttk.Label(root,text='Saved discoveries sync automatically every 15 seconds. Use /reload in WoW to save recent discoveries.').pack(anchor='w',padx=18)
    ttk.Label(root,text='In-game clients receive approved changes through their sync bridge; server edits alone do not refresh WoW.').pack(anchor='w',padx=18)
    toolbar=ttk.Frame(root); toolbar.pack(fill='x',padx=18,pady=12)
    ttk.Label(toolbar,textvariable=status).pack(side='left')
    tabs=ttk.Notebook(root); tabs.pack(fill='both',expand=True,padx=18,pady=5)
    tables={}; data={}; controls={}
    def table(name,columns):
        panel=ttk.Frame(tabs,padding=10); tabs.add(panel,text=name)
        bar=ttk.Frame(panel); bar.pack(fill='x',pady=(0,10)); controls[name]=bar
        frame=ttk.Frame(panel); frame.pack(fill='both',expand=True)
        view=ttk.Treeview(frame,columns=columns,show='headings',selectmode='browse')
        for col in columns: view.heading(col,text=col); view.column(col,width=160,anchor='w')
        scroll=ttk.Scrollbar(frame,orient='vertical',command=view.yview); view.configure(yscrollcommand=scroll.set)
        view.pack(side='left',fill='both',expand=True); scroll.pack(side='right',fill='y')
        tables[name]=view; return panel
    table('Guilds',('Guild','Faction','Shared visibility','Your visibility','Source'))
    ttk.Label(controls['Guilds'],text='Your visibility reads saved personal hides. Shared exclusions affect everyone.').pack(anchor='w',pady=(0,5))
    table('Users',('User','Role','Access'))
    table('History',('Change','User','Action','Target','Reason'))
    footer=ttk.Frame(root,padding=18); footer.pack(fill='x')
    ttk.Label(footer,text='Reason for change (optional):').pack(side='left')
    reason=ttk.Entry(footer); reason.pack(side='left',fill='x',expand=True,padx=10)
    def refresh(show_error=True):
        try:
            state=fetch(profile)
            imported=import_discoveries(profile,act,state['guilds'])
            if imported: state=fetch(profile)
            data.clear(); data.update(state)
            for tree in tables.values(): tree.delete(*tree.get_children())
            local_guilds=saved_guilds(ruleset_of(profile))
            for i,g in enumerate(sorted(state['guilds'],key=lambda v:v['name'])):
                tables['Guilds'].insert('', 'end',iid=str(i),values=guild_view(g,local_guilds))
            data['guild_rows']=sorted(state['guilds'],key=lambda v:v['name'])
            for i,u in enumerate(state['users']): tables['Users'].insert('','end',iid=str(i),values=(u['name'],u['role'],'Active' if u['active'] else 'Revoked'))
            for i,e in enumerate(state['history']): tables['History'].insert('','end',iid=str(i),values=(e['seq'],e['actor'],e['kind'],e['target'],e['reason']))
            status.set(f"Connected to Oracle · {state['actor']} · {state['revision']} approved changes · {len(state['guilds'])} guilds")
        except Exception as exc: status.set('Connection failed'); show_error and messagebox.showerror('Could not load database',str(exc),parent=root)
    def selected(tab,key):
        choice=tables[tab].selection()
        if not choice: messagebox.showinfo('Select a row','Select a row in the list first.',parent=root); return None
        return data[key][int(choice[0])]
    def submit(op,description):
        op['reason']=op.get('reason',reason.get())
        if not messagebox.askyesno('Confirm shared change',description+'\n\nSave this change to Oracle?',parent=root): return
        target=None
        if op['kind']=='grant':
            target=filedialog.asksaveasfilename(parent=root,title='Save new privileged user credential',defaultextension='.json')
            if not target: return
            if Path(target).exists(): messagebox.showerror('Choose new file','Existing credential files cannot be overwritten.',parent=root); return
        try:
            result=act(profile,op)
            if result.get('credential'):
                credential=result['credential']; credential['url']=profile['url']
                import os
                fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
                with os.fdopen(fd,'w') as stream: json.dump(credential,stream,indent=2)
            refresh(); status.set('Saved to Oracle. Database view refreshed.')
        except Exception as exc: messagebox.showerror('Change rejected',str(exc),parent=root)
    def guild(kind):
        if kind=='add': name=simpledialog.askstring('Add guild','Exact guild name:',parent=root)
        else:
            row=selected('Guilds','guild_rows'); name=row['name'] if row else None
        if name: submit({'kind':kind,'target':name},f"{kind.capitalize()} guild <{name}> for all users.")
    def user(kind):
        if kind=='grant': name=simpledialog.askstring('Grant access','User ID for this privileged user:',parent=root)
        else:
            row=selected('Users','users'); name=row['name'] if row else None
        if name: submit({'kind':kind,'target':name},f"{kind.capitalize()} privileged access for {name}.")
    def rollback():
        row=selected('History','history')
        if row: submit({'kind':'rollback','target':'revision','ref':row['seq']},f"Undo guild change #{row['seq']}. Later changes to the same guild prevent this rollback.")
    for title,kind in [('Add guild','add'),('Exclude selected','exclude'),('Restore selected','restore')]: ttk.Button(controls['Guilds'],text=title,command=lambda k=kind:guild(k)).pack(side='left',padx=4)
    def upload_discoveries():
        try:
            count=import_discoveries(profile,act); refresh(); status.set(f'Imported {count} saved guild discoveries. WoW saves current discoveries when you /reload or log out.')
        except Exception as exc: messagebox.showerror('Discovery import failed',str(exc),parent=root)
    ttk.Button(controls['Guilds'],text='Import discovered guilds',command=upload_discoveries).pack(side='left',padx=4)
    ttk.Button(controls['Users'],text='Grant privileged access',command=lambda:user('grant')).pack(side='left',padx=4)
    ttk.Button(controls['Users'],text='Revoke selected',command=lambda:user('revoke')).pack(side='left',padx=4)
    ttk.Button(controls['History'],text='Undo selected guild change',command=rollback).pack(side='left',padx=4)
    def sync_game():
        try:
            count=update_addon(profile); status.set(f'Installed addon updated with {count} approved changes. Run /reload in WoW to apply.')
        except Exception as exc: messagebox.showerror('Addon sync failed',str(exc),parent=root)
    ttk.Button(toolbar,text='Update installed addon',command=sync_game).pack(side='right',padx=8)
    selected_ruleset=tk.StringVar(value='pvp')
    selector=ttk.Combobox(toolbar,textvariable=selected_ruleset,values=('pvp','pve','rp','hardcore'),state='readonly',width=12)
    selector.pack(side='right',padx=8)
    def change_ruleset(_):
        profile['url']=base_url+'/ruleset/'+selected_ruleset.get(); refresh()
    selector.bind('<<ComboboxSelected>>',change_ruleset)
    ttk.Button(toolbar,text='Sync and refresh',command=refresh).pack(side='right')
    def periodic_sync():
        refresh(False); root.after(15000,periodic_sync)
    root.after(100,refresh); root.after(15000,periodic_sync); root.mainloop()
