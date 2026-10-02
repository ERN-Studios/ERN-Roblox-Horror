local result=(function()
-- Read-only actual Server inspection. Cached modules are already used by the running host.
-- Bridge.Build only creates local Lua descriptors; no Instance/source/config writes.
local Players, HS = game:GetService("Players"), game:GetService("HttpService")
local ServerScriptService=game:GetService("ServerScriptService")
local output={scope="Read-only actual server access predicate and queue callback evaluation; no teleport, queue creation, spoofed participant or multiplayer claim",
	placeId=game.PlaceId, universeId=game.GameId, players={}, serverHasClientGateFolder=false}
local model=workspace:FindFirstChild("LobbyReimaginedPreview")
output.modelReady=model and model:GetAttribute("Ready")==true or false
output.serverHasClientGateFolder=model and model:FindFirstChild("R4ClientDevGates")~=nil or false
local ok,problem=pcall(function()
	local access=require(game:GetService("ReplicatedStorage"):FindFirstChild("DevAccess"))
	local bridge=require(ServerScriptService:FindFirstChild("LobbyReimaginedPreview"):FindFirstChild("QueueBridge"))
	local stations=bridge.Build(model)
	output.stationCount=#stations
	output.ordinaryNumericIdDenied=not access.IsAllowed(1) and not access.IsLevel6PreviewAllowed(1)
	for _,player in ipairs(Players:GetPlayers())do
		local row={name=player.Name,userId=player.UserId,generalDeveloper=access.IsAllowed(player),
			level6PreviewAllowed=access.IsLevel6PreviewAllowed(player),level5Queues={},level6Queues={}}
		for _,station in ipairs(stations)do
			if station.level==5 or station.level==6 then
				local allowed=bridge.AllowsPreview(station,player)
				table.insert(if station.level==5 then row.level5Queues else row.level6Queues,
					{index=station.index,level=station.level,serverCallbackAllows=allowed,previewQueue=station.previewQueue})
			end
		end
		table.insert(output.players,row)
	end
end)
output.actualCallbacksEvaluated=ok
if not ok then output.actualCallbackEvaluationError=tostring(problem)end
return HS:JSONEncode(output)

end)();print("ENDFIX_SERVER_ACCESS "..game:GetService("HttpService"):JSONEncode(result))
