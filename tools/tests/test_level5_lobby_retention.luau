local checks=0
for _,studio in ipairs({true,false}) do
 local RunService={IsStudio=function() return studio end}
 local workspace,ServerStorage={},{}
 local lobby={Name="ServerLobby",Parent=workspace,Attrs={}}
 function lobby:SetAttribute(k,v) self.Attrs[k]=v end
 function workspace:FindFirstChild(name) if name=="ServerLobby" and lobby.Parent==self then return lobby end end
 function ServerStorage:FindFirstChild(name) if lobby.Name==name and lobby.Parent==self then return lobby end end
 local LOBBY_NAME="Level 5 Stored Server Lobby"
local function parkLobby()
	-- Studio's real Back to Lobby route requires its existing spawn to remain
	-- in Workspace. This map is 17,000 studs away, so keeping that local floor
	-- does not expose it from the preview. Published reserved servers teleport
	-- players home and may still park their unused lobby as before.
	if RunService:IsStudio() then return end
	local lobby = workspace:FindFirstChild("ServerLobby")
	if not lobby then return end
	assert(ServerStorage:FindFirstChild(LOBBY_NAME) == nil, "Level 5 lobby backup already exists")
	lobby:SetAttribute("Level5OriginalName", lobby.Name)
	lobby.Name, lobby.Parent = LOBBY_NAME, ServerStorage
end

 parkLobby()
 assert((lobby.Parent==workspace)==studio,"Studio's leave guard must keep its actual lobby floor")
 assert(lobby.Name==(studio and "ServerLobby" or LOBBY_NAME),"published reserved path keeps previous storage name")
 assert((lobby.Attrs.Level5OriginalName=="ServerLobby")==not studio,"only parked lobby has restore metadata")
 checks+=3
end
print("PASS: "..checks.." park/leave-floor assertions against real adapter function")
