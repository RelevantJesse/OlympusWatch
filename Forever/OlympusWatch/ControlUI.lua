local A=OlympusWatch
-- Old signed battle records remain readable in history; no separate encounter window.
function A.BattleView(e)
    return {name=e.name,guild='',faction=e.faction,map=e.map,x=e.x/10000,y=e.y/10000,time=e.time,reporter=e.contact,expires=e.expires,battle=e}
end
function A.OpenNearby(selected)
    local f=A.window; if not f then return end
    A.nearbyWindow=f
    if type(selected)=='table' then
        f.selected=selected
        local groups=A.NearbyActivity()
        for i,s in ipairs(groups) do if s.id==selected.id then f.page=math.ceil(i/6); break end end
    end
    A.db.shown=true; A.SetView('sightings'); f:Show(); A.BringWindowToFront(f)
end
function A.OpenBattles() A.OpenNearby() end
function A.RefreshControlUI()
    local f=A.window; if not f then return end
    A.nearbyWindow=f
    local selected=f.selected; f.selected=nil
    for _,s in ipairs(f.currentList or {}) do if selected and selected.id==s.id then f.selected=s; break end end
    local s=f.selected; local fresh=A.EncounterFresh(s)
    local reporter=s and (s.help and s.help.reporter or s.reporter)
    local contact=fresh and A.db.sharing and A.Text(reporter) and reporter~=A.PlayerName() and reporter~='Unknown observer'
    local localFresh=false
    for _,g in ipairs(s and s.guilds or {}) do if g.localTime and A.Now()-g.localTime<120 then localFresh=true; break end end
    f.mapAction:SetEnabled(fresh==true)
    f.helpAction:SetEnabled(fresh==true and localFresh and A.db.sharing and (not A.lastHelp or A.Now()-A.lastHelp>=60))
    f.whisperAction:SetEnabled(fresh==true and A.Text(reporter) and reporter~=A.PlayerName() and reporter~='Unknown observer')
    f.inviteAction:SetEnabled(contact==true and (not A.lastInviteRequest or A.Now()-A.lastInviteRequest>=30))
    f.detail:SetText(s and A.EncounterTitle(s) or 'Select a sighting')
    f.detailLocation:SetText(s and 'Approx. '..A.Location(s)..' | '..A.Age(s.time) or '')
    f.detailGuild:SetText(s and 'Guild: '..s.guild:sub(1,88)..(#s.guild>88 and '...' or '') or '')
    f.observer:SetText(s and (reporter==A.PlayerName() and 'Reported by you' or 'Reported by '..reporter) or '')
    f.detailLayer:SetText(s and 'Layer unconfirmed' or '')
    f.detailNote:SetText(s and (A.Now()-s.time>=120 and 'Older report: the opponents may have moved. Contact the reporter before traveling.' or 'Approximate observer location. Opponents may have moved or changed PvP status.') or 'Choose a sighting on the left to see its location, guild and reporter.')
    f.actionHint:SetText(not s and '' or s.help and 'Help requested | '..math.ceil((300-A.Now()+s.help.time)/60)..' min remaining' or not A.db.sharing and 'Enable Sharing in Settings to request help or an invite.' or not localFresh and 'Request help requires your own sighting from the last 2 minutes.' or 'Request help asks nearby players to join you for 5 minutes.')
    for _,row in ipairs(f.rows) do row.selected:SetShown(s and row.s and row.s.id==s.id or false) end
    local requests={}; local map=A.CurrentMap()
    for name,r in pairs(A.inviteRequests) do
        if A.Now()-r.time>=120 then A.inviteRequests[name]=nil
        elseif not A.InCity() and A.InWorld() and A.ZoneMap(r.map)==A.ZoneMap(map) then requests[#requests+1]=r end
    end
    table.sort(requests,function(a,b) return a.time>b.time or a.time==b.time and a.name<b.name end)
    local visible=f.view=='sightings' and #requests>0
    f.requestPanel:SetShown(visible); f:SetSize(740,visible and 578 or 460)
    f.inviteStatus:SetText(#requests==0 and 'No pending invite requests' or #requests..' pending invite requests (expire after 2 min)')
    for i,row in ipairs(f.requests) do
        row.request=requests[i]; row:SetShown(row.request~=nil)
        if row.request then row.text:SetText(row.request.name..' | '..A.Age(row.request.time)) end
    end
end
local originalCommand=A.Command
function A.Command(message)
    local cmd=message:match('^%s*(%S*)'):lower()
    if cmd=='battles' or cmd=='operations' or cmd=='nearby' then A.OpenNearby()
    elseif cmd=='settings' then A.SetView('settings'); A.db.shown=true; A.window:Show()
    elseif cmd=='admin' then A.Print('Shared guild management is in the owner companion app.')
    else originalCommand(message) end
end
SlashCmdList.OLYMPUSWATCH=A.Command
local originalRefresh=A.RefreshUI
function A.RefreshUI() originalRefresh(); A.RefreshControlUI() end
