local A=OlympusWatch
local function position(button)
    local angle=math.rad(A.db.minimapAngle or 225)
    local x,y=math.cos(angle),math.sin(angle)
    local radiusX=(Minimap:GetWidth() or 140)/2+8
    local radiusY=(Minimap:GetHeight() or 140)/2+8
    local shape=GetMinimapShape and GetMinimapShape() or 'ROUND'
    if shape=='SQUARE' then
        local scale=math.max(math.abs(x),math.abs(y)); x,y=x/scale,y/scale
    end
    button:ClearAllPoints(); button:SetPoint('CENTER',Minimap,'CENTER',x*radiusX,y*radiusY)
end
function A.SetupMinimap()
    if not Minimap or A.minimapButton then return end
    if type(A.db.minimapAngle)~='number' or A.db.minimapAngle~=A.db.minimapAngle or math.abs(A.db.minimapAngle)==math.huge then A.db.minimapAngle=225 end
    local b=CreateFrame('Button','OlympusWatchMinimapButton',Minimap)
    A.minimapButton=b
    b:SetSize(32,32); b:SetFrameStrata('MEDIUM'); b:SetFrameLevel(Minimap:GetFrameLevel()+8)
    b:RegisterForClicks('LeftButtonUp','RightButtonUp'); b:RegisterForDrag('LeftButton')
    local icon=b:CreateTexture(nil,'ARTWORK'); icon:SetSize(23,23); icon:SetPoint('CENTER')
    icon:SetTexture('Interface\\AddOns\\OlympusWatch\\MinimapIcon')
    local border=b:CreateTexture(nil,'OVERLAY'); border:SetSize(54,54); border:SetPoint('TOPLEFT')
    border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
    b:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
    b:SetScript('OnEnter',function(self)
        GameTooltip:SetOwner(self,'ANCHOR_LEFT'); GameTooltip:SetText('OlympusWatch')
        GameTooltip:AddLine('Left-click: open / close',1,1,1)
        GameTooltip:AddLine('Right-click: nearby encounters',1,1,1)
        GameTooltip:AddLine('Drag: move around minimap',1,1,1)
        GameTooltip:Show()
    end)
    b:SetScript('OnLeave',function() GameTooltip:Hide() end)
    b:SetScript('OnClick',function(_,mouse)
        if mouse=='RightButton' then A.Command('battles')
        else A.Command(A.window and A.window:IsShown() and 'hide' or 'show') end
    end)
    b:SetScript('OnDragStart',function(self)
        GameTooltip:Hide()
        self:SetScript('OnUpdate',function(button)
            local cx,cy=Minimap:GetCenter(); if not cx or not cy then return end
            local x,y=GetCursorPosition(); local scale=Minimap:GetEffectiveScale()
            A.db.minimapAngle=math.deg(math.atan2(y/scale-cy,x/scale-cx))%360
            position(button)
        end)
    end)
    b:SetScript('OnDragStop',function(self) self:SetScript('OnUpdate',nil) end)
    position(b); b:SetShown(not A.db.minimapHidden)
end
local original=A.Command
function A.Command(message)
    if type(message)=='string' and message:lower():match('^%s*minimap%s*$') then
        A.db.minimapHidden=not A.db.minimapHidden
        if A.minimapButton then A.minimapButton:SetShown(not A.db.minimapHidden) end
        A.Print('Minimap icon '..(A.db.minimapHidden and 'hidden' or 'shown')..'. Use /ow minimap to toggle.')
    else return original(message) end
end
SlashCmdList.OLYMPUSWATCH=A.Command
