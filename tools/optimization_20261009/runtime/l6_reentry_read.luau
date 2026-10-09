-- Read-only current real re-entry; prior first-round child/body IDs were 893644/893648.
assert(game:GetService("RunService"):IsRunning() and workspace:GetAttribute("Level6InUse")==true)
local p=game.Players.LocalPlayer
assert(p and p.Name=="Player1" and p:GetAttribute("InRound")==true)
local m=assert(workspace:FindFirstChild("Level 6 Indoor Playground"))
local child=assert(m:FindFirstChild("Level 6 Counting Child"))
local body=assert(child:FindFirstChild("Body"))
assert(child:GetDebugId(0)~="893644" and body:GetDebugId(0)~="893648","Fresh round-owned child/body missing")
local rp=RaycastParams.new()
rp.FilterType=Enum.RaycastFilterType.Include
rp.FilterDescendantsInstances={m}
rp.RespectCanCollide=true
local root=p.Character.HumanoidRootPart
local hit=workspace:Raycast(root.Position+Vector3.new(0,2,0),Vector3.new(0,-18,0),rp)
assert(hit and hit.Normal.Y>.9 and p.Character.Humanoid.Health>0)
local gui=p.PlayerGui:FindFirstChild("RoundGui")
local cover=gui and gui:FindFirstChild("LevelLoading")
assert(not cover or cover.Visible==false)
local lod=0
for _,d in ipairs(m:GetDescendants()) do
 if d:IsA("UnionOperation") and (d.Parent.Name=="Frame_Decks" or d.Parent.Name=="Frame_DecksDeep" or d.Parent.Name=="Frame_DeckPads") then
  assert(d.RenderFidelity==Enum.RenderFidelity.Automatic and d.CollisionFidelity==Enum.CollisionFidelity.Hull)
  lod+=1
 end
end
assert(lod==6605)
return game.HttpService:JSONEncode({complete=true,kind="actual-normal-two-client-l6-reentry",
 childId=child:GetDebugId(0),bodyId=body:GetDebugId(0),priorChildId="893644",priorBodyId="893648",
 floor=hit.Instance:GetFullName(),floorClass=hit.Instance.ClassName,health=p.Character.Humanoid.Health,
 position={root.Position.X,root.Position.Y,root.Position.Z},lodAutomaticHull=lod,loadingCoverVisible=false,
 fullCountingFinalePassed=false})
