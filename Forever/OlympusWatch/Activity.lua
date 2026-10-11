local A=OlympusWatch
local MAX_AREAS,MAX_SAMPLES=64,256
A.activity={}
local function areaKey(map,x,y) return map..':'..math.min(9,math.floor(x*10))..':'..math.min(9,math.floor(y*10)) end
local function area(map,x,y)
    local key=areaKey(map,x,y); local entry=A.activity[key]
    if not entry then
        local count,oldest,oldTime=0,nil,math.huge
        for k,v in pairs(A.activity) do count=count+1; if v.time<oldTime then oldest,oldTime=k,v.time end end
        if count>=MAX_AREAS then A.activity[oldest]=nil end
        entry={id=key,map=map,x=(math.min(9,math.floor(x*10))+.5)/10,y=(math.min(9,math.floor(y*10))+.5)/10,time=0,samples={},size=0,peers={},overflow={}}
        A.activity[key]=entry
    end
    return entry
end
function A.RecordActivity(s)
    if A.IsCityMap and A.IsCityMap(s.map) then return end
    local entry=area(s.map,s.x,s.y); local key=s.name:lower(); local guild=A.Key(s.guild)
    entry.time=math.max(entry.time,s.time)
    if entry.samples[key] or entry.size<MAX_SAMPLES then
        if not entry.samples[key] then entry.size=entry.size+1 end
        local previous=entry.samples[key]
        if not previous or s.time>previous.time or s.time==previous.time and not previous.localSeen then
            entry.samples[key]={time=s.time,guild=guild,name=s.guild,localSeen=s.localSeen,reporter=s.reporter}
        end
    else
        local count=0; for _ in pairs(entry.overflow) do count=count+1 end
        if count<16 or entry.overflow[guild] then entry.overflow[guild]=s.time end
        entry.overflowTime=s.time
    end
end
function A.ActivityGroups()
    local now=A.Now(); local result={}
    for key,entry in pairs(A.activity) do
        local guilds={}; local total,capped,last=0,entry.overflowTime and now-entry.overflowTime<(A.HISTORY_TTL or 900) or false,0
        for name,s in pairs(entry.samples) do
            if now-s.time>=(A.HISTORY_TTL or 900) or not A.Watched(s.name) then entry.samples[name]=nil; entry.size=entry.size-1
            else
                local g=guilds[s.guild] or {name=s.name,count=0,time=0,localCount=0}; guilds[s.guild]=g
                g.count=g.count+1; g.localCount=g.localCount+(s.localSeen and 1 or 0); if s.time>=g.time then g.reporter=s.reporter; g.time=s.time end; if s.localSeen then g.localTime=math.max(g.localTime or 0,s.time) end
            end
        end
        for guild,time in pairs(entry.overflow) do
            if now-time>=(A.HISTORY_TTL or 900) or not A.Watched(guild) then entry.overflow[guild]=nil
            else capped=true; last=math.max(last,time) end
        end
        for guild,peer in pairs(entry.peers) do
            if now-peer.time>=(A.HISTORY_TTL or 900) or not A.Watched(peer.name) then entry.peers[guild]=nil
            else
                local g=guilds[guild] or {name=peer.name,count=0,time=0,localCount=0}; guilds[guild]=g
                g.count=math.max(g.count,peer.count); if peer.time>=g.time then g.reporter=peer.reporter; g.time=peer.time end; capped=capped or peer.capped
            end
        end
        local list={}
        for _,g in pairs(guilds) do total=total+g.count; last=math.max(last,g.time); list[#list+1]=g end
        if total>0 then
            table.sort(list,function(a,b) return a.time>b.time or a.time==b.time and a.name<b.name end)
            local shown={}; for i=1,math.min(3,#list) do shown[#shown+1]=list[i].name end
            result[#result+1]={id=key,name=tostring(total)..(capped and '+' or '')..' distinct reported',guild=table.concat(shown,', '),faction=A.Faction()=='Alliance' and 'Horde' or 'Alliance',map=entry.map,x=entry.x,y=entry.y,time=last,reporter=list[1].reporter or 'Unknown observer',activity=true,count=total,capped=capped,guildCount=#list,guilds=list}
        else A.activity[key]=nil end
    end
    table.sort(result,function(a,b) return a.time>b.time or a.time==b.time and a.count>b.count end)
    return result
end
function A.ShareActivity()
    if not A.db.sharing or not A.authority or A.Now()-(A.lastActivityShare or 0)<15 then return end
    A.lastActivityShare=A.Now()
    local groups=A.ActivityGroups()
    -- A bounded shortlist; no player-name burst is queued for a crowd.
    for i=1,math.min(4,#groups) do
        local group=groups[i]
        for j=1,math.min(3,#group.guilds) do
            local g=group.guilds[j]
            if g.localCount>0 and A.Now()-g.localTime<(A.HISTORY_TTL or 900) and not (A.IsCityMap and A.IsCityMap(group.map)) then
                local count=math.min(MAX_SAMPLES,g.localCount)
                A.QueueShared(table.concat({'H',A.Faction(),group.map,math.floor(group.x*10),math.floor(group.y*10),count,group.capped and 1 or 0,g.localTime,OlympusWatchCrypto.Hex(g.name)},'\t'))
            end
        end
    end
end
function A.ReceiveActivity(rest,sender)
    local map,gx,gy,count,capped,time,guild=rest:match('^(%d+)\t(%d+)\t(%d+)\t(%d+)\t([01])\t(%d+)\t([0-9a-f]+)$')
    map,gx,gy,count,time=tonumber(map),tonumber(gx),tonumber(gy),tonumber(count),tonumber(time)
    guild=guild and OlympusWatchCrypto.Unhex(guild)
    if not map or (A.IsCityMap and A.IsCityMap(map)) or map<1 or map>100000 or gx>9 or gy>9 or count<1 or count>MAX_SAMPLES or A.Now()-time>=(A.HISTORY_TTL or 900) or time>A.Now() or not A.Watched(guild) then return end
    local entry=area(map,(gx+.5)/10,(gy+.5)/10); local key=A.Key(guild)
    local size=0; for _ in pairs(entry.peers) do size=size+1 end
    if size>=16 and not entry.peers[key] then return end
    local old=entry.peers[key]
    if not old or time>old.time or time==old.time and count>old.count then entry.peers[key]={name=guild,count=count,capped=capped=='1',time=time,reporter=sender}; entry.time=math.max(entry.time,time) end
end
function A.ActivityTooltip(owner,s)
    GameTooltip:SetOwner(owner,'ANCHOR_RIGHT'); GameTooltip:SetText(s.name)
    GameTooltip:AddLine(A.Location(s),1,1,1)
    GameTooltip:AddLine(s.guildCount..' guilds reported in this area in the last 15 minutes.',1,.65,.2,true)
    for i=1,math.min(3,#s.guilds) do local g=s.guilds[i]; GameTooltip:AddLine(g.name..': '..g.count..' reported',1,1,1) end
    GameTooltip:AddLine('Observer: '..s.reporter..' | Layer unconfirmed',1,1,1,true)
    GameTooltip:AddLine('Observer area, not exact enemy positions. Reports may span layers; nearby cells can overlap.',.8,.8,.8,true)
    GameTooltip:AddLine(s.capped and 'Crowd sampling limit reached. The + means additional players were observed; it is not a census.' or 'Distinct reported players, not a live crowd size. Peer totals use the largest report, not a sum.',.8,.8,.8,true)
    GameTooltip:AddLine('Click a sighting to select it. Map, help and contact actions are in its details.',.4,1,.4,true); GameTooltip:Show()
end
