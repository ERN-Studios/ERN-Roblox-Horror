
local player=game:GetService("Players").LocalPlayer
local pg=player.PlayerGui
local device=require(game.ReplicatedStorage.UIDevice)
local keys={"ForceTouchUI","UIRegressionViewport"}
local borrowed={}
for _,k in ipairs(keys) do borrowed[k]=workspace:GetAttribute(k) end
local oldQueue=player:GetAttribute("QueueModalOpen")
local changes=0
local connection=device.Changed:Connect(function() changes+=1 end)
local function waitEvent() task.wait(.15) end
local checks={}
local ok,err=xpcall(function()
 workspace:SetAttribute("ForceTouchUI",true);waitEvent()
 assert(device.IsTouch() and device.Binding("[Q]","[RT]")=="","touch glyph suppression")
 checks.touchForm=true
 workspace:SetAttribute("ForceTouchUI",false);waitEvent()
 assert(not device.IsTouch() and device.Binding("[Q]","[RT]")=="[Q]","pointer return")
 checks.pointerReturn=true
 local before=changes
 workspace:SetAttribute("UIRegressionViewport",Vector2.new(390,844));waitEvent()
 assert(changes>before and device.Layout().Width==390,"viewport refresh")
 checks.viewportRefresh=true
 workspace:SetAttribute("UIRegressionViewport",borrowed.UIRegressionViewport);waitEvent()
 before=changes
 player:SetAttribute("QueueModalOpen",true);waitEvent()
 assert(changes>before and device.ScreenOwningModalOpen(),"modal refresh")
 checks.modalRefresh=true
 player:SetAttribute("QueueModalOpen",oldQueue);waitEvent()
 assert(player:GetAttribute("QueueModalOpen")==oldQueue,"modal restore")
 checks.modalReturn=true
end,debug.traceback)
for _,k in ipairs(keys) do workspace:SetAttribute(k,borrowed[k]) end
player:SetAttribute("QueueModalOpen",oldQueue)
waitEvent()
connection:Disconnect()
for _,k in ipairs(keys) do assert(workspace:GetAttribute(k)==borrowed[k],"borrowed attribute not restored") end
assert(player:GetAttribute("QueueModalOpen")==oldQueue,"queue not restored")
assert(ok,err)
checks.borrowedStateRestored=true
checks.notificationCount=changes
checks.physicalGamepadTested=false
checks.physicalMobileTested=false
return game:GetService("HttpService"):JSONEncode(checks)
