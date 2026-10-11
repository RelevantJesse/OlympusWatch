local A=OlympusWatch
local C=OlympusWatchCrypto
local K=OlympusWatchAuthorityKey
local fields={'domain','seq','prev','time','actor','kind','target','name','faction','map','x','y','start','expires','reason','contact','layer','ref','override'}
local textFields={actor=64,target=96,name=96,reason=160,contact=96,layer=48}
local numbers={seq=true,time=true,map=true,x=true,y=true,start=true,expires=true,ref=true,override=true}
local kinds={grant=true,revoke=true,add=true,exclude=true,restore=true,rollback=true,battle=true,cancel=true}
local function integer(v,lo,hi) return type(v)=='number' and v==v and v==math.floor(v) and v>=lo and v<=hi end
function A.ParseEvent(wire)
    if type(wire)~='string' or #wire>4096 then return nil end
    local payload,signature=wire:match('^(.*)%.([0-9a-f]+)$')
    if not payload or #signature~=512 then return nil end
    local parts={}; for value in (payload..'|'):gmatch('(.-)|') do parts[#parts+1]=value end
    if #parts~=#fields then return nil end
    local e={wire=wire,payload=payload,signature=signature}
    for i,key in ipairs(fields) do
        local value=parts[i]
        if textFields[key] then
            value=C.Unhex(value)
            if not value or #value>textFields[key] or value:find('[%c|]') then return nil end
        elseif numbers[key] then
            if not value:match('^%d+$') then return nil end
            value=tonumber(value); if not integer(value,0,2147483647) then return nil end
        end
        e[key]=value
    end
    if e.domain~=('OWA1:'..A.Scope()) or not kinds[e.kind] or e.seq<1 or e.seq>10000 or #e.prev~=64 or e.prev:find('[^0-9a-f]') or e.actor=='' or e.target=='' or e.override>1 then return nil end
    return e
end
local function freshState()
    return {revision=0,head=string.rep('0',64),time=0,roles={[K.owner]=true},guilds={},battles={},lastExclude={},audit={},latestGuild={}}
end
function A.InitAuthority()
    if not K or not K.modulus then return end
    if type(A.db.authorityLog)~='table' then A.db.authorityLog={} end
    if type(A.db.sharedGuilds)~='table' then A.db.sharedGuilds={} end
    for key,enabled in pairs(A.db.guilds) do
        if enabled and key:find('olympus',1,true) then A.db.sharedGuilds[key]=A.db.guildNames[key] or key end
    end
    A.authority={state=freshState(),queue={},queued={},verified={},fragments={},outgoing={},outSeen={},interests={},replay=1,ready=false}
    A.db.authorityID=A.db.authorityID or K.id
    if A.db.authorityID~=K.id then A.authority.error='Authority key mismatch: install the original owner public key.'; return end
    A.QueueShared('Q\t'..(A.Faction() or '')..'\t0\t'..K.id)
end
function A.GlobalExcluded(guild)
    return A.authority and A.authority.state.guilds[A.Key(guild)]=='exclude'
end
function A.ApplyEvent(e,replay)
    local auth=A.authority; local state=auth.state
    if e.seq~=state.revision+1 or e.prev~=state.head or e.time<state.time or e.time>A.Now()+60 then return false,'Out-of-order or invalid authority time' end
    local owner=e.actor==K.owner
    if not owner and not state.roles[e.actor] then return false,'Author is not privileged' end
    if e.override==1 and (not owner or e.kind~='exclude') then return false,'Invalid owner override' end
    local before=state.guilds[e.target]
    if e.kind=='grant' or e.kind=='revoke' then
        if not owner or e.target==K.owner or #e.target>64 then return false,'Only the owner manages roles' end
        if e.kind=='grant' and state.roles[e.target] or e.kind=='revoke' and not state.roles[e.target] then return false,'Invalid role transition' end
        state.roles[e.target]=e.kind=='grant'
    elseif e.kind=='add' or e.kind=='restore' or e.kind=='exclude' then
        if e.target~=A.Key(e.name) or not A.Text(e.name) then return false,'Invalid guild key' end
        if e.kind=='exclude' then
            if before=='exclude' then return false,'Guild already excluded' end
            state.lastExclude[e.actor]=e.time; state.guilds[e.target]='exclude'
        else
            if e.kind=='restore' and before~='exclude' then return false,'Guild is not excluded' end
            state.guilds[e.target]='watch'
        end
        A.db.guildNames[e.target]=e.name; A.db.guildSources[e.target]='shared'
        state.latestGuild[e.target]=e.seq
    elseif e.kind=='rollback' then
        local previous=state.audit[e.ref]
        if not owner or not previous or previous.event.target~=e.target or state.latestGuild[e.target]~=e.start or (e.name~='' and e.name~='watch' and e.name~='exclude') or e.name~=(previous.before or '') then return false,'Invalid owner rollback' end
        state.guilds[e.target]=e.name~='' and e.name or nil
        state.latestGuild[e.target]=e.seq
    elseif e.kind=='battle' then
        local battle=state.battles[e.target]
        if battle and battle.actor~=e.actor and not owner then return false,'Cannot edit another organizer\'s battle' end
        if not A.Text(e.name) or not A.Text(e.contact) or (e.faction~='Horde' and e.faction~='Alliance') or not integer(e.map,1,100000) or not integer(e.x,0,10000) or not integer(e.y,0,10000) or e.start<e.time-60 or e.start>e.time+7*86400 or e.expires<=e.start or e.expires>e.start+7200 then return false,'Invalid battle announcement' end
        state.battles[e.target]=e
    elseif e.kind=='cancel' then
        if not state.battles[e.target] then return false,'Battle not found' end
        state.battles[e.target]=nil
    end
    state.revision=e.seq; state.head=C.Hash(e.wire); state.time=e.time
    state.audit[e.seq]={event=e,before=before}
    if not replay then
        A.db.authorityLog[e.seq]=e.wire
        A.QueueEvent(e.wire)

    end
    A.Changed()
    return true
end
function A.StageEvent(wire)
    if not A.authority or A.authority.error then return false end
    local e=A.ParseEvent(wire); local auth=A.authority
    if not e or e.seq<=auth.state.revision or e.seq>auth.state.revision+64 or #auth.queue>=32 then return false end
    local id=C.Hash(wire); if auth.queued[id] then return false end
    auth.queued[id]=true; auth.queue[#auth.queue+1]=e
    return true
end
function A.AuthorityWork()
    local auth=A.authority; if not auth or auth.error then return end
    -- Replay persisted signatures rather than trusting editable cached roles.
    if not auth.worker then
        local e,replay
        if not auth.ready then
            local raw=A.db.authorityLog[auth.replay]
            if raw then e=A.ParseEvent(raw); replay=true
                if not e then auth.error='Corrupt saved authority history at '..auth.replay; return end
            else auth.ready=true end
        end
        if not e then e=table.remove(auth.queue,1) end
        if e then
            auth.worker=coroutine.create(function()
                auth.queued[C.Hash(e.wire)]=nil
                if not C.Verify(e.payload,e.signature,K.modulus,coroutine.yield) then
                    if replay then auth.error='Invalid saved signature at '..auth.replay end
                    return
                end
                if replay then
                    local ok,reason=A.ApplyEvent(e,true)
                    if not ok then auth.error=reason; return end
                    auth.replay=auth.replay+1
                else auth.verified[e.seq]=e end
            end)
        end
    end
    -- Small arithmetic slices keep hostile signature traffic from blocking a frame.
    for _=1,2 do
        if not auth.worker then break end
        local ok,err=coroutine.resume(auth.worker)
        if not ok then auth.error='Authority verifier failed: '..tostring(err); auth.worker=nil; return end
        if coroutine.status(auth.worker)=='dead' then auth.worker=nil; break end
    end
    if auth.ready then
        local e=auth.verified[auth.state.revision+1]
        if e then
            local ok,reason=A.ApplyEvent(e,false)
            auth.verified[e.seq]=nil
            if not ok then auth.error=reason end
        end
    end
    -- Feed a long clipboard import progressively within the verifier queue bound.
    if auth.import and #auth.queue<24 then
        for _=1,8 do
            local start,finish=auth.import:find('\n',auth.importOffset,true)
            local raw=auth.import:sub(auth.importOffset,(start or (#auth.import+1))-1):gsub('\r$','')
            local e=A.ParseEvent(raw)
            if e and e.seq>auth.state.revision+64 then break end
            if raw~='' then A.StageEvent(raw) end
            if not finish then auth.import=nil; break end
            auth.importOffset=finish+1
        end
    end
end
function A.ImportAuthority(text)
    if A.ImportCatalogue and A.ImportCatalogue(text) then return true end
    if not A.authority or type(text)~='string' or #text>48*1024*1024 then return false end
    A.authority.import=text; A.authority.importOffset=1
    A.Print('Signed history queued for verification. Changes apply only after signatures and permissions pass.')
    return true
end
function A.QueueShared(message)
    local auth=A.authority; if not auth or #message>255 or #auth.outgoing>=512 or auth.outSeen[message] then return end
    auth.outgoing[#auth.outgoing+1]=message; auth.outSeen[message]=true
end
function A.QueueEvent(wire)
    local id=C.Hash(wire):sub(1,16); local total=math.ceil(#wire/170)
    for i=1,total do A.QueueShared(table.concat({'E',A.Faction() or '',id,i,total,wire:sub((i-1)*170+1,i*170)},'\t')) end
end
function A.ShareGuild(guild)
    if not A.authority or not A.Text(guild) or not A.Key(guild):find('olympus',1,true) then return end
    A.db.sharedGuilds[A.Key(guild)]=guild
    local factions=A.db.guildFactions[A.Key(guild)] or {}
    local label=factions.Alliance and (factions.Horde and 'Both' or 'Alliance') or factions.Horde and 'Horde' or 'Unknown'
    A.QueueShared('D\t'..(A.Faction() or '')..'\t'..C.Hex(guild)..'\t'..label)
end
function A.ReceiveShared(message,sender)
    if not A.authority or type(message)~='string' or #message>255 then return false end
    local tag,faction,rest=message:match('^(%u)\t([^\t]*)\t(.*)$')
    if tag~='D' and tag~='E' and tag~='Q' and tag~='I' and tag~='H' and tag~='L' and tag~='J' then return false end
    if faction~=A.Faction() then return true end
    local auth=A.authority
    if tag=='J' or tag=='L' then
        if A.ReceiveEncounter then A.ReceiveEncounter(tag,rest,sender) end
    elseif tag=='H' then
        if A.ReceiveActivity then A.ReceiveActivity(rest,sender) end
    elseif tag=='I' then
        local id=C.Unhex(rest); local e=id and auth.state.battles[id]
        if not e or e.faction~=A.Faction() or e.expires<=A.Now() then return true end
        local interested=auth.interests[id] or {}; auth.interests[id]=interested
        local count=A.InterestCount(id)
        if count<1000 or interested[sender] then interested[sender]=A.Now()
        else auth.interestOverflow=auth.interestOverflow or {}; auth.interestOverflow[id]=A.Now() end
    elseif tag=='D' then
        local encoded,label=rest:match('^([^\t]+)\t([^\t]+)$')
        local guild=C.Unhex(encoded or rest)
        if label and label~='Alliance' and label~='Horde' and label~='Both' and label~='Unknown' then return true end
        if not A.Text(guild) or not A.Key(guild):find('olympus',1,true) then return true end
        local key=A.Key(guild)
        local count=0; for _ in pairs(A.db.sharedGuilds) do count=count+1 end
        if count>=2000 and not A.db.sharedGuilds[key] then return true end
        local factions=A.db.guildFactions[key] or {}; A.db.guildFactions[key]=factions
        if label=='Alliance' or label=='Both' then factions.Alliance=true end
        if label=='Horde' or label=='Both' then factions.Horde=true end
        A.Changed()
        local new=not A.db.sharedGuilds[key]
        A.db.sharedGuilds[key]=guild; A.db.guildNames[key]=guild
        if not A.db.excludedGuilds[key] and not A.GlobalExcluded(guild) then A.db.guilds[key]=true; A.db.guildSources[key]='shared' end
        if new then A.Print('Shared guild discovered: <'..guild..'>'); A.Changed() end
    elseif tag=='Q' then
        local revision,root=rest:match('^(%d+)\t([0-9a-f]+)$'); revision=tonumber(revision)
        if root~=K.id or not integer(revision,0,10000) then return true end
        if A.Now()-(auth.lastResponse or 0)<15 then return true end
        auth.lastResponse=A.Now()
        for seq=revision+1,math.min(revision+8,auth.state.revision) do A.QueueEvent(A.db.authorityLog[seq]) end
        local keys={}; for key in pairs(A.db.sharedGuilds) do keys[#keys+1]=key end; table.sort(keys)
        -- Rotate the catalogue so long lists do not starve later discoveries.
        local offset=auth.catalogueOffset or 0
        for i=1,math.min(80,#keys) do A.ShareGuild(A.db.sharedGuilds[keys[(offset+i-1)%#keys+1]]) end
        auth.catalogueOffset=#keys>0 and (offset+80)%#keys or 0
    elseif tag=='E' then
        local id,index,total,fragment=rest:match('^([0-9a-f]+)\t(%d+)\t(%d+)\t(.*)$'); index,total=tonumber(index),tonumber(total)
        if not id or #id~=16 or not integer(total,1,25) or not integer(index,1,total) or #fragment>170 then return true end
        local key=sender..':'..id; local entry=auth.fragments[key]
        if not entry then
            local count=0; for _ in pairs(auth.fragments) do count=count+1 end; if count>=16 then return true end
            entry={time=A.Now(),total=total,parts={},count=0}; auth.fragments[key]=entry
        end
        if entry.total~=total then return true end
        if not entry.parts[index] then entry.count=entry.count+1; entry.parts[index]=fragment end
        if entry.count==total then
            local wire=table.concat(entry.parts); auth.fragments[key]=nil
            if C.Hash(wire):sub(1,16)==id then A.StageEvent(wire) end
        end
    end
    return true
end
function A.SharedTick()
    local auth=A.authority; if not auth then return end
    for key,entry in pairs(auth.fragments) do if A.Now()-entry.time>90 then auth.fragments[key]=nil end end
    if not A.db.sharing or not A.db.enabled or not A.InWorld() then return end
    if A.Now()-(auth.lastSync or 0)>=30 then
        auth.lastSync=A.Now(); A.QueueShared('Q\t'..(A.Faction() or '')..'\t'..auth.state.revision..'\t'..K.id)
    end
    local message=auth.outgoing[1]
    if message and A.Broadcast(message) then table.remove(auth.outgoing,1); auth.outSeen[message]=nil end
end
function A.ActiveBattles()
    local result={}
    if not A.authority then return result end
    for _,e in pairs(A.authority.state.battles) do
        if e.faction==A.Faction() and e.expires>A.Now() then result[#result+1]=e end
    end
    table.sort(result,function(a,b) if a.start==b.start then return a.target<b.target end; return a.start<b.start end)
    return result
end
function A.Interested(id)
    local e=A.authority and A.authority.state.battles[id]
    if not e or e.expires<=A.Now() or e.faction~=A.Faction() then return end
    local interested=A.authority.interests[id] or {}; A.authority.interests[id]=interested
    local name=A.PlayerName(); if not name then return end
    if A.Now()-(interested[name] or 0)<60 then return end
    interested[name]=A.Now(); A.QueueShared('I\t'..A.Faction()..'\t'..C.Hex(id))
    A.Print('Marked interested in '..e.name..'. Contact '..e.contact..' to join; this does not send an invite.')
end
function A.InterestCount(id)
    local count=0
    local interested=A.authority and A.authority.interests[id] or {}
    for name,time in pairs(interested) do
        if A.Now()-time<=1200 then count=count+1 else interested[name]=nil end
    end
    return count
end
function A.MakeRequest(op)
    local keys={'kind','target','name','faction','map','x','y','start','expires','reason','contact','layer','ref','override'}
    local parts={'OWREQ1'}
    for _,key in ipairs(keys) do
        local v=op[key] or (numbers[key] and 0 or '')
        parts[#parts+1]=textFields[key] and C.Hex(tostring(v)) or tostring(v)
    end
    local request=table.concat(parts,'|')
    A.Print('Manage shared guilds and users in the owner companion app.')
    return request
end

-- Catalogue observations are advisory. They never alter signed exclusions or create sightings.
function A.ExportCatalogue()
    local lines={'OWG2|'..A.Scope()}
    for _,entry in ipairs(A.GuildEntries(false)) do
        if entry.key:find('olympus',1,true) then
            local f=A.db.guildFactions[entry.key] or {}
            lines[#lines+1]=C.Hex(entry.name)..'|'..(f.Alliance and (f.Horde and 'Both' or 'Alliance') or f.Horde and 'Horde' or 'Unknown')
        end
    end
    table.sort(lines,function(a,b) if a:match('^OWG2|') then return true elseif b:match('^OWG2|') then return false else return a<b end end)
    return table.concat(lines,'\n')
end
function A.ImportCatalogue(text)
    if type(text)~='string' or #text>512000 or text:sub(1,#('OWG2|'..A.Scope()..'\n'))~='OWG2|'..A.Scope()..'\n' then return false end
    for line in text:gmatch('[^\r\n]+') do
        local name,faction=line:match('^([0-9a-f]+)|(%a+)$')
        if name then A.ReceiveShared('D\t'..(A.Faction() or '')..'\t'..name..'\t'..faction,'Catalogue bridge') end
    end
    A.Print('Guild catalogue imported. Factions are reported observations; exclusions remain in effect.')
    return true
end
