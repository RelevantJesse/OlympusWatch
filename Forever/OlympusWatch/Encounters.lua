local A=OlympusWatch
A.HISTORY_TTL=900
A.helpRequests={}; A.inviteRequests={}
-- UI map IDs, not terrain/instance IDs. Parent checks cover city sub-maps.
local cities={[84]=true,[85]=true,[87]=true,[88]=true,[89]=true,[90]=true,[103]=true,[110]=true,[111]=true,[125]=true,[126]=true}
function A.IsCityMap(map)
    for _=1,8 do
        if cities[map] then return true end
        local info=C_Map and A.Read(C_Map.GetMapInfo,map)
        if not info or not info.parentMapID or info.parentMapID==0 or info.parentMapID==map then return false end
        map=info.parentMapID
    end
    return false
end
function A.CurrentMap() return C_Map and A.Read(C_Map.GetBestMapForUnit,'player') end
function A.InCity() return A.IsCityMap(A.CurrentMap()) end
function A.ZoneMap(map)
    for _=1,8 do
        local info=C_Map and A.Read(C_Map.GetMapInfo,map)
        if not info or info.mapType==3 or not info.parentMapID or info.parentMapID==0 then return map end
        map=info.parentMapID
    end
    return map
end
function A.NearbyActivity()
    local result={}; local map=A.CurrentMap()
    if not map or A.InCity() or not A.InWorld() then return result end
    local now=A.Now()
    for key,h in pairs(A.helpRequests) do if now-h.time>=300 or not A.Watched(h.guild) then A.helpRequests[key]=nil end end
    for _,s in ipairs(A.ActivityGroups()) do
        if A.ZoneMap(s.map)==A.ZoneMap(map) and not A.IsCityMap(s.map) then
            for _,h in pairs(A.helpRequests) do
                if h.id==s.id and (not s.help or h.time>s.help.time) then s.help=h end
            end
            result[#result+1]=s
        end
    end
    return result
end
function A.EncounterFresh(s)
    return s and not A.InCity() and A.InWorld() and not A.IsCityMap(s.map) and A.ZoneMap(s.map)==A.ZoneMap(A.CurrentMap()) and A.Now()-s.time<900 and A.db.enabled
end
function A.RequestHelp(s)
    if not A.EncounterFresh(s) or not A.db.sharing then A.Print('Select a recent encounter in your current outdoor zone and enable sharing.'); return end
    local g
    for _,candidate in ipairs(s.guilds or {}) do if candidate.localTime and A.Now()-candidate.localTime<120 then g=candidate; break end end
    if not g then A.Print('To request help, first spot a flagged member yourself here. Older and peer reports can still be mapped or contacted.'); return end
    if A.lastHelp and A.Now()-A.lastHelp<60 then A.Print('Wait a minute before requesting help again.'); return end
    local reporter=A.PlayerName(); if not reporter then return end
    local message=table.concat({'L',A.Faction(),s.map,math.floor(s.x*10),math.floor(s.y*10),g.localTime,A.Now(),math.min(256,g.localCount),OlympusWatchCrypto.Hex(g.name)},'\t')
    if not A.Broadcast(message) then A.Print('Help request could not be sent. Check the network or join a party/guild.'); return end
    A.lastHelp=A.Now(); A.ReceiveEncounter('L',message:match('^L\t[^\t]+\t(.*)$'),reporter)
    A.Print('Help requested for five minutes. Players can request an invite; you choose whom to invite.'); A.Changed()
end
local function point(rest)
    local map,gx,gy=rest:match('^(%d+)\t(%d+)\t(%d+)$')
    map,gx,gy=tonumber(map),tonumber(gx),tonumber(gy)
    if not map or map<1 or map>100000 or gx>9 or gy>9 or A.IsCityMap(map) or not A.Read(C_Map.GetMapInfo,map) then return end
    return map,gx,gy,map..':'..gx..':'..gy
end
function A.ReceiveEncounter(tag,rest,sender)
    if not A.Text(sender) then return end
    if tag=='L' then
        local m,x,y,seen,time,count,guild=rest:match('^(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t([0-9a-f]+)$')
        if not m then return end
        local map,gx,gy,id=point(m..'\t'..x..'\t'..y); seen,time,count=tonumber(seen),tonumber(time),tonumber(count); guild=OlympusWatchCrypto.Unhex(guild)
        if not map or not A.Watched(guild) or time>A.Now() or A.Now()-time>=300 or seen>time or time-seen>=120 or count<1 or count>256 then return end
        local key=id..':'..sender; local size=0; for _ in pairs(A.helpRequests) do size=size+1 end
        if size>=64 and not A.helpRequests[key] then return end
        local old=A.helpRequests[key]; if old and time<=old.time then return end
        A.helpRequests[key]={id=id,time=time,reporter=sender,guild=guild}
        A.ReceiveActivity(table.concat({map,gx,gy,count,0,seen,OlympusWatchCrypto.Hex(guild)},'\t'),sender)
        if A.db.alerts and not A.InCity() and A.ZoneMap(map)==A.ZoneMap(A.CurrentMap()) and (not A.lastHelpAlert or A.Now()-A.lastHelpAlert>=30) then
            A.lastHelpAlert=A.Now(); A.Print(sender..' requests help nearby against <'..guild..'>. Open Nearby for location and invite request. Layer unconfirmed.')
        end
        A.Changed()
    elseif tag=='J' then
        local map,gx,gy,id=point(rest)
        if not map or A.InCity() or not A.InWorld() or A.ZoneMap(map)~=A.ZoneMap(A.CurrentMap()) then return end
        local entry=A.activity[id]; local own=false
        for _,s in pairs(entry and entry.samples or {}) do if s.localSeen and A.Now()-s.time<900 and A.Watched(s.name) then own=true; break end end
        if not own then return end
        local old=A.inviteRequests[sender]; if old and A.Now()-old.time<60 then return end
        local size=0; for name,r in pairs(A.inviteRequests) do if A.Now()-r.time>=120 then A.inviteRequests[name]=nil else size=size+1 end end
        if size>=20 and not old then return end
        A.inviteRequests[sender]={name=sender,time=A.Now(),id=id,map=map}
        A.Print(sender..' requests a party invite for your sighting. Open Nearby to accept or dismiss.'); A.Changed()
    end
end
function A.EncounterContact(s,invite)
    if not A.EncounterFresh(s) then A.Print('Select a current-zone encounter from the last 15 minutes.'); return end
    local reporter=s.help and s.help.reporter or s.reporter
    if not A.Text(reporter) or reporter==A.PlayerName() then A.Print('You are the reporter. Other players can request an invite from you.'); return end
    if not invite then
        if ChatFrame_OpenChat then ChatFrame_OpenChat('/w '..reporter..' Is the Olympus encounter near '..A.Location(s)..' still active? Are you able to group?') end
        return
    end
    if not A.db.sharing or A.Scope()=='unknown' then A.Print('Enable sharing to request an invite.'); return end
    if A.lastInviteRequest and A.Now()-A.lastInviteRequest<30 then A.Print('Wait 30 seconds before requesting another invite.'); return end
    local payload='R1\t'..A.Scope()..'\tJ\t'..A.Faction()..'\t'..s.map..'\t'..math.floor(s.x*10)..'\t'..math.floor(s.y*10)
    local ok,result=pcall(C_ChatInfo.SendAddonMessage,A.PREFIX,payload,'WHISPER',reporter)
    if ok and (result==0 or result==true) then A.lastInviteRequest=A.Now(); A.Print('Invite requested from '..reporter..'. They must accept; grouping does not guarantee a layer change.')
    else A.Print('Invite request could not be sent. Try Whisper reporter.'); end
end
function A.AcceptEncounterInvite(name)
    local r=A.inviteRequests[name]
    if not r or A.Now()-r.time>=120 or A.InCity() or not A.InWorld() or A.ZoneMap(r.map)~=A.ZoneMap(A.CurrentMap()) then A.Print('That invite request expired or you left the outdoor zone.'); return end
    local fn=C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
    if not fn then A.Print('Party invitation API unavailable. Invite '..name..' manually.'); return end
    local ok=pcall(fn,name)
    if ok then A.inviteRequests[name]=nil; A.Print('Party invite attempted for '..name..'. WoW may require party leadership or reject a full group.'); A.Changed() end
end
