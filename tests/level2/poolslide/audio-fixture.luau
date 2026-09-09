-- Table-only regression fixture for the production Level 2 Sound Controller.
-- loadstring this fixture, then call its returned function with actual source.
-- Uses native Roblox Vector3/CFrame/Enum values but creates no real Instances,
-- plays no real audio, makes no DataModel changes, and performs no asset upload.
return function(soundControllerSource)
	local results = {}
	local function signal()
		local self = {Connections = {}}
		function self:Connect(callback)
			local connection = {Connected = true, Callback = callback}
			function connection:Disconnect() self.Connected = false end
			table.insert(self.Connections, connection)
			return connection
		end
		function self:Fire(...)
			for _, connection in ipairs(table.clone(self.Connections)) do
				if connection.Connected then connection.Callback(...) end
			end
		end
		return self
	end
	local function harness()
		local h = {Clock = 100, Played = {}, Created = {}, Queue = {}, Tagged = {}, RandomCalls = {}}
		local methods = {}
		local function object(className, name)
			local self = setmetatable({_class = className, Name = name or className,
				_children = {}, _attributes = {}, _signals = {}, Position = Vector3.zero,
				CFrame = CFrame.identity, AncestryChanged = signal(), DescendantAdded = signal(),
				TimeLength = 0, IsPlaying = false}, {
				__index = function(item, key)
					if key == "Parent" then return rawget(item, "_parent") end
					if key == "WorldPosition" and item._class == "Attachment" then
						return item.Parent.CFrame:PointToWorldSpace(item.Position)
					end
					if key == "TransformedWorldCFrame" and item._class == "Bone" then
						return item.Parent.CFrame * CFrame.new(0, 15, 0)
					end
					return methods[key]
				end,
				__newindex = function(item, key, value)
					if key ~= "Parent" then rawset(item, key, value) return end
					local old = rawget(item, "_parent")
					if old == value then return end
					if old then
						local index = table.find(old._children, item)
						if index then table.remove(old._children, index) end
					end
					rawset(item, "_parent", value)
					if value then
						table.insert(value._children, item)
						local ancestor = value
						while ancestor do ancestor.DescendantAdded:Fire(item) ancestor = ancestor.Parent end
					end
					item.AncestryChanged:Fire(item, value)
					for _, descendant in ipairs(item:GetDescendants()) do
						descendant.AncestryChanged:Fire(descendant, descendant.Parent)
					end
				end,
			})
			table.insert(h.Created, self)
			return self
		end
		function methods:IsA(className)
			return self._class == className
				or className == "BasePart" and (self._class == "Part" or self._class == "MeshPart")
		end
		function methods:GetAttribute(name) return self._attributes[name] end
		function methods:SetAttribute(name, value)
			local old = self._attributes[name]
			self._attributes[name] = value
			if old ~= value and self._signals[name] then self._signals[name]:Fire() end
		end
		function methods:GetAttributeChangedSignal(name)
			self._signals[name] = self._signals[name] or signal()
			return self._signals[name]
		end
		function methods:GetDescendants()
			local out = {}
			local function visit(parent)
				for _, child in ipairs(parent._children) do table.insert(out, child) visit(child) end
			end
			visit(self)
			return out
		end
		function methods:FindFirstChild(name, recursive)
			for _, child in ipairs(self._children) do if child.Name == name then return child end end
			if recursive then
				for _, child in ipairs(self._children) do
					local found = child:FindFirstChild(name, true)
					if found then return found end
				end
			end
		end
		function methods:FindFirstChildOfClass(className)
			for _, child in ipairs(self._children) do if child:IsA(className) then return child end end
		end
		function methods:WaitForChild(name)
			return assert(self:FindFirstChild(name), "fixture missing child " .. name)
		end
		function methods:IsDescendantOf(parent)
			local current = self.Parent
			while current do if current == parent then return true end current = current.Parent end
			return false
		end
		function methods:Destroy()
			if self.Destroyed then return end
			self.Destroyed = true
			self.IsPlaying = false
			for _, child in ipairs(table.clone(self._children)) do child:Destroy() end
			self.Parent = nil
		end
		function methods:Play()
			self.IsPlaying = true
			self.PlayedAt = h.Clock
			table.insert(h.Played, self)
		end
		function methods:Stop() self.IsPlaying = false end
		h.Object = object
		h.Workspace = object("Workspace")
		for name, value in pairs({SelectedLevel = 2, RoundActive = true, WorldGenerated = true}) do
			h.Workspace:SetAttribute(name, value)
		end
		h.World = object("Model", "Level 2 Generated World")
		h.World.Parent = h.Workspace
		h.Player = object("Player", "LocalPlayer")
		h.Player:SetAttribute("InRound", true)
		h.Character = object("Model", "Character")
		h.Character.Parent = h.Workspace
		h.Player.Character = h.Character
		local humanoid = object("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = h.Character
		local playerRoot = object("Part", "HumanoidRootPart")
		playerRoot.Parent = h.Character
		h.Replicated = object("ReplicatedStorage")
		h.Library = object("Folder", "Level 2 Sound Library")
		h.Library.Parent = h.Replicated
		function h:Slot(name, value)
			local slot = self.Library:FindFirstChild(name) or object("StringValue", name)
			slot.Value = value
			slot.Parent = self.Library
			return slot
		end
		for index = 1, 4 do h:Slot("Level 2 Distant Monster-Like Pipe Groan " .. index, tostring(1000 + index)) end
		for index, name in ipairs({"Level 2 Pump Start", "Level 2 Drain Rush", "Level 2 Pressure Door", "Level 2 Slide Rush"}) do
			h:Slot(name, tostring(2000 + index))
		end
		h.Event = object("RemoteEvent", "Level 2 Sound Event")
		h.Event.OnClientEvent = signal()
		h.Event.Parent = h.Replicated
		h.State = object("Folder", "Level 2 State")
		h.State.Parent = h.Replicated
		h.Heartbeat = signal()
		local soundService = object("SoundService")
		local services = {
			Players = {LocalPlayer = h.Player}, ReplicatedStorage = h.Replicated,
			SoundService = soundService, RunService = {Heartbeat = h.Heartbeat},
			ContentProvider = {PreloadAsync = function() end},
			CollectionService = {GetTagged = function(_, tag) return table.clone(h.Tagged[tag] or {}) end},
			Debris = {AddItem = function(_, item, seconds)
				table.insert(h.Queue, {At = h.Clock + seconds, Callback = function() item:Destroy() end})
			end},
		}
		local environment = setmetatable({
			game = {GetService = function(_, name) return assert(services[name], name) end},
			workspace = h.Workspace, Instance = {new = function(className) return object(className) end},
			Random = {new = function() return {
				NextNumber = function(_, minimum, maximum)
					table.insert(h.RandomCalls, {minimum, maximum})
					return minimum
				end,
				NextInteger = function(_, minimum) return minimum end,
			} end},
			os = {clock = function() return h.Clock end},
			task = {
				spawn = function(callback) callback() end,
				delay = function(seconds, callback)
					table.insert(h.Queue, {At = h.Clock + seconds, Callback = callback})
				end,
			},
		}, {__index = getfenv()})
		local chunk, err = loadstring(soundControllerSource)
		assert(chunk, err)
		setfenv(chunk, environment)
		chunk()
		function h:Step(seconds)
			self.Clock += seconds
			for index = #self.Queue, 1, -1 do
				local entry = self.Queue[index]
				if entry.At <= self.Clock then table.remove(self.Queue, index) entry.Callback() end
			end
			self.Heartbeat:Fire(seconds)
		end
		function h:Advance(seconds)
			while seconds > 0 do local step = math.min(seconds, .25) self:Step(step) seconds -= step end
		end
		function h:Entity(options)
			options = options or {}
			local runtime = self.World:FindFirstChild("Level 2 Pool Slide Runtime")
			if not runtime then runtime = object("Folder", "Level 2 Pool Slide Runtime") runtime.Parent = self.World end
			local model = object("Model", options.TagOnly and "Tagged Pool Slide" or "Level 2 Pool Slide")
			model:SetAttribute("Level2_PoolSlideActive", options.Active ~= false)
			local root = object("Part", "RootPart")
			root.CFrame = CFrame.new(120, 0, 0)
			if not options.MissingRoot then root.Parent = model model.PrimaryPart = root end
			local head = object("Bone", "Head")
			head.Parent = root
			model.Parent = options.OutsideWorld and self.Workspace or runtime
			if options.TagOnly then self.Tagged.Level2PoolSlideEntity = {model} end
			return model, root
		end
		function h:Groans()
			local out = {}
			for _, sound in ipairs(self.Played) do
				if sound.SoundId and sound.SoundId:match("^rbxassetid://100[1-4]$") then table.insert(out, sound) end
			end
			return out
		end
		h:Step(0)
		return h
	end
	local function case(name, callback)
		local ok, failure = pcall(callback)
		table.insert(results, {Name = name, Passed = ok, Error = not ok and tostring(failure) or nil})
	end
	case("no monster audio before a real spawn, even after old serial changes", function()
		local h = harness()
		h.State:SetAttribute("Level2_SlidemouthWarningSerial", 100)
		h.State:SetAttribute("Level2_SlidemouthScreamSerial", 100)
		h:Advance(120)
		assert(#h:Groans() == 0)
	end)
	case("first groan waits ten seconds after body availability", function()
		local h = harness()
		h:Advance(40)
		h:Entity()
		h:Step(0)
		h:Advance(9.75)
		assert(#h:Groans() == 0)
		h:Advance(.25)
		assert(#h:Groans() == 1 and h:Groans()[1].PlayedAt == 150)
	end)
	case("real RootPart attachment follows movement and preserves sound profile", function()
		local h = harness()
		local model, root = h:Entity()
		h:Step(0) h:Advance(10)
		local sound = assert(h:Groans()[1])
		local emitter = sound.Parent
		assert(emitter:IsA("Attachment") and emitter.Parent == root and emitter:IsDescendantOf(model))
		local before = emitter.WorldPosition
		root.CFrame = root.CFrame + Vector3.new(30, 2, -40)
		assert((emitter.WorldPosition - before - Vector3.new(30, 2, -40)).Magnitude < .0001)
		assert(emitter.Position == Vector3.new(0, 15, 0))
		assert(sound.Volume == .68 and sound.PlaybackSpeed == .97)
		assert(sound.RollOffMinDistance == 18 and sound.RollOffMaxDistance == 280)
		local reverb = sound:FindFirstChildOfClass("ReverbSoundEffect")
		assert(reverb and reverb.DecayTime == 5.2 and reverb.Density == .34 and reverb.Diffusion == .30)
		assert(reverb.DryLevel == -9 and reverb.WetLevel == -2)
	end)
	case("later cadence is twenty-four seconds and shuffle bag uses all four", function()
		local h = harness() h:Entity() h:Step(0) h:Advance(10 + 24 * 4)
		local groans, seen = h:Groans(), {}
		assert(#groans == 5)
		for index = 1, 4 do seen[groans[index].SoundId] = true end
		local unique = 0 for _ in pairs(seen) do unique += 1 end
		assert(unique == 4 and groans[4].SoundId ~= groans[5].SoundId)
		for index = 2, #groans do assert(groans[index].PlayedAt - groans[index-1].PlayedAt == 24) end
		local firstRange, laterRange, pitchRange = false, false, false
		for _, call in ipairs(h.RandomCalls) do
			if call[1] == 10 and call[2] == 18 then firstRange = true end
			if call[1] == 24 and call[2] == 42 then laterRange = true end
			if call[1] == .97 and call[2] == 1.02 then pitchRange = true end
		end
		assert(firstRange and laterRange and pitchRange, "keep the full authored random timing/pitch ranges")
	end)
	case("tagged alternative entity is supported", function()
		local h = harness() local model = h:Entity({TagOnly = true}) h:Step(0) h:Advance(10)
		assert(#h:Groans() == 1 and h:Groans()[1]:IsDescendantOf(model))
	end)
	case("inactive and outside-world tagged models never emit", function()
		local h = harness() h:Entity({Active = false}) h:Entity({TagOnly = true, OutsideWorld = true})
		h:Advance(90) assert(#h:Groans() == 0)
	end)
	case("late root streams in without random positional fallback", function()
		local h = harness() local model, root = h:Entity({MissingRoot = true})
		h:Advance(50) assert(#h:Groans() == 0)
		root.Parent = model model.PrimaryPart = root h:Step(0)
		h:Advance(9.75) assert(#h:Groans() == 0)
		h:Advance(.25) assert(#h:Groans() == 1)
	end)
	case("entity despawn immediately destroys its playing voice", function()
		local h = harness() local model = h:Entity() h:Step(0) h:Advance(10)
		local voice = h:Groans()[1] model.Parent = nil
		assert(voice.Destroyed) h:Advance(60) assert(#h:Groans() == 1)
	end)
	case("root stream-out stops sound and stream-in restarts first delay", function()
		local h = harness() local model, root = h:Entity() h:Step(0) h:Advance(10)
		local voice = h:Groans()[1] root.Parent = nil assert(voice.Destroyed)
		h:Advance(30) assert(#h:Groans() == 1)
		root.Parent = model h:Step(0) h:Advance(9.75) assert(#h:Groans() == 1)
		h:Advance(.25) assert(#h:Groans() == 2)
	end)
	case("deactivation stops an existing voice immediately", function()
		local h = harness() local model = h:Entity() h:Step(0) h:Advance(10)
		local voice = h:Groans()[1] model:SetAttribute("Level2_PoolSlideActive", false)
		assert(voice.Destroyed) h:Advance(60) assert(#h:Groans() == 1)
	end)
	case("round exit cleans entity voices and stops further emission", function()
		local h = harness() h:Entity() h:Step(0) h:Advance(10)
		local voice = h:Groans()[1] h.Player:SetAttribute("InRound", false)
		assert(voice.Destroyed) h:Advance(60) assert(#h:Groans() == 1)
	end)
	case("world removal cleans entity voices", function()
		local h = harness() h:Entity() h:Step(0) h:Advance(10)
		local voice = h:Groans()[1] h.World.Parent = nil
		assert(voice.Destroyed) h:Advance(60) assert(#h:Groans() == 1)
	end)
	case("authored pump cue owns mix without triggering another monster lane", function()
		local h = harness() h:Entity() h:Step(0) h:Advance(10)
		local voice = h:Groans()[1] h.Event.OnClientEvent:Fire("Level 2 Pump Start")
		assert(voice.Destroyed and h.Played[#h.Played].SoundId == "rbxassetid://2001")
		h:Advance(23.75) assert(#h:Groans() == 1)
		h:Advance(.25) assert(#h:Groans() == 2)
	end)
	case("common water drops remain detached ambience before creature spawn", function()
		local h = harness() h:Slot("Level 2 Water Drop", "3001") h:Advance(5)
		assert(#h:Groans() == 0)
		local common
		for _, sound in ipairs(h.Played) do if sound.SoundId == "rbxassetid://3001" then common = sound end end
		assert(common and common.Parent:IsA("Part") and common.Parent.Name == "Level 2 Random Audio Emitter")
	end)
	case("missing monster asset never produces fallback audio or detached emitter", function()
		local h = harness()
		for index = 1, 4 do h:Slot("Level 2 Distant Monster-Like Pipe Groan " .. index, "") end
		h:Entity() h:Step(0) h:Advance(60) assert(#h:Groans() == 0)
		for _, item in ipairs(h.Created) do
			assert(item.Name ~= "Level 2 Pool Slide Local Groan Emitter")
		end
	end)
	local passed = 0 for _, result in ipairs(results) do if result.Passed then passed += 1 end end
	return {Passed = passed, Total = #results, Results = results}
end
