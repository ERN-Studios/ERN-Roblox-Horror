-- Offline policy/geometry/lifetime regressions; these do not prove an actual Play.
local fs, luau, serde = require("@lune/fs"), require("@lune/luau"), require("@lune/serde")
local r = require("@lune/roblox")
local ROOT = "tools/lobby_access_spawn_20261002/devgates/"
local source = fs.readFile(ROOT .. "R4DevGateController.LocalScript.candidate.luau")
local accessSource = fs.readFile("artifacts/lobby-access-spawn-20261002/devgate-audit/ReplicatedStorage__DevAccess.live.luau")
assert(pcall(luau.compile, source))
local cases = {}
local function test(name, run)
	local ok, why = pcall(run)
	table.insert(cases, {name=name, passed=ok, error=if ok then nil else tostring(why)})
	if not ok then warn(name .. ": " .. tostring(why)) end
end
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
local function gateCount(model)
	local folder=model:FindFirstChild("R4ClientDevGates")
	local count=0
	if folder then for _, d in ipairs(folder:GetDescendants()) do if d.Name=="Coming Soon Shutter" then count+=1 end end end
	return count,folder
end
test("actual fresh allowlist rejects ordinary IDs, strings, NaN, infinity and spoofed tables", function()
	local f=fixture(1)
	for _, subject in ipairs({1,-1,0,9488575950,11374988580,"9488575949",{UserId=9488575949},math.huge,0/0,9488575949.1}) do
		assert(f.access.IsAllowed(subject)==false and f.access.IsLevel6PreviewAllowed(subject)==false)
	end
	assert(not f.access.IsAllowed(nil) and not f.access.IsLevel6PreviewAllowed(nil))
	f.player.Name="LaverSneglen"; assert(not f.access.IsAllowed(f.player))
	assert(f.access.IsAllowed(40920547) and f.access.IsAllowed(9488575949))
	assert(not f.access.IsAllowed(11374988579) and f.access.IsLevel6PreviewAllowed(11374988579))
end)
test("nondeveloper sees two opaque colliding shutters and only owned bay labels/prompts hidden", function()
	local f=fixture(1); local model,_,labels,prompts=f.build(); model.Parent=f.world; f.run()
	local count,folder=gateCount(model); assert(count==2 and not folder:GetAttribute("Level5PreviewAllowed") and not folder:GetAttribute("Level6PreviewAllowed"))
	for _,level in ipairs({5,6}) do
		for _,label in ipairs(labels[level])do assert(label.Visible==false)end
		for _,prompt in ipairs(prompts[level])do assert(prompt.Enabled==false)end
	end
	for _,part in ipairs(folder:GetDescendants())do if part.Name=="Coming Soon Shutter"then assert(part.CanCollide and part.Anchored and part.CanTouch==false)end end
	assert(f.originalLabel.Visible and not f.original:FindFirstChild("R4ClientDevGates"))
end)
test("both shared developers retain both normal preview routes without shutters", function()
	for _,userId in ipairs({40920547,9488575949})do
		local f=fixture(userId);local model,_,labels,prompts=f.build();model.Parent=f.world;f.run()
		local count,folder=gateCount(model);assert(count==0 and folder:GetAttribute("Level5PreviewAllowed") and folder:GetAttribute("Level6PreviewAllowed"))
		for _,level in ipairs({5,6})do for _,label in ipairs(labels[level])do assert(label.Visible)end;for _,prompt in ipairs(prompts[level])do assert(prompt.Enabled)end end
	end
end)
test("Zen sees both preview openings without general developer command expansion",function()
	local f=fixture(11374988579);local model,_,labels,prompts=f.build();model.Parent=f.world;f.run()
	local count,folder=gateCount(model);assert(count==0 and folder:GetAttribute("Level5PreviewAllowed") and folder:GetAttribute("Level6PreviewAllowed"))
	assert(labels[5][1].Visible and prompts[5][1].Enabled and labels[6][1].Visible and prompts[6][1].Enabled)
	assert(not f.access.IsAllowed(f.player) and f.access.IsLevel6PreviewAllowed(f.player))
end)
test("missing or erroring access module fails closed",function()
	for _,mode in ipairs({"missing","error"})do
		local f=fixture(9488575949,mode);local model=f.build();model.Parent=f.world;f.run();assert(gateCount(model)==2)
	end
end)
test("late Ready publication creates exactly one owned folder",function()
	local f=fixture(1);local model=f.build(false);model.Parent=f.world;f.run();assert(gateCount(model)==0)
	model:SetAttribute("Ready",true);assert(gateCount(model)==2)
	model:SetAttribute("Ready",true);assert(gateCount(model)==2)
end)
test("revision3 or nonowned model remains untouched",function()
	for _,settings in ipairs({{3,true},{4,false}})do
		local f=fixture(1);local model,_,labels,prompts=f.build(true,settings[1],settings[2]);model.Parent=f.world;f.run()
		assert(gateCount(model)==0 and labels[5][1].Visible and prompts[6][1].Enabled)
	end
end)
test("late top-level atomic model arrival builds gates",function()
	local f=fixture(1);f.run();local model=f.build();model.Parent=f.world;assert(gateCount(model)==2)
end)
test("late kiosk descendant is hidden and replicated Enabled true is suppressed locally",function()
	local f=fixture(1);local model,_,_,prompts=f.build();model.Parent=f.world;f.run()
	local label=f.create("TextLabel");label.Name="QueueTitle";label.Parent=model:FindFirstChild("QueueBay_Level5");assert(label.Visible==false)
	prompts[6][1].Enabled=true;assert(prompts[6][1].Enabled==false)
end)
test("a kiosk moved outside owned lobby restores visibility and releases its signal",function()
	local f=fixture(1);local model,_,labels=f.build();model.Parent=f.world;f.run();local before=f.stats.connections
	local label=labels[5][1];label.Parent=f.original;assert(label.Visible and f.stats.connections==before-1)
	label.Visible=false;label.Visible=true;assert(label.Visible)
end)
test("ten Ready reset cycles restore baseline and do not leak connections",function()
	local f=fixture(1);local model,_,labels,prompts=f.build();model.Parent=f.world;f.run();local activeCount=f.stats.connections
	for _=1,10 do
		model:SetAttribute("Ready",false);assert(gateCount(model)==0 and labels[5][1].Visible and prompts[6][1].Enabled)
		assert(f.stats.connections==5) -- One workspace event plus four model-observation signals.
		model:SetAttribute("Ready",true);assert(gateCount(model)==2 and f.stats.connections==activeCount)
	end
end)
test("atomic streaming removal releases all owned signals; reappearance rebuilds cleanly",function()
	local f=fixture(1);local model,_,labels,prompts=f.build();model.Parent=f.world;f.run()
	model.Parent=nil;assert(gateCount(model)==0 and f.stats.connections==1 and labels[5][1].Visible and prompts[6][1].Enabled)
	model.Parent=f.world;assert(gateCount(model)==2 and not labels[5][1].Visible)
end)
test("conflicting folder is preserved and no foreign geometry or visibility changed",function()
	local f=fixture(1);local model,_,labels,prompts=f.build();local foreign=f.create("Folder");foreign.Name="R4ClientDevGates";foreign.Parent=model
	model.Parent=f.world;f.run();assert(model:FindFirstChild("R4ClientDevGates")==foreign and gateCount(model)==0)
	assert(labels[5][1].Visible and prompts[6][1].Enabled and #f.stats.warnings==1)
end)
test("both shutters fit measured aperture and road-facing mounted subtitle without road projection",function()
	local f=fixture(1);local model,headers=f.build();model.Parent=f.world;f.run();local _,folder=gateCount(model)
	for _,level in ipairs({5,6})do
		local container=folder:FindFirstChild("Level"..level.." Client Gate")
		local panel=container:FindFirstChild("Coming Soon Shutter");local status=container:FindFirstChild("Mounted Access Subtitle")
		local gate=headers[level].CFrame*r.CFrame.new(0,-17.2,-1.42)
		local localPanel=gate:ToObjectSpace(panel.CFrame);local at=localPanel.Position
		assert((at-r.Vector3.new(0,7.8,0)).Magnitude<1e-4 and panel.Size==r.Vector3.new(20,15.6,.35))
		local localStatus=gate:ToObjectSpace(status.CFrame);assert(localStatus.Position.Z>1.42 and localStatus.Position.Y>18.54)
		assert(math.abs(panel.CFrame.Position.X-(if level==5 then 191.4 else 248.6))<1e-4)
	end
end)
test("fallback ComingSoon display matches original red design and configured 70/30 fill",function()
	local f=fixture(1);local model=f.build();model.Parent=f.world;f.run();local _,folder=gateCount(model)
	for _,level in ipairs({5,6})do
		local notice=folder["Level"..level.." Client Gate"]["Coming Soon Notice"]
		local gui=notice.ComingSoonDisplay;local screen=gui.Screen
		local progress=if level==5 then 70 else 30
		assert(gui.Face==r.Enum.NormalId.Back and gui.CanvasSize==r.Vector2.new(900,690))
		assert(gui:GetAttribute("ProgressPercent")==progress and gui:GetAttribute("TemplateSource")=="FreshTunnelLobbyBuilderFallback")
		assert(screen.Title.Text=="COMING SOON" and screen.LevelStatus.Text=="WORK IN PROGRESS")
		assert(screen.ProgressPercent.Text==progress.."% COMPLETE")
		assert(screen.ProgressTrack.ProgressFill.Size==r.UDim2.fromScale(progress/100,1))
		assert(screen.Title.TextColor3==r.Color3.fromRGB(255,76,60))
		assert(notice.Size==r.Vector3.new(15.9,11.9,.07))
	end
end)
local function originalTemplate(f, level)
	local doors=f.create("Folder");doors.Name="LevelDoorways";doors.Parent=f.original
	local host=f.create("Part");host.Name="ComingSoonPanel";host.Parent=doors
	local gui=f.create("SurfaceGui");gui.Name="ComingSoonDisplay";gui:SetAttribute("ComingSoonGateVersion",3);gui:SetAttribute("FutureLevel",level);gui.Parent=host
	local screen=f.create("Frame");screen.Name="Screen";screen:SetAttribute("OriginalLayoutSentinel","preserve");screen.Parent=gui
	local title=f.create("TextLabel");title.Name="Title";title.Text="COMING SOON";title.Parent=screen
	local kicker=f.create("TextLabel");kicker.Name="GateKicker";kicker.Text="ORIGINAL";kicker.Parent=screen
	local track=f.create("Frame");track.Name="ProgressTrack";track.Parent=screen
	local fill=f.create("Frame");fill.Name="ProgressFill";fill.Size=r.UDim2.fromScale(.9,1);fill.Parent=track
	local number=f.create("TextLabel");number.Name="ProgressPercent";number.Text="90% COMPLETE";number.Parent=screen
	return gui
end
test("fresh valid original ComingSoon layout is cloned without mutating original 90% display",function()
	local f=fixture(1);local template=originalTemplate(f,4);local model=f.build();model.Parent=f.world;f.run();local _,folder=gateCount(model)
	for _,level in ipairs({5,6})do
		local gui=folder["Level"..level.." Client Gate"]["Coming Soon Notice"].ComingSoonDisplay
		assert(gui~=template and gui:GetAttribute("TemplateSource")=="OriginalLobbyComingSoonDisplay")
		assert(gui.Screen:GetAttribute("OriginalLayoutSentinel")=="preserve")
		assert(gui.Screen.GateKicker.Text==string.format("ZYNTRA TRANSIT // GATE %02d",level))
		assert(gui:GetAttribute("ProgressPercent")==(if level==5 then 70 else 30))
	end
	assert(template.Screen.ProgressPercent.Text=="90% COMPLETE" and template.Screen.ProgressTrack.ProgressFill.Size==r.UDim2.fromScale(.9,1))
end)
test("original layout containing a script is not cloned",function()
	local f=fixture(1);local template=originalTemplate(f,5);local foreign=f.create("LocalScript");foreign.Parent=template
	local model=f.build();model.Parent=f.world;f.run();local _,folder=gateCount(model)
	local gui=folder["Level5 Client Gate"]["Coming Soon Notice"].ComingSoonDisplay
	assert(gui:GetAttribute("TemplateSource")=="FreshTunnelLobbyBuilderFallback" and foreign.Parent==template)
	for _,child in ipairs(gui:GetDescendants())do assert(not child:IsA("LuaSourceContainer"))end
end)

local passed=true
for _,case in ipairs(cases)do passed=passed and case.passed end
local receipt={scope="Offline exact-source syntax, current DevAccess policy and mocked client presentation/lifetime; not actual Studio Play or server-authority proof",passed=passed,testCount=#cases,cases=cases,
	candidateSHA256=serde.hash("sha256",source),candidateBytes=#source,accessSourceSHA256=serde.hash("sha256",accessSource),serverSourcesChanged=false}
fs.writeFile(ROOT.."client-test-receipt.json",serde.encode("json",receipt,true).."\n")
print(serde.encode("json",receipt,true));assert(passed)
