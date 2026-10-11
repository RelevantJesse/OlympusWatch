local addonName = ...
OlympusWatch = { sightings = {}, units = {}, pending = {}, stats = { detected = 0, received = 0, sent = 0, restricted = 0 }, PREFIX = "OlympusWatch1", TTL = 120 }
local A = OlympusWatch
local frame = CreateFrame("Frame")
A.frame = frame
local function secret(v) return issecretvalue and issecretvalue(v) end
function A.Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok or secret(a) or secret(b) then A.stats.restricted = A.stats.restricted + 1; return nil end
    return a, b
end
function A.Now() return GetServerTime() end
function A.Text(v, limit)
    return type(v) == "string" and #v > 0 and #v <= (limit or 96) and not v:find("[%c|]")
end
function A.Key(v) return v:match("^%s*(.-)%s*$"):lower() end
function A.Watched(guild)
    if not A.Text(guild) then return false end
    local key=A.Key(guild)
    if A.authority and (not A.authority.ready or A.authority.error) then return false end
    local global=A.authority and A.authority.state.guilds[key]
    local known=A.db.guilds[key]==true or A.db.sharedGuilds and A.db.sharedGuilds[key]~=nil or global=='watch'
    return known and not A.db.excludedGuilds[key] and (global~='exclude' or A.db.showOverrides[key]==true)
end
-- Reset only personal visibility for the active ruleset. Signed history is retained.
function A.ResetPersonalPreferences()
    if not A.db then return end
    for key in pairs(A.db.excludedGuilds) do
        if A.db.guildNames[key] or A.db.sharedGuilds and A.db.sharedGuilds[key] then A.db.guilds[key]=true end
    end
    A.db.excludedGuilds={}; A.db.showOverrides={}
    if A.authority then A.authority.lastSync=nil end
    if A.window then A.window.guildOffset=0; A.window.showExcluded=false end
    A.Print('Personal hides and show overrides reset for '..A.Scope()..'. The verified global list is retained.')
    if A.db.enabled and A.db.sharing and A.InWorld() then
        if A.JoinNetwork then A.JoinNetwork() end
        if A.SharedTick then A.SharedTick() end
        A.Print('Peer updates requested. New changes require an online peer with the latest list.')
    else A.Print('Enable scanning and sharing outside instances to resume peer updates.') end
    A.Changed()
end
function A.DiscoverGuild(guild,faction)
    if not A.Text(guild) then return end
    if A.authority and (not A.authority.ready or A.authority.error) then return end
    local key=A.Key(guild)
    if not key:find('olympus',1,true) and not A.Watched(guild) then return end
    local factions=A.db.guildFactions[key] or {}; A.db.guildFactions[key]=factions
    local changed=(faction=='Alliance' or faction=='Horde') and not factions[faction]
    if changed then factions[faction]=true; if A.RefreshUI then A.RefreshUI() end end
    if key:find('olympus',1,true) and A.ShareGuild and (changed or not A.db.sharedGuilds[key]) then A.ShareGuild(guild) end
    if A.GlobalExcluded and A.GlobalExcluded(guild) then return end
    if not key:find("olympus",1,true) or A.db.excludedGuilds[key] then return end
    A.db.guildNames[key]=guild
    if A.db.guilds[key] then return end
    A.db.guilds[key]=true
    A.db.guildSources[key]="seen"
    -- A local chat notice, once per newly discovered guild, independent of alerts.
    A.Print("Auto-added guild <"..guild.."> after seeing a member in the world.")
    if A.RefreshUI then A.RefreshUI() end
end
function A.Faction() return A.Read(UnitFactionGroup, "player") end
function A.Opponent(faction)
    local own = A.Faction()
    return (own == "Alliance" and faction == "Horde") or (own == "Horde" and faction == "Alliance")
end
function A.InWorld() return A.Read(IsInInstance) == false end
function A.PlayerName()
    local name, realm = A.Read(UnitFullName, "player")
    if not A.Text(name) then return nil end
    if not A.Text(realm) then realm = A.Read(GetNormalizedRealmName) end
    return A.Text(realm) and (name .. "-" .. realm) or name
end
function A.Ruleset()
    local rules=Enum and Enum.GameRule
    local api=C_GameRules and C_GameRules.IsGameRuleActive
    local hc=rules and rules.HardcoreRuleset and A.Read(api,rules.HardcoreRuleset)
    local rp=rules and rules.RPRuleset and A.Read(api,rules.RPRuleset)
    local pvp=rules and rules.PvPRuleset and A.Read(api,rules.PvPRuleset)
    if hc==true then return 'hardcore' elseif rp==true then return 'rp' elseif pvp==true then return 'pvp' end
    local name=A.Read(GetRealmName) or A.Read(GetNormalizedRealmName)
    name=type(name)=='string' and name:lower() or ''
    if name:find('hardcore',1,true) then return 'hardcore' end
    if name:find('roleplay',1,true) or name:match('%f[%a]rp%f[%A]') then return 'rp' end
    if name:find('pvp',1,true) then return 'pvp' end
    if name:find('pve',1,true) or name:find('normal',1,true) then return 'pve' end
    if hc==false and rp==false and pvp==false then return 'pve' end
    return 'unknown'
end
function A.Scope() return A.activeRuleset or A.Ruleset() end
function A.NetworkName()
    local faction = A.Faction()
    if faction == "Alliance" or faction == "Horde" then return "OlympusWatch" .. A.Scope() .. faction end
end
function A.ChannelID()
    if not A.db.network then return nil end
    local name = A.NetworkName()
    local id = name and A.Read(GetChannelName, name)
    return type(id) == "number" and id > 0 and id or nil
end
function A.JoinNetwork()
    local name = A.NetworkName()
    if A.db.network and name and not A.ChannelID() then A.Read(JoinTemporaryChannel, name) end
end
function A.Print(text) print("|cffef9933OlympusWatch:|r " .. text) end
function A.Changed() if A.RefreshUI then A.RefreshUI() end; if A.RefreshMap then A.RefreshMap() end end
function A.Prune()
    local now = A.Now()
    for key, s in pairs(A.sightings) do
        if now - s.time >= A.TTL or not A.Watched(s.guild) or not A.Opponent(s.faction) then
            A.sightings[key] = nil; A.pending[key] = nil
        end
    end
end
function A.Sorted()
    A.Prune()
    local list = {}; for _, s in pairs(A.sightings) do list[#list + 1] = s end
    table.sort(list, function(a,b) if a.time == b.time then return a.name < b.name end; return a.time > b.time end)
    return list
end
function A.Store(s)
    if A.IsCityMap and A.IsCityMap(s.map) then return false end
    if A.RecordActivity then A.RecordActivity(s) end
    A.Prune()
    local key = s.name:lower()
    local previous = A.sightings[key]
    -- Same-second reports cannot overwrite a local observation with a peer's report.
    if previous and (s.time < previous.time or (s.time == previous.time and (previous.localSeen or not s.localSeen))) then return false end
    if not previous then
        local count, oldestKey, oldest = 0, nil, math.huge
        for k, v in pairs(A.sightings) do count = count + 1; if v.time < oldest then oldestKey, oldest = k, v.time end end
        if count >= 100 then A.sightings[oldestKey] = nil; A.pending[oldestKey] = nil end
        if A.db.alerts and (not A.CurrentMap or A.ZoneMap(s.map)==A.ZoneMap(A.CurrentMap())) and (not A.InCity or not A.InCity()) and (not A.lastSightingAlert or A.Now()-A.lastSightingAlert>=15) then
            A.lastSightingAlert=A.Now()
            A.Print(s.name .. " <" .. s.guild .. "> spotted; PvP flagged when seen" .. (s.localSeen and "." or " (reported by " .. s.reporter .. ")."))
            if PlaySound and SOUNDKIT then A.Read(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
        end
    end
    A.sightings[key] = s
    return true
end
function A.Observe(unit)
    if not A.db.enabled or not A.InWorld() then return end
    if A.Read(UnitIsPlayer, unit) ~= true or A.Read(UnitIsVisible, unit) ~= true then return end
    local guild = A.Read(GetGuildInfo, unit)
    A.DiscoverGuild(guild,A.Read(UnitFactionGroup,unit))
    if A.InCity and A.InCity() then return end
    if A.Read(UnitIsPVP, unit) ~= true then return end
    local faction = A.Read(UnitFactionGroup, unit)
    if not A.Opponent(faction) then return end
    if not A.Watched(guild) then return end
    local name, realm = A.Read(UnitFullName, unit)
    if not A.Text(name) then return end
    if not A.Text(realm) then realm = A.Read(GetNormalizedRealmName) end
    if A.Text(realm) then name = name .. "-" .. realm end
    if not A.Text(name) then return end
    local map = C_Map and A.Read(C_Map.GetBestMapForUnit, "player")
    local pos = map and A.Read(C_Map.GetPlayerMapPosition, map, "player")
    if not pos then return end
    local x, y = A.Read(pos.GetXY, pos)
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then return end
    local reporter = A.PlayerName(); if not reporter then return end
    local s = {name = name, guild = guild, faction = faction, map = map, x = x, y = y, time = A.Now(), reporter = reporter, localSeen = true}
    if A.Store(s) then
        A.stats.detected = A.stats.detected + 1
        -- Coalesce repeated scans; never relay peer reports.
        A.pending[name:lower()] = s
    end
end
function A.Encode(s)
    return table.concat({"1", A.Faction(), s.faction, s.name, s.guild, tostring(s.map), string.format("%.4f",s.x), string.format("%.4f",s.y), tostring(s.time), "PVP"}, "\t")
end
local function integer(v, lo, hi) return type(v) == "number" and v == v and v >= lo and v <= hi and v == math.floor(v) end
function A.Decode(message, sender)
    if not A.Text(sender) or type(message) ~= "string" or #message > 255 then return nil end
    local fields = {}; for v in (message .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = v end
    if #fields ~= 10 or fields[1] ~= "1" or fields[2] ~= A.Faction() or not A.Opponent(fields[3]) or fields[10] ~= "PVP" then return nil end
    if not A.Text(fields[4]) or not A.Watched(fields[5]) then return nil end
    local map, x, y, timestamp = tonumber(fields[6]), tonumber(fields[7]), tonumber(fields[8]), tonumber(fields[9])
    if not integer(map, 1, 100000) or not integer(timestamp, 1, A.Now()) or A.Now() - timestamp >= A.TTL then return nil end
    if not x or not y or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    if not C_Map or not A.Read(C_Map.GetMapInfo, map) then return nil end
    return {name=fields[4], guild=fields[5], faction=fields[3], map=map, x=x, y=y, time=timestamp, reporter=sender, localSeen=false}
end
function A.Receive(prefix, message, channel, sender, target, zoneID, localID, channelName)
    if type(message)~='string' then return end
    local scope,payload=message:match('^R1\t([^\t]+)\t(.*)$')
    if scope~=A.Scope() or A.Scope()=='unknown' then return end
    message=payload
    if not A.db.enabled or not A.db.sharing or not A.InWorld() then return end
    if secret(prefix) or secret(message) or secret(channel) or secret(sender) or secret(localID) or secret(channelName) then return end
    if prefix ~= A.PREFIX or sender == A.PlayerName() then return end
    if not A.Text(sender) then return end
    local permitted = channel == "GUILD" or channel == "PARTY" or channel == "RAID" or channel == "WHISPER" and message:match('^J\t')~=nil
    if channel == "CHANNEL" then
        local id = A.ChannelID()
        permitted = id and localID == id and channelName == A.NetworkName()
    end
    if not permitted then return end
    -- Bound incoming work globally, including malformed messages.
    local now = A.Now()
    if A.receiveSecond ~= now then A.receiveSecond, A.receiveCount = now, 0 end
    A.receiveCount = A.receiveCount + 1; if A.receiveCount > 30 then return end
    if A.ReceiveShared and A.ReceiveShared(message,sender) then return end
    local s = A.Decode(message, sender)
    if s and A.Store(s) then A.stats.received = A.stats.received + 1; A.Changed() end
end
function A.Broadcast(message)
    if A.Scope()=='unknown' then return end
    message='R1\t'..A.Scope()..'\t'..message
    if not A.db.enabled or not A.db.sharing or not A.InWorld() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
    if #message>255 or A.Read(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) == true or A.Read(C_ChatInfo.InChatMessagingLockdown) == true then return false end
    local destinations = {}
    if A.Read(IsInRaid) == true then destinations[#destinations+1] = {"RAID"}
    elseif A.Read(IsInGroup) == true then destinations[#destinations+1] = {"PARTY"} end
    if A.Read(IsInGuild) == true then destinations[#destinations+1] = {"GUILD"} end
    local id = A.ChannelID(); if id then destinations[#destinations+1] = {"CHANNEL", tostring(id)} end
    local delivered=false
    for _, d in ipairs(destinations) do
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, A.PREFIX, message, d[1], d[2])
        if ok and (result == 0 or result == true) then A.stats.sent = A.stats.sent + 1; delivered=true end
        A.lastSendResult = ok and tostring(result) or "API error"
    end
    return delivered
end
function A.SendPending()
    if not A.db.enabled or not A.db.sharing or not A.InWorld() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
    if A.Read(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) == true or A.Read(C_ChatInfo.InChatMessagingLockdown) == true then return end
    local now = A.Now(); A.lastSent = A.lastSent or {}
    local key, s
    for k,v in pairs(A.pending) do if now - (A.lastSent[k] or 0) >= 15 and (not s or v.time < s.time) then key,s=k,v end end
    if not s then return end
    A.pending[key] = nil
    if now - s.time >= A.TTL or not A.Watched(s.guild) then return end
    local message = A.Encode(s); if #message > 255 then return end
    A.Broadcast(message)
    A.lastSent[key] = now
    for k,t in pairs(A.lastSent) do if now-t > A.TTL then A.lastSent[k]=nil end end
end
function A.Settings()
    OlympusWatchDB = type(OlympusWatchDB) == "table" and OlympusWatchDB or {}
    A.activeRuleset=A.activeRuleset or A.Ruleset()
    local root=OlympusWatchDB
    if A.activeRuleset=='unknown' then A.db=root else
        root.rulesets=type(root.rulesets)=='table' and root.rulesets or {}
        root.rulesets[A.activeRuleset]=type(root.rulesets[A.activeRuleset])=='table' and root.rulesets[A.activeRuleset] or {}
        A.db=root.rulesets[A.activeRuleset]
    end
    A.db.ruleset=A.activeRuleset
    local legacy=type(A.db.guilds)=="table" and not A.db.discoveryVersion
    if type(A.db.guilds)~="table" then A.db.guilds={} end
    for _,key in ipairs({"excludedGuilds","guildNames","guildSources","guildFactions","showOverrides"}) do
        if type(A.db[key])~="table" then A.db[key]={} end
    end
    if legacy then
        -- v0.1 seeded these names without provenance. Discard the seeds; preserve
        -- absent seed names as exclusions because Remove used to delete the key.
        local seeds={"olympus"}
        for _,roman in ipairs({"ii","iii","iv","v","vi","vii","viii","ix","x"}) do seeds[#seeds+1]="olympus "..roman end
        for _,key in ipairs(seeds) do
            if not A.db.guilds[key] then A.db.excludedGuilds[key]=true end
            A.db.guilds[key]=nil
        end
    end
    A.db.discoveryVersion=1
    for _, key in ipairs({"enabled", "sharing", "network", "alerts", "shown"}) do if type(A.db[key]) ~= "boolean" then A.db[key] = true end end
end
function A.Initialize()
    A.Settings()
    if A.InitAuthority then A.InitAuthority() end
    if type(OlympusWatchServerSnapshot)=='table' and OlympusWatchServerSnapshot.ruleset==A.Scope() then
        if A.ImportAuthority and type(OlympusWatchServerSnapshot.events)=='string' and #OlympusWatchServerSnapshot.events>0 then A.ImportAuthority(OlympusWatchServerSnapshot.events) end
        if A.ImportCatalogue then A.ImportCatalogue(OlympusWatchServerSnapshot.catalogue) end
    end
    A.Read(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix, A.PREFIX)
    A.JoinNetwork()
    if A.CreateUI then A.CreateUI() end
    if A.SetupMap then A.SetupMap() end
    if A.SetupMinimap then A.SetupMinimap() end
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then A.Initialize() elseif A.db and A.SetupMap then A.SetupMap() end
        return
    end
    if not A.db then return end
    if event == "CHAT_MSG_ADDON" then A.Receive(...)
    elseif event == "NAME_PLATE_UNIT_ADDED" then local unit = ...; A.units[unit] = true; A.Observe(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then local unit = ...; A.units[unit] = nil
    elseif event == "PLAYER_TARGET_CHANGED" then A.Observe("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then A.Observe("mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then A.Observe("focus")
    elseif event == "PLAYER_ENTERING_WORLD" then A.units = {}; A.pending = {}; A.JoinNetwork(); if A.SetupMap then A.SetupMap() end end
end)
for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_FOCUS_CHANGED", "CHAT_MSG_ADDON"}) do frame:RegisterEvent(event) end
local elapsedTotal, joinTotal = 0, 0
frame:SetScript("OnUpdate", function(_, elapsed)
    if not A.db then return end
    if A.AuthorityWork then A.AuthorityWork() end
    elapsedTotal, joinTotal = elapsedTotal + elapsed, joinTotal + elapsed
    if elapsedTotal < 1 then return end; elapsedTotal = 0
    if A.db.enabled then
        for unit in pairs(A.units) do A.Observe(unit) end
        for _,unit in ipairs({"target","mouseover","focus"}) do A.Observe(unit) end
    end
    A.Prune(); if A.ShareActivity then A.ShareActivity() end; if not A.authority or not A.authority.outgoing[1] then A.SendPending() end; if A.SharedTick then A.SharedTick() end; A.Changed()
    if joinTotal >= 30 then joinTotal = 0; A.JoinNetwork() end
end)
