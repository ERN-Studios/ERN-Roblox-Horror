local fs,luau=require("@lune/fs"),require("@lune/luau")
local r=require("@lune/roblox")
local source=fs.readFile("tools/lobby_access_spawn_20261002/devgates/R4DevGateController.LocalScript.candidate.luau")
local accessSource=fs.readFile("artifacts/lobby-access-spawn-20261002/devgate-audit/ReplicatedStorage__DevAccess.live.luau")
local function fixture(userId, mode)
	local stats = {connections=0, warnings={}}
	local function signal()
		local listeners = {}
		local s = {}
		function s:Connect(fn)
			local c = {active=true}
			stats.connections += 1
			listeners[c] = fn
			function c:Disconnect()
				if self.active then self.active=false; listeners[self]=nil; stats.connections -= 1 end
			end
			return c
		end
		function s:Fire(...)
			local copy = {}
			for c, fn in pairs(listeners) do table.insert(copy, {c, fn}) end
			for _, row in ipairs(copy) do if row[1].active then row[2](...) end end
		end
		return s
	end
	local methods, create = {}, nil
	function methods:IsA(class)
		return self.ClassName == class or (class == "BasePart" and self.ClassName == "Part")
			or (class == "LuaSourceContainer" and (self.ClassName == "ModuleScript" or self.ClassName == "LocalScript" or self.ClassName == "Script"))
	end
	function methods:IsDescendantOf(parent)
		local next = self.Parent
		while next do if next == parent then return true end; next = next.Parent end
		return false
	end
	function methods:GetAttribute(name) return self._attrs[name] end
	function methods:SetAttribute(name, value)
		self._attrs[name] = value
		if self._attributeSignals[name] then self._attributeSignals[name]:Fire() end
	end
	function methods:GetAttributeChangedSignal(name)
		self._attributeSignals[name] = self._attributeSignals[name] or signal()
		return self._attributeSignals[name]
	end
	function methods:GetPropertyChangedSignal(name)
		self._propertySignals[name] = self._propertySignals[name] or signal()
		return self._propertySignals[name]
	end
	function methods:GetChildren() return table.clone(self._children) end
	function methods:GetDescendants()
		local list = {}
		local function visit(node)
			for _, child in ipairs(node._children) do table.insert(list, child); visit(child) end
		end
		visit(self)
		return list
	end
	function methods:FindFirstChild(name)
		for _, child in ipairs(self._children) do if child.Name == name then return child end end
		return nil
	end
	function methods:WaitForChild(name) return self:FindFirstChild(name) end
	function methods:FindFirstChildOfClass(class)
		for _, child in ipairs(self._children) do if child:IsA(class) then return child end end
		return nil
	end
	function methods:Clone()
		local copy = create(self.ClassName)
		for key,value in pairs(self._props) do if key ~= "Parent" then copy[key] = value end end
		copy._attrs = table.clone(self._attrs)
		for _,child in ipairs(self._children) do child:Clone().Parent = copy end
		return copy
	end
	function methods:Destroy()
		self.Destroying:Fire()
		self.Parent = nil
		for _, child in ipairs(self:GetChildren()) do child:Destroy() end
	end
	create = function(class)
		local object = {
			_instance=true, _attrs={}, _children={}, _attributeSignals={}, _propertySignals={},
			_props={ClassName=class, Name=class, Enabled=true, Visible=true},
			ChildAdded=signal(), DescendantAdded=signal(), DescendantRemoving=signal(), AncestryChanged=signal(), Destroying=signal(),
		}
		setmetatable(object, {
			__index=function(self, key) if methods[key] then return methods[key] end; if self._props[key] ~= nil then return self._props[key] end; return methods.FindFirstChild(self,key) end,
			__newindex=function(self, key, value)
				local previous = self._props[key]
				if previous == value then return end
				if key == "Parent" then
					local all = {self}
					for _, descendant in ipairs(self:GetDescendants()) do table.insert(all, descendant) end
					local oldAncestor = previous
					while oldAncestor do
						for _, descendant in ipairs(all) do oldAncestor.DescendantRemoving:Fire(descendant) end
						oldAncestor = oldAncestor.Parent
					end
					if previous then table.remove(previous._children, assert(table.find(previous._children, self))) end
					self._props.Parent = value
					if value then
						table.insert(value._children, self)
						value.ChildAdded:Fire(self)
						local ancestor = value
						while ancestor do
							for _, descendant in ipairs(all) do ancestor.DescendantAdded:Fire(descendant) end
							ancestor = ancestor.Parent
						end
					end
					self.AncestryChanged:Fire(self, value)
				else self._props[key] = value end
				if self._propertySignals[key] then self._propertySignals[key]:Fire() end
			end,
		})
		return object
	end
	local world, replicated, players = create("Workspace"), create("ReplicatedStorage"), create("Players")
	local player = create("Player"); player.UserId=userId; players.LocalPlayer=player; player.Parent=players
	local original = create("Model"); original.Name="ServerLobby"; original.Parent=world
	local publicLabel=create("TextLabel"); publicLabel.Name="QueueTitle"; publicLabel.Parent=original
	local accessModule=create("ModuleScript"); accessModule.Name="DevAccess"
	if mode ~= "missing" then accessModule.Parent=replicated end
	local envTypeof = function(v) return if type(v)=="table" and rawget(v, "_instance") then "Instance" else typeof(v) end
	local access = luau.load(accessSource, {environment={typeof=envTypeof}})()
	if mode == "error" then access={IsAllowed=function()error("access error")end, IsLevel6PreviewAllowed=function()error("access error")end} end
	local function buildModel(isReady, rev, owned)
		local model = create("Model"); model.Name="LobbyReimaginedPreview"
		model:SetAttribute("LobbyReimaginedOwned", owned ~= false)
		model:SetAttribute("LobbyVisualRevision", rev or 4)
		model:SetAttribute("Ready", isReady ~= false)
		local signs=create("Folder"); signs.Name="LevelGateSigns"; signs.Parent=model
		local headers, labels, prompts = {}, {}, {}
		for _, level in ipairs({5,6}) do
			local side = if level==5 then -1 else 1
			local yaw = if level==5 then math.pi/2 else -math.pi/2
			local gate = r.CFrame.new(220+side*28.6, 30.8, -680)*r.CFrame.Angles(0,yaw,0)
			local header=create("Part"); header.Name="LEVEL "..level.." Door Header"
			header.CFrame=gate*r.CFrame.new(0,17.2,1.42); header:SetAttribute("Level",level); header.Parent=signs
			headers[level]=header
			local bay=create("Model"); bay.Name="QueueBay_Level"..level; bay.Parent=model
			labels[level], prompts[level] = {}, {}
			for index=1,4 do
				local station=create("Model"); station.Name="Level"..level.." Queue "..index; station.Parent=bay
				for _, name in ipairs({"QueueTitle","QueueSubtitle"}) do
					local label=create("TextLabel"); label.Name=name; label.Parent=station; table.insert(labels[level],label)
				end
				local control=create("Part"); control.Name="Queue Kiosk Control"; control.Parent=station
				local prompt=create("ProximityPrompt"); prompt.Name="Level"..level.."DeveloperPreviewPrompt"; prompt.Parent=control
				table.insert(prompts[level],prompt)
			end
		end
		return model, headers, labels, prompts
	end
	local function run()
		luau.load(source, {environment={
			game={GetService=function(_,name) return ({Players=players,ReplicatedStorage=replicated})[name] end},
			workspace=world, Instance={new=create}, Enum=r.Enum,
			Color3=r.Color3, Vector2=r.Vector2, Vector3=r.Vector3, CFrame=r.CFrame, UDim2=r.UDim2, UDim=r.UDim,
			ColorSequence=r.ColorSequence, ColorSequenceKeypoint=r.ColorSequenceKeypoint,
			require=function(module) assert(module==accessModule); return access end,
			warn=function(message) table.insert(stats.warnings,message) end,
		}})()
	end
	return {world=world, original=original, originalLabel=publicLabel, player=player, access=access,
		create=create, build=buildModel, run=run, stats=stats, signal=signal, players=players, accessModule=accessModule, envTypeof=envTypeof}
end

return fixture
