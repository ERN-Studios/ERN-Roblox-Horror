local S=game.ServerScriptService["Level 3 Systems"]
local A=require(S["Level 3 Round Adapter"])
local O=require(S["Level 3 Objective Controller"])
local m=A.GetManifest()
local cd=m.Modules[1]
local p=game.Players.Player1
local prompt=cd.Prompt
local target=prompt.Parent:IsA("Attachment") and prompt.Parent.WorldPosition or prompt.Parent.Position
p.Character.HumanoidRootPart:SetNetworkOwner(nil)
p.Character.Humanoid:Move(Vector3.zero)
p.Character:PivotTo(CFrame.new(target+Vector3.new(0,0,3)))
local root=p.Character.HumanoidRootPart
local head=p.Character.Head
local params=RaycastParams.new()
params.FilterDescendantsInstances={p.Character}
params.FilterType=Enum.RaycastFilterType.Exclude
local hit=workspace:Raycast(head.Position,target-head.Position,params)
local function pack(v) return {v.X,v.Y,v.Z} end
return {attrs=p:GetAttributes(),phase=workspace:GetAttribute("RoundActive"),root=pack(root.Position),target=pack(target),
 distance=(root.Position-target).Magnitude,enabled=prompt.Enabled,lineOfSight=prompt.RequiresLineOfSight,
 hit=hit and hit.Instance:GetFullName(),owner=cd.Model:GetFullName(),collected=O.DebugCollectCD(p,1)}
