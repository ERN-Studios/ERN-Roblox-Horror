local previous=workspace:GetAttribute("ReentryRuntimeResult");local expired=workspace:GetAttribute("ReentryRuntimeExpired");local probe=Instance.new("Script");probe.Name="ReentryPaidPathProbe";probe.Source=[==[
local p=game.Players:GetPlayers()[1]
local protection=require(game.ServerScriptService.PlayerProtection)
p.Character.Humanoid.Health=0;task.wait(.1)
local accepted,reason=game.ServerStorage.ZyntraReentry:Invoke(p)
local first={accepted=accepted,reason=reason,active=protection.IsActive(p,p.Character),used=p:GetAttribute("ZyntraReentryUsed"),remaining=(p:GetAttribute("PlayerProtectionExpiresAt") or 0)-workspace:GetServerTimeNow()}
p.Character.Humanoid.Health=0;task.wait(.1)
local duplicate,duplicateReason=game.ServerStorage.ZyntraReentry:Invoke(p)
first.duplicate=duplicate;first.duplicateReason=duplicateReason
workspace:SetAttribute("ReentryPaidPathResult",game.HttpService:JSONEncode(first))
-- Restore a living developer character for the remaining read-only UI check.
game.ServerStorage.ZyntraReentry:Invoke(p,true)
]==];probe.Parent=game.ServerScriptService;task.wait(1.5);return game.HttpService:JSONEncode({runtime=previous,expired=expired,paidPath=workspace:GetAttribute("ReentryPaidPathResult")})
