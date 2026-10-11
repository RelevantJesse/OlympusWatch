local A = OlympusWatch
function A.Location(s)
    local info = C_Map and A.Read(C_Map.GetMapInfo, s.map)
    local zone = info and A.Read(function() return info.name end)
    return string.format("%s %.1f, %.1f", A.Text(zone) and zone or ("Map " .. s.map), s.x*100, s.y*100)
end
function A.Tooltip(owner, s)
    if s.activity and A.ActivityTooltip then A.ActivityTooltip(owner,s); return end
    if s.battle and A.BattleTooltip then A.BattleTooltip(owner,s.battle); return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(s.name)
    GameTooltip:AddLine("<" .. s.guild .. "> - " .. s.faction, 1, .65, .2)
    GameTooltip:AddLine("PvP flagged when seen " .. math.max(0, A.Now()-s.time) .. "s ago", 1, 1, 1)
    GameTooltip:AddLine(A.Location(s), 1, 1, 1)
    GameTooltip:AddLine("Approximate observer location; enemy may have moved.", .8, .8, .8, true)
    GameTooltip:AddLine("Observer: " .. s.reporter .. (s.localSeen and " (you)" or " (peer report)"), .8, .8, .8, true)
    GameTooltip:AddLine("Layer not verified. Report does not confirm current PvP flag.", .8, .8, .8, true)
    GameTooltip:AddLine("Left-click: waypoint. Right-click: prepare group callout.", .4, 1, .4, true)
    GameTooltip:Show()
end
function A.Waypoint(s)
    if s.battle and s.expires<=A.Now() or not s.battle and A.Now()-s.time>=(s.activity and (A.HISTORY_TTL or 900) or A.TTL) then A.Print("That marker expired."); return end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        A.Read(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(s.map, s.x, s.y))
        if C_SuperTrack then A.Read(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
        if OpenWorldMap then A.Read(OpenWorldMap, s.map) end
    else A.Print("Waypoint API unavailable; " .. A.Location(s)) end
end
function A.Callout(s)
    if A.Now()-s.time >= (s.activity and (A.HISTORY_TTL or 900) or A.TTL) then A.Print("That sighting expired."); return end
    if s.activity and A.OpenNearby then A.OpenNearby(s); return end
    if s.activity then
        local text=s.name..' near '..A.Location(s)..'. Gather nearby? Reports are recent observer locations; layer unverified.'
        local channel=A.Read(IsInRaid)==true and '/raid ' or A.Read(IsInGroup)==true and '/party ' or '/say '
        if ChatFrame_OpenChat then ChatFrame_OpenChat(channel..text:sub(1,240)) else A.Print(text) end
        return
    end
    local text = string.format("%s <%s>: PvP flagged when seen %ds ago near %s (observer: %s; layer unverified). Rally here?", s.name, s.guild, A.Now()-s.time, A.Location(s), s.reporter)
    local command = A.Read(IsInRaid) == true and "/raid " or (A.Read(IsInGroup) == true and "/party " or "/say ")
    -- Open a draft: the player chooses whether to send it.
    if ChatFrame_OpenChat then ChatFrame_OpenChat(command .. text:sub(1,240)) else A.Print(text) end
end
local function button(parent, text, x, y, width, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22); b:SetPoint("TOPLEFT", x, y); b:SetText(text); b:SetScript("OnClick", callback)
    return b
end
local function label(parent,text,x,y,width,template)
    local l=parent:CreateFontString(nil,"OVERLAY",template or "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT",x,y); l:SetWidth(width); l:SetJustifyH("LEFT"); l:SetText(text)
    return l
end
function A.GuildEntries(excluded)
    local entries={}
    local source={}; for key,enabled in pairs(excluded and A.db.excludedGuilds or A.db.guilds) do source[key]=enabled end
    if not excluded then
        for key in pairs(A.db.sharedGuilds or {}) do source[key]=true end
        if A.authority then for key,state in pairs(A.authority.state.guilds) do if state=='watch' then source[key]=true end end end
    end
    if excluded and A.authority then for key,state in pairs(A.authority.state.guilds) do if state=='exclude' then source[key]=true end end end
    for key,enabled in pairs(source) do
        local global=A.GlobalExcluded and A.GlobalExcluded(key)
        if enabled and (excluded and not A.Watched(key) or not excluded and A.Watched(key)) then
            entries[#entries+1]={key=key,name=A.db.guildNames[key] or key,source=A.db.guildSources[key],global=global,override=A.db.showOverrides[key]==true}
        end
    end
    table.sort(entries,function(a,b) return a.key<b.key end)
    return entries
end
-- Top-level frames let WoW raise the whole window (including its children)
-- together. Opaque backdrops prevent controls behind it from bleeding through.
function A.BringWindowToFront(frame)
    local highest=frame:GetFrameLevel()
    for _,other in ipairs(A.uiWindows or {}) do
        highest=math.max(highest,other:GetFrameLevel())
    end
    frame:SetFrameLevel(highest+50)
    frame:Raise()
end
function A.ConfigureWindow(frame,control)
    -- Auxiliary windows must stay above the main window even when clicking
    -- its Global button causes WoW to raise that button's top-level parent.
    frame:SetFrameStrata(control and 'FULLSCREEN_DIALOG' or 'DIALOG')
    frame:SetToplevel(true)
    A.uiWindows=A.uiWindows or {}; A.uiWindows[#A.uiWindows+1]=frame
    frame:SetScript('OnShow',function(self) A.BringWindowToFront(self) end)
    frame:SetScript('OnMouseDown',function(self) A.BringWindowToFront(self) end)
end
function A.SetView(view)
    local f=A.window; if not f then return end
    f.view=(view=='guilds' or view=='settings') and view or 'sightings'; A.db.view=f.view
    local guilds,nearby,settings=f.view=='guilds',f.view=='sightings',f.view=='settings'
    for _,widget in ipairs({f.guildPanel,f.edit,f.addGuild,f.excludeGuild,f.guildMode,f.guildFooter,f.resetPersonal,f.resetHint}) do widget:SetShown(guilds) end
    f.nearbyPanel:SetShown(nearby); f.settingsPanel:SetShown(settings)
    A.RefreshUI()
end
function A.Age(time)
    local age=math.max(0,A.Now()-time)
    return age<60 and 'Just now' or math.floor(age/60)..' min ago'
end
function A.EncounterTitle(s)
    local count=s.count or 1
    return count..(s.capped and '+' or '')..(count==1 and not s.capped and ' opponent spotted' or ' opponents reported')
end
function A.RefreshGuildList()
    local f=A.window; local entries=A.GuildEntries(f.showExcluded); local maxOffset=math.max(0,#entries-8)
    f.guildOffset=math.max(0,math.min(f.guildOffset or 0,maxOffset)); f.updatingGuildScroll=true
    f.guildScroll:SetMinMaxValues(0,maxOffset); f.guildScroll:SetValue(f.guildOffset); f.updatingGuildScroll=false
    f.guildScroll:SetShown(maxOffset>0)
    for i,row in ipairs(f.guildRows) do
        local e=entries[f.guildOffset+i]; row.entry=e; row:SetShown(e~=nil)
        if e then
            local faction=A.db.guildFactions[e.key] or {}
            row.name:SetText(e.name)
            row.faction:SetText(faction.Alliance and (faction.Horde and 'Both' or 'Alliance') or faction.Horde and 'Horde' or 'Unknown')
            local visibility=e.override and 'Shown by you' or e.global and 'Excluded globally' or A.db.excludedGuilds[e.key] and 'Hidden by you' or 'Visible'
            row.visibility:SetText(visibility)
            row.visibility:SetTextColor(e.override and .4 or visibility=='Visible' and .5 or 1,e.override and .8 or visibility=='Visible' and .9 or .7,e.override and 1 or .4)
            row.source:SetText(e.source=='seen' and 'Discovered' or e.source=='shared' and 'Shared' or A.authority and A.authority.state.guilds[e.key]=='watch' and 'Approved' or 'Local')
            row.action:SetText(f.showExcluded and (e.global and 'Show anyway' or 'Restore') or 'Hide')
        end
    end
    f.guildEmpty:SetShown(#entries==0)
    f.guildEmpty:SetText(f.showExcluded and 'No hidden or excluded guilds.' or "No guilds yet. Names containing 'olympus' are discovered when you see a member.")
    f.guildMode:SetText(f.showExcluded and 'Show visible' or 'Show hidden / excluded')
    f.guildFooter:SetText(#entries..(f.showExcluded and ' hidden / excluded' or ' visible')..' | Your choices affect only you.')
    f.guildTab:SetText('Guilds ('..#A.GuildEntries(false)..')')
end
function A.CreateUI()
    local f=CreateFrame('Frame','OlympusWatchWindow',UIParent,'BackdropTemplate'); A.window=f
    A.ConfigureWindow(f); f:SetSize(740,460); f:SetPoint('CENTER'); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart',f.StartMoving)
    f:SetScript('OnDragStop',function(self) self:StopMovingOrSizing(); local point,_,relative,x,y=self:GetPoint(); A.db.position={point,relative,x,y} end)
    local p=A.db.position
    if type(p)=='table' and type(p[1])=='string' and type(p[2])=='string' and type(p[3])=='number' and type(p[4])=='number' then f:ClearAllPoints(); f:SetPoint(p[1],UIParent,p[2],p[3],p[4]) end
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}}); f:SetBackdropColor(.06,.06,.08,1)
    label(f,'Olympus Watch',16,-15,520,'GameFontNormalLarge')
    f.closeButton=button(f,'Close',645,-12,78,function() A.db.shown=false; f:Hide() end)
    f.status=label(f,'',16,-43,700)
    f.sightingTab=button(f,'Nearby',16,-68,135,function() A.SetView('sightings') end)
    f.guildTab=button(f,'Guilds',159,-68,135,function() A.SetView('guilds') end)
    f.settingsTab=button(f,'Settings',302,-68,110,function() A.SetView('settings') end)
    f.tabMarker=f:CreateTexture(nil,'OVERLAY'); f.tabMarker:SetSize(135,2); f.tabMarker:SetColorTexture(1,.75,.2,1)
    f.nearbyPanel=CreateFrame('Frame',nil,f); f.nearbyPanel:SetPoint('TOPLEFT',16,-106); f.nearbyPanel:SetSize(708,340)
    label(f.nearbyPanel,'Your zone | sightings from the last 15 minutes',0,0,340,'GameFontNormalSmall')
    f.rows={}; f.page=1
    for i=1,6 do
        local r=CreateFrame('Button',nil,f.nearbyPanel); r:SetPoint('TOPLEFT',0,-25-(i-1)*43); r:SetSize(342,41); r:RegisterForClicks('LeftButtonUp','RightButtonUp')
        local bg=r:CreateTexture(nil,'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(1,1,1,i%2==0 and .035 or .06)
        r.selected=r:CreateTexture(nil,'BACKGROUND'); r.selected:SetAllPoints(); r.selected:SetColorTexture(.8,.5,.15,.22); r.selected:Hide()
        r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
        r.label=label(r,'',8,-5,326,'GameFontNormalSmall'); r.subtitle=label(r,'',8,-23,326)
        r:SetScript('OnClick',function(self,mouse)
            if not self.s then return end
            if A.OpenNearby then A.OpenNearby(self.s)
            elseif mouse=='RightButton' then A.Callout(self.s) else A.Waypoint(self.s) end
        end)
        r:SetScript('OnEnter',function(self) if self.s then A.Tooltip(self,self.s) end end); r:SetScript('OnLeave',function() GameTooltip:Hide() end)
        f.rows[i]=r
    end
    f.nearbyEmpty=label(f.nearbyPanel,'',8,-60,325)
    f.previous=button(f.nearbyPanel,'Previous',0,-291,88,function() f.page=math.max(1,f.page-1); A.RefreshUI() end)
    f.next=button(f.nearbyPanel,'Next',96,-291,88,function() f.page=f.page+1; A.RefreshUI() end)
    f.footer=label(f.nearbyPanel,'',0,-320,342)
    f.detailPanel=CreateFrame('Frame',nil,f.nearbyPanel); f.detailPanel:SetPoint('TOPLEFT',362,0); f.detailPanel:SetSize(346,335)
    local dp=f.detailPanel
    label(dp,'Encounter details',0,0,338,'GameFontNormalSmall')
    f.detail=label(dp,'',0,-27,338,'GameFontNormalLarge')
    f.detailLocation=label(dp,'',0,-58,338); f.detailGuild=label(dp,'',0,-83,338)
    f.observer=label(dp,'',0,-116,338)
    f.detailLayer=label(dp,'Layer unconfirmed',0,-149,338,'GameFontNormalSmall')
    f.detailNote=label(dp,'Choose a sighting on the left to view its location and contact its reporter.',0,-173,338)
    f.mapAction=button(dp,'Map',0,-222,152,function() if f.selected then A.Waypoint(f.selected) end end)
    f.helpAction=button(dp,'Request help',164,-222,172,function() if f.selected then A.RequestHelp(f.selected) end end)
    f.whisperAction=button(dp,'Whisper reporter',0,-253,152,function() if f.selected then A.EncounterContact(f.selected,false) end end)
    f.inviteAction=button(dp,'Request invite',164,-253,172,function() if f.selected then A.EncounterContact(f.selected,true) end end)
    f.actionHint=label(dp,'',0,-284,338); f.inviteStatus=label(dp,'No pending invite requests',0,-322,338)
    f.requestPanel=CreateFrame('Frame',nil,f); f.requestPanel:SetPoint('TOPLEFT',16,-456); f.requestPanel:SetSize(708,112)
    label(f.requestPanel,'Party invite requests | choose whom to invite',0,0,700,'GameFontNormalSmall'); f.requests={}
    for i=1,3 do
        local row=CreateFrame('Frame',nil,f.requestPanel); row:SetPoint('TOPLEFT',0,-24-(i-1)*28); row:SetSize(708,26)
        row.text=label(row,'',8,-5,440)
        button(row,'Invite',455,0,110,function() if row.request then A.AcceptEncounterInvite(row.request.name) end end)
        button(row,'Dismiss',575,0,110,function() if row.request then A.inviteRequests[row.request.name]=nil; A.RefreshUI() end end)
        f.requests[i]=row
    end
    f.edit=CreateFrame('EditBox',nil,f,'InputBoxTemplate'); f.edit:SetSize(280,24); f.edit:SetPoint('TOPLEFT',22,-109); f.edit:SetAutoFocus(false); f.edit:SetMaxLetters(96)
    f.editHint=label(f.edit,'Exact guild name',8,-5,255); f.editHint:SetTextColor(.65,.65,.65)
    f.edit:SetScript('OnTextChanged',function(self) f.editHint:SetShown(self:GetText()=='') end)
    f.edit:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    f.addGuild=button(f,'Add locally',315,-109,115,function() A.Command('add '..f.edit:GetText()); f.edit:ClearFocus() end)
    f.excludeGuild=button(f,'Hide guild',439,-109,115,function() A.Command('remove '..f.edit:GetText()); f.edit:ClearFocus() end)
    f.edit:SetScript('OnEnterPressed',function(self) A.Command('add '..self:GetText()); self:ClearFocus() end)
    f.guildPanel=CreateFrame('Frame',nil,f); f.guildPanel:SetPoint('TOPLEFT',16,-154); f.guildPanel:SetSize(708,244)
    for _,col in ipairs({{'Guild',8,194},{'Faction',207,80},{'Visibility',292,125},{'Source',422,90},{'Action',520,116}}) do label(f.guildPanel,col[1],col[2],0,col[3],'GameFontNormalSmall') end
    f.guildRows={}; f.guildOffset=0; f.showExcluded=false
    for i=1,8 do
        local row=CreateFrame('Frame',nil,f.guildPanel); row:SetPoint('TOPLEFT',0,-25-(i-1)*26); row:SetSize(686,26)
        local bg=row:CreateTexture(nil,'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(1,1,1,i%2==0 and .035 or .075)
        row.name=label(row,'',8,-6,194); row.faction=label(row,'',207,-6,80); row.visibility=label(row,'',292,-6,125); row.source=label(row,'',422,-6,90)
        row.action=button(row,'Hide',520,-2,115,function() if row.entry then A.Command((f.showExcluded and 'add ' or 'remove ')..row.entry.name) end end)
        row:EnableMouse(true); row:EnableMouseWheel(true)
        row:SetScript('OnMouseWheel',function(_,delta) f.guildOffset=f.guildOffset-delta; A.RefreshGuildList() end)
        row:SetScript('OnEnter',function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(self.entry.name)
            GameTooltip:AddLine(self.entry.override and 'Shown only for you despite the global exclusion. Hide clears this override.' or self.entry.global and 'Excluded globally. Show anyway restores visibility only for you.' or f.showExcluded and 'Hidden by you. Restore shows this guild again.' or 'Visible to you. Hide affects only your addon.',1,1,1,true); GameTooltip:Show()
        end); row:SetScript('OnLeave',function() GameTooltip:Hide() end); f.guildRows[i]=row
    end
    f.guildEmpty=label(f.guildPanel,'',16,-72,650)
    f.guildScroll=CreateFrame('Slider','OlympusWatchGuildScrollBar',f.guildPanel); f.guildScroll:SetPoint('TOPRIGHT',-3,-25); f.guildScroll:SetSize(16,205); f.guildScroll:SetOrientation('VERTICAL'); f.guildScroll:SetValueStep(1); f.guildScroll:SetObeyStepOnDrag(true)
    local track=f.guildScroll:CreateTexture(nil,'BACKGROUND'); track:SetAllPoints(); track:SetColorTexture(0,0,0,.5)
    local thumb=f.guildScroll:CreateTexture(nil,'OVERLAY'); thumb:SetSize(14,28); thumb:SetColorTexture(.8,.5,.2,.9); f.guildScroll:SetThumbTexture(thumb)
    f.guildScroll:SetScript('OnValueChanged',function(_,value) if not f.updatingGuildScroll then f.guildOffset=math.floor(value+.5); A.RefreshGuildList() end end)
    f.guildPanel:EnableMouseWheel(true); f.guildPanel:SetScript('OnMouseWheel',function(_,delta) f.guildOffset=f.guildOffset-delta; A.RefreshGuildList() end)
    f.guildMode=button(f,'Show hidden / excluded',16,-406,190,function() f.showExcluded=not f.showExcluded; f.guildOffset=0; A.RefreshGuildList() end)
    f.guildFooter=label(f,'',218,-411,505)
    f.resetPersonal=button(f,'Reset my visibility choices',16,-434,210,function() A.ResetPersonalPreferences() end)
    f.resetPersonal:SetScript('OnEnter',function(self) GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText('Reset my visibility choices'); GameTooltip:AddLine('Clear personal hides and Show anyway overrides for this ruleset. Keep discoveries and verified global changes, then request peer updates.',1,1,1,true); GameTooltip:Show() end)
    f.resetPersonal:SetScript('OnLeave',function() GameTooltip:Hide() end)
    f.resetHint=label(f,'Current ruleset only. Shared exclusions stay in place.',238,-439,484)
    f.settingsPanel=CreateFrame('Frame',nil,f); f.settingsPanel:SetPoint('TOPLEFT',16,-110); f.settingsPanel:SetSize(708,330)
    local sp=f.settingsPanel
    label(sp,'Detection and sharing',0,0,690,'GameFontNormalLarge')
    f.toggle=button(sp,'',0,-42,155,function() A.Command(A.db.enabled and 'off' or 'on') end); label(sp,'Collect sightings of visible, flagged opponents.',170,-47,510)
    f.share=button(sp,'',0,-83,155,function() A.Command('sharing '..(A.db.sharing and 'off' or 'on')) end); label(sp,'Send and receive guilds, sightings and help requests.',170,-88,510)
    f.network=button(sp,'',0,-124,155,function() A.Command('network '..(A.db.network and 'off' or 'on')) end); label(sp,'Connect across guilds. Party and guild sharing remains separate.',170,-129,510)
    f.alert=button(sp,'',0,-165,155,function() A.Command('alerts '..(A.db.alerts and 'off' or 'on')) end); label(sp,'Show sighting notices and play detection sounds.',170,-170,510)
    button(sp,'Clear encounter history',0,-220,210,function() A.Command('clear') end); label(sp,'Clear this session\'s sightings and requests; retain guild choices.',225,-225,480)
    f.networkInfo=label(sp,'',0,-280,690)
    UISpecialFrames[#UISpecialFrames+1]='OlympusWatchWindow'
    f:SetShown(A.db.shown); A.SetView(A.db.view or 'sightings')
end
function A.RefreshUI()
    local f=A.window; if not f then return end
    f.tabMarker:ClearAllPoints(); f.tabMarker:SetPoint('TOPLEFT',f.view=='guilds' and 159 or f.view=='settings' and 302 or 16,-93); f.tabMarker:SetSize(f.view=='settings' and 110 or 135,2)
    local list=A.NearbyActivity and A.NearbyActivity() or A.ActivityGroups and A.ActivityGroups() or A.Sorted(); f.currentList=list
    local pages=math.max(1,math.ceil(#list/6)); f.page=math.max(1,math.min(f.page,pages))
    local network=A.db.sharing and (A.db.network and (A.ChannelID() and 'Connected' or 'Connecting') or 'Party / guild sharing') or 'Sharing off'
    local map=A.CurrentMap and A.CurrentMap(); local info=map and C_Map and A.Read(C_Map.GetMapInfo,map)
    local zone=info and info.name or 'Current zone'
    f.status:SetText((A.InCity and A.InCity() and 'Sightings disabled in cities' or not A.InWorld() and 'Paused in instance' or zone)..' | '..network..' | '..A.Scope()..' / '..(A.Faction() or 'Unknown'))
    A.RefreshGuildList(); f.sightingTab:SetText('Nearby ('..#list..')')
    f.toggle:SetText('Scanning: '..(A.db.enabled and 'on' or 'off')); f.share:SetText('Sharing: '..(A.db.sharing and 'on' or 'off')); f.network:SetText('Network: '..(A.db.network and 'on' or 'off')); f.alert:SetText('Alerts: '..(A.db.alerts and 'on' or 'off'))
    f.networkInfo:SetText('Network channel: '..(A.NetworkName() or 'Unavailable')..'. Updates depend on reachable online peers.')
    for i,r in ipairs(f.rows) do
        local s=list[(f.page-1)*6+i]; r.s=s; r.area=s; r:SetShown(s~=nil)
        if s then
            r.label:SetText((s.help and 'HELP | ' or '')..A.EncounterTitle(s)..' | '..A.Age(s.time))
            r.subtitle:SetText(string.format('Approx. %.0f, %.0f | %s',s.x*100,s.y*100,s.guild))
            r.selected:SetShown(f.selected and f.selected.id==s.id or false)
        end
    end
    f.nearbyEmpty:SetShown(#list==0); f.nearbyEmpty:SetText(A.InCity and A.InCity() and 'Sightings are disabled in cities. Guild discovery still works.' or not A.InWorld() and 'Sightings resume outdoors.' or not A.db.enabled and 'Scanning is off. Enable it in Settings.' or 'No sightings in this zone in the last 15 minutes.')
    f.previous:SetShown(f.view=='sightings' and pages>1); f.next:SetShown(f.view=='sightings' and pages>1)
    f.previous:SetEnabled(f.page>1); f.next:SetEnabled(f.page<pages)
    f.footer:SetText(pages>1 and 'Page '..f.page..'/'..pages..' | Select a sighting for details.' or #list>0 and 'Select a sighting for location and reporter.' or 'Only recent outdoor encounters appear here.')
    if not A.RefreshControlUI then
        for _,b in ipairs({f.mapAction,f.helpAction,f.whisperAction,f.inviteAction}) do b:SetEnabled(false) end
        f.detail:SetText('Select a sighting'); f.requestPanel:Hide()
    end
end
function A.Command(message)
    if not A.db then return end
    local cmd,arg=message:match("^%s*(%S*)%s*(.-)%s*$"); cmd=cmd:lower()
    if cmd=="" or cmd=="show" then A.db.shown=true; A.SetView("sightings"); A.window:Show()
    elseif cmd=="hide" then A.db.shown=false; A.window:Hide()
    elseif cmd=="add" or cmd=="remove" then
        if not A.Text(arg) then A.Print("Enter an exact guild name, e.g. /ow add Olympus II"); return end
        local key=A.Key(arg); if key=="" then return end
        if cmd=="add" then
            A.db.guilds[key]=true; A.db.excludedGuilds[key]=nil; A.db.showOverrides[key]=A.GlobalExcluded and A.GlobalExcluded(arg) and true or nil; A.db.guildNames[key]=arg; A.db.guildSources[key]="manual"
        else
            A.db.guilds[key]=nil; A.db.excludedGuilds[key]=true; A.db.showOverrides[key]=nil
        end
        A.Print((cmd=="add" and "Showing locally (your preference only): " or "Hidden locally; excluded from your auto-discovery: ")..arg)
    elseif cmd=="on" or cmd=="off" then A.db.enabled=cmd=="on"; if not A.db.enabled then A.pending={} end
    elseif cmd=="sharing" or cmd=="network" or cmd=="alerts" then
        if arg~="on" and arg~="off" then A.Print("Use /ow "..cmd.." on|off"); return end
        A.db[cmd]=arg=="on"
        if cmd=="sharing" then A.pending={} end
        if cmd=="network" then
            if A.db.network then A.JoinNetwork() else local name=A.NetworkName(); if name then A.Read(LeaveChannelByName,name) end end
        end
    elseif cmd=="clear" then A.sightings={}; A.pending={}; A.activity={}; A.helpRequests={}; A.inviteRequests={}
    elseif cmd=="reset-personal" then A.ResetPersonalPreferences()
    elseif cmd=="debug" then
        A.Print(string.format("Faction=%s world=%s enabled=%s sharing=%s networkID=%s; detected=%d received=%d sent=%d restricted=%d lastSend=%s",tostring(A.Faction()),tostring(A.InWorld()),tostring(A.db.enabled),tostring(A.db.sharing),tostring(A.ChannelID()),A.stats.detected,A.stats.received,A.stats.sent,A.stats.restricted,tostring(A.lastSendResult)))
        A.Print("Enable enemy nameplates (V). Reports are approximate; layer and current flag are unverified.")
    else A.Print("/ow show|hide|on|off|add <guild>|remove <guild>|sharing on|off|network on|off|alerts on|off|clear|debug") end
    A.Changed()
end
SLASH_OLYMPUSWATCH1="/ow"; SLASH_OLYMPUSWATCH2="/olympuswatch"; SlashCmdList.OLYMPUSWATCH=A.Command
