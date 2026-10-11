local A=OlympusWatch
OlympusWatchPinMixin={}
function OlympusWatchPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI"); self:SetScalingLimits(1,1,1.2)
    self:SetSize(22,22); self:EnableMouse(true); self:RegisterForClicks("LeftButtonUp","RightButtonUp")
    self.count=self:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); self.count:SetPoint('TOP',self,'BOTTOM',0,0)
    self.icon=self:CreateTexture(nil,"ARTWORK"); self.icon:SetAllPoints(); self.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
end
function OlympusWatchPinMixin:OnMouseEnter() if self.s then A.Tooltip(self,self.s) end end
function OlympusWatchPinMixin:OnMouseLeave() GameTooltip:Hide() end
function OlympusWatchPinMixin:OnMouseClickAction(mouse)
    if self.s then
        if self.s.battle then A.OpenBattles(self.s.battle.target)
        elseif mouse=="RightButton" then A.Callout(self.s) else A.Waypoint(self.s) end
    end
end
-- The base OnClick invokes global map handlers before the pin action; those
-- handlers can consume a right click to zoom out even with passthrough disabled.
function OlympusWatchPinMixin:OnClick(mouse)
    if mouse=="RightButton" or mouse=="LeftButton" then self:OnMouseClickAction(mouse) end
end
function OlympusWatchPinMixin:OnMouseDown(mouse, ...)
    if mouse~="RightButton" then MapCanvasPinMixin.OnMouseDown(self,mouse,...) end
end
function OlympusWatchPinMixin:OnMouseUp(mouse, ...)
    if mouse~="RightButton" then MapCanvasPinMixin.OnMouseUp(self,mouse,...) end
end
function OlympusWatchPinMixin:ShouldMouseButtonBePassthrough() return false end
function OlympusWatchPinMixin:ApplyFrameLevel()
    MapCanvasPinMixin.ApplyFrameLevel(self)
    -- Leatrix's POIs use HIGH strata / level 100. Keep our clickable pins above them.
    self:SetFrameStrata("HIGH"); self:SetFrameLevel(math.max(self:GetFrameLevel(),110))
end
function OlympusWatchPinMixin:OnAcquired(s)
    self.s=s; self:SetPosition(s.x,s.y)
    if self.count then self.count:SetText(s.activity and (tostring(s.count)..(s.capped and '+' or '')) or '') end
    self.icon:SetTexture(s.battle and 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_4' or 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_8')
    self:SetPropagateMouseClicks(false); self:SetPropagateMouseMotion(false)
    self:SetPassThroughButtons()
end
function OlympusWatchPinMixin:OnReleased() self.s=nil; MapCanvasPinMixin.OnReleased(self) end
function A.SetupMap()
    if A.provider or not WorldMapFrame or not MapCanvasDataProviderMixin or not MapCanvasPinMixin or not CreateFromMixins then return end
    -- Fill the base when the map UI is available, keeping XML's mixin table stable.
    for k,v in pairs(MapCanvasPinMixin) do if OlympusWatchPinMixin[k]==nil then OlympusWatchPinMixin[k]=v end end
    local provider=CreateFromMixins(MapCanvasDataProviderMixin)
    provider.pins={}
    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate("OlympusWatchPinTemplate"); self.pins={}
    end
    function provider:RefreshAllData()
        local canvas=self:GetMap(); local map=canvas:GetMapID()
        if self.mapID~=map then self:RemoveAllData(); self.mapID=map end
        if not A.db or not A.db.enabled then self:RemoveAllData(); return end
        local active={}
        local markers=A.ActivityGroups and A.ActivityGroups() or A.Sorted()
        local areaPins,battlePins=0,0
        for _,s in ipairs(markers) do
            if not (A.IsCityMap and A.IsCityMap(s.map)) and s.map==map and (not s.activity or areaPins<16) and (not s.battle or battlePins<8) then
                if s.activity then areaPins=areaPins+1 end
                if s.battle then battlePins=battlePins+1 end
                local key=s.battle and ('battle:'..s.battle.target) or (s.activity and ('area:'..s.id) or ('player:'..s.name:lower())); active[key]=true
                local pin=self.pins[key]
                if pin then pin.s=s; pin:SetPosition(s.x,s.y); if pin.count then pin.count:SetText(s.activity and (tostring(s.count)..(s.capped and '+' or '')) or '') end
                else self.pins[key]=canvas:AcquirePin("OlympusWatchPinTemplate",s) end
            end
        end
        for key,pin in pairs(self.pins) do if not active[key] then canvas:RemovePin(pin); self.pins[key]=nil end end
    end
    A.provider=provider; WorldMapFrame:AddDataProvider(provider)
end
function A.RefreshMap()
    if A.provider and WorldMapFrame:IsShown() then A.provider:RefreshAllData() end
end
