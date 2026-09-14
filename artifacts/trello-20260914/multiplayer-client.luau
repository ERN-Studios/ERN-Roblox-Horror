-- Disposable Studio test driver. REMOVE from Edit before finishing.
if not game:GetService("RunService"):IsStudio() then return end
local P = game:GetService("Players").LocalPlayer
local R = game:GetService("ReplicatedStorage")
local controls = require(P:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
local function pack(v) return {v.X,v.Y,v.Z} end
R:WaitForChild("CodexMultiplayerProbe").OnClientInvoke = function(c)
 if c.op == "remote" then
  local folder = R:FindFirstChild(c.folder or "Remotes")
  folder:FindFirstChild(c.name):FireServer(table.unpack(c.args or {}))
 elseif c.op == "attributes" then
  for key,value in pairs(c.values) do P:SetAttribute(key,value) end
 elseif c.op == "walk" then
  controls:Disable()
  local h=P.Character:FindFirstChildOfClass("Humanoid")
  h:MoveTo(Vector3.new(table.unpack(c.position)))
 elseif c.op == "controls" then
  if c.enabled then controls:Enable() else controls:Disable() end
 elseif c.op == "snapshot" then
  local result={name=P.Name,userId=P.UserId,attributes=P:GetAttributes(),guis={},sounds={}}
  local ch=P.Character
  result.position=ch and pack(ch:GetPivot().Position)
  local staminaGui=P.PlayerGui:FindFirstChild("StaminaGui")
  local bar=staminaGui and staminaGui:FindFirstChild("Frame")
  local fill=bar and bar:FindFirstChildOfClass("Frame")
  result.stamina=bar and {visible=bar.Visible,alpha=bar.BackgroundTransparency,
   fraction=fill and fill.Size.X.Scale,position={bar.AbsolutePosition.X,bar.AbsolutePosition.Y}}
  result.battery={}
  for _,o in ipairs(P.PlayerGui:GetDescendants()) do
   if o.Name=="FlashlightPower" then
    result.battery.visible=o.Visible
    for _,list in ipairs(o:GetDescendants()) do
     if list:IsA("UIListLayout") then
      local bars={}
      for _,v in ipairs(list.Parent:GetChildren()) do
       if v:IsA("Frame") then table.insert(bars,v.BackgroundTransparency) end
      end
      result.battery.bars=bars
     end
    end
   end
  end
  for _,o in ipairs(P.PlayerGui:GetDescendants()) do
   if o:IsA("TextLabel") or o:IsA("TextButton") then
    if not c.filter or o:GetFullName():lower():find(c.filter:lower(),1,true) then
     local visible=o.Visible
     local parent=o.Parent
     while parent and parent~=P.PlayerGui do
      if parent:IsA("GuiObject") and not parent.Visible then visible=false end
      if parent:IsA("ScreenGui") and not parent.Enabled then visible=false end
      parent=parent.Parent
     end
     table.insert(result.guis,{path=o:GetFullName(),text=o.Text,visible=visible,active=o.Active})
    end
   end
  end
  for _,o in ipairs(game:GetDescendants()) do
   if o:IsA("Sound") and (o.IsPlaying or o.Name=="Running" or o.Name:find("Step")) then
    table.insert(result.sounds,{path=o:GetFullName(),id=o.SoundId,volume=o.Volume,playing=o.IsPlaying})
   end
  end
  return result
 end
 return true
end
