local p=game.Players:GetPlayers()[1];local char=p.Character;local root=char.HumanoidRootPart;local hum=char:FindFirstChildOfClass("Humanoid");local placement=require(game.ServerScriptService.ReentryPlacement);local target
for x=-120,120,24 do for z=-120,120,24 do local frame=placement.At(root,hum,CFrame.new(x,root.Position.Y,z)); if frame and (frame.Position-root.Position).Magnitude>60 then target=frame;break end end;if target then break end end
assert(target,"No safe test death spot");char:PivotTo(target*root.CFrame:ToObjectSpace(char:GetPivot()));task.wait(.8)
local before=root.CFrame;workspace:SetAttribute("ReentryTestDeathFrame",before);hum.Health=0;task.wait(.1)
local accepted,reason=game.ServerStorage.ZyntraReentry:Invoke(p,true);local new=p.Character.HumanoidRootPart
local result={accepted=accepted,reason=reason,death=tostring(before.Position),arrival=tostring(new.Position),distance=(new.Position-before.Position).Magnitude,anchored=new.Anchored,protection=require(game.ServerScriptService.PlayerProtection).IsActive(p,p.Character),source=p:GetAttribute("PlayerProtectionSource"),remaining=p:GetAttribute("PlayerProtectionExpiresAt")-workspace:GetServerTimeNow(),used=p:GetAttribute("ZyntraReentryUsed")}
assert(accepted and result.distance<1 and not result.anchored and result.protection and result.remaining>9.5,"Re-entry regression")
return game.HttpService:JSONEncode(result)
