-- Table-only regression fixture: compile in Edit, call with Objective Controller
-- source. The real public method, authorization, actuator body, gauges, sounds
-- and drain scheduling run. A test-only initializer attaches the unchanged pump
-- loop to a minimal session; unrelated exit/flume construction is not exercised.
-- No DataModel instances, actual users, geometry or scripts are changed.
return function(objectiveSource)
	local results = {}
	local pumpStart = assert(objectiveSource:find(
		"\tfor _, pump in ipairs(manifest.Pumps) do\n\t\tlocal function activate", 1, true))
	local pumpEnd = assert(objectiveSource:find(
		"\n\t-- LEVEL2_EXIT_TRANSITION_20260828\n\t-- Completion", pumpStart, true))
	local pumpLoop = objectiveSource:sub(pumpStart, pumpEnd - 1)
	local sourceBody = assert(objectiveSource:match("^(.*)\nreturn ObjectiveController%s*$"))
	local fixtureSource = sourceBody .. [[

function ObjectiveController.__FixtureStart(manifest, generation)
	ObjectiveController.Stop()
	local session = {Manifest=manifest, Generation=generation, Connections={}, GaugeTweens={},
		DebugActivators={}, DevPumpLastRequest={}, Started={}, StartedCount=0, DoorsOpen=false,
		Escaping={}, Transitioning={}, PumpSoundDuration=11.572244897959184}
	activeSession = session
	local goal = #manifest.Pumps
]] .. pumpLoop .. [[
	return session
end
return ObjectiveController
]]
	local function signal()
		local self = {Connections = {}}
		function self:Connect(callback)
			local connection = {Connected=true, Callback=callback}
			function connection:Disconnect() self.Connected=false end
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
		local h = {Clock=100, Delayed={}, Sounds={}, Tweens={}, Drains={}, Flags={}}
		local methods = {}
		local function object(className, name)
			return setmetatable({_class=className, Name=name or className, _children={},
				_attributes={}, _signals={}, AncestryChanged=signal()}, {
				__index=function(self,key)
					if key=="Parent" then return rawget(self,"_parent") end
					return methods[key]
				end,
				__newindex=function(self,key,value)
					if key~="Parent" then rawset(self,key,value) return end
					local old=rawget(self,"_parent")
					if old==value then return end
					if old then
						local index=table.find(old._children,self)
						if index then table.remove(old._children,index) end
					end
					rawset(self,"_parent",value)
					if value then table.insert(value._children,self) end
					self.AncestryChanged:Fire(self,value)
				end,
			})
		end
		function methods:IsA(className)
			return className==self._class or className=="BasePart" and self._class=="Part"
		end
		function methods:GetAttribute(name) return self._attributes[name] end
		function methods:SetAttribute(name,value)
			local old=self._attributes[name]
			self._attributes[name]=value
			if old~=value and self._signals[name] then self._signals[name]:Fire() end
		end
		function methods:GetAttributeChangedSignal(name)
			self._signals[name]=self._signals[name] or signal()
			return self._signals[name]
		end
		function methods:GetPropertyChangedSignal(name) return self:GetAttributeChangedSignal("property:"..name) end
		function methods:FindFirstChild(name)
			for _,child in ipairs(self._children) do if child.Name==name then return child end end
		end
		function methods:WaitForChild(name) return assert(self:FindFirstChild(name),name) end
		function methods:FindFirstChildOfClass(className)
			for _,child in ipairs(self._children) do if child:IsA(className) then return child end end
		end
		function methods:IsDescendantOf(ancestor)
			local parent=self.Parent
			while parent do if parent==ancestor then return true end parent=parent.Parent end
			return false
		end
		function methods:GetPivot() return self.Pivot or CFrame.new() end
		h.Workspace=object("Workspace")
		for name,value in pairs({SelectedLevel=2,RoundActive=true,WorldGenerated=true,Level2Pumps=0}) do
			h.Workspace:SetAttribute(name,value)
		end
		function h.Workspace:GetServerTimeNow() return h.Clock end
		function h.Workspace:Raycast()
			return h.Flags.Wall and {Instance=object("Part","Wall")} or nil
		end
		h.Workspace.Terrain={FillBlock=function(_,cframe,size,material)
			table.insert(h.Drains,{At=h.Clock,CFrame=cframe,Size=size,Material=material})
		end}
		h.Players=object("Players")
		h.Players.PlayerRemoving=signal()
		function h.Players:GetPlayers() return table.clone(self._children) end
		function h:Player(name,allowed)
			local player=object("Player",name)
			player.Parent=self.Players
			player.UserId=#self.Players._children
			player.Allowed=allowed
			player.CharacterRemoving=signal()
			player:SetAttribute("InRound",true)
			local character=object("Model",name.." Character")
			character.Parent=self.Workspace
			player.Character=character
			local humanoid=object("Humanoid")
			humanoid.Health=100 humanoid.Died=signal() humanoid.Parent=character
			local root=object("Part","HumanoidRootPart")
			root.Position=Vector3.new(1000,3,1000) root.Parent=character
			return player,humanoid,root
		end
		h.Developer,h.Humanoid,h.Root=h:Player("Developer",true)
		local replicated=object("ReplicatedStorage")
		local access=object("ModuleScript","DevAccess") access.Parent=replicated
		h.State=object("Folder","Level 2 State") h.State.Parent=replicated
		local sound=object("RemoteEvent","Level 2 Sound Event") sound.Parent=replicated
		function sound:FireClient(player,cue) table.insert(h.Sounds,{Player=player,Cue=cue,At=h.Clock}) end
		function sound:FireAllClients(cue) table.insert(h.Sounds,{Cue=cue,At=h.Clock}) end
		local tweenService={}
		function tweenService:Create(target,info,properties)
			local tween={Target=target,Info=info,Properties=properties,Completed=signal()}
			function tween:Play() self.Played=true end
			function tween:Cancel() self.Cancelled=true end
			table.insert(h.Tweens,tween)
			return tween
		end
		local services={Players=h.Players,ReplicatedStorage=replicated,TweenService=tweenService,
			RunService={IsStudio=function() return true end},ContentProvider={},SoundService={}}
		local baseTypeof=typeof
		local environment=setmetatable({
			game={GetService=function(_,name) return assert(services[name],name) end},
			workspace=h.Workspace,
			require=function(module)
				assert(module==access)
				return {IsAllowed=function(player) return type(player)=="table" and player.Allowed==true end}
			end,
			typeof=function(value)
				return type(value)=="table" and value._class and "Instance" or baseTypeof(value)
			end,
			os={clock=function() return h.Clock end},
			task={delay=function(delay,callback)
				table.insert(h.Delayed,{At=h.Clock+delay,Callback=callback})
			end},
			RaycastParams={new=function() return {} end},
		},{__index=getfenv()})
		local chunk=assert(loadstring(fixtureSource,"DevPumpObjectiveUnderTest"))
		setfenv(chunk,environment)
		h.Controller=chunk()
		h.World=object("Model","Level 2 Generated World")
		h.World.Parent=h.Workspace h.World:SetAttribute("Level2_Generation",1)
		h.Manifest={World=h.World,Pumps={},Drains={},PressureDoors={},Exit={}}
		h.ByIndex={}
		for _,index in ipairs({3,1,2}) do
			local model=object("Model","Pump "..index) model.Parent=h.World
			local lever=object("Part","Lever") lever.Parent=model lever.Position=Vector3.new(index*20,1,0)
			lever.CFrame=CFrame.new(lever.Position)
			local prompt=object("ProximityPrompt") prompt.Parent=lever prompt.Enabled=true
			prompt.MaxActivationDistance=10 prompt.RequiresLineOfSight=true prompt.Triggered=signal()
			local lamp=object("Part","Lamp") lamp.Parent=model
			local needle=object("Part","Needle") needle.Parent=model
			local value=object("NumberValue","Pressure") value.Value=0 value.Parent=model
			local label=object("TextLabel","Readout") label.Parent=model
			local pump={Index=index,Model=model,Prompt=prompt,Lamp=lamp,Lever=lever,
				GaugeNeedlePivot=needle,GaugeNeedleZeroCFrame=CFrame.new(),
				GaugeNeedleFullCFrame=CFrame.Angles(0,0,1),GaugePressureValue=value,GaugePressureText=label}
			table.insert(h.Manifest.Pumps,pump) h.ByIndex[index]=pump
			h.Manifest.Drains[index]={Water={CFrame=CFrame.new(index,0,0),Size=Vector3.one}}
		end
		h.Session=h.Controller.__FixtureStart(h.Manifest,1)
		function h:Advance(seconds)
			local target=self.Clock+seconds
			local turns=0
			while true do
				table.sort(self.Delayed,function(a,b) return a.At<b.At end)
				local nextTask=self.Delayed[1]
				if not nextTask or nextTask.At>target+.000001 then break end
				table.remove(self.Delayed,1) self.Clock=nextTask.At
				turns+=1 assert(turns<100,"unbounded delayed callback loop")
				nextTask.Callback()
			end
			self.Clock=target
		end
		function h:Pull() return self.Controller.DevActivatePumpPair(self.Developer) end
		function h:Count() return self.Session.StartedCount end
		function h:AssertCancelled()
			self:Advance(6)
			assert(self:Count()==1,"cancelled sequence pulled another pump")
			assert(self.Session.DevPumpSequence==nil,"cancelled sequence stayed locked")
			assert(self.Developer:GetAttribute("DevLevel2PumpBusy")==false)
		end
		return h
	end
	local function test(name,callback)
		local ok,failure=xpcall(callback,debug.traceback)
		table.insert(results,{Name=name,Passed=ok,Error=not ok and tostring(failure) or nil})
	end
	test("index order, first immediate and second exactly five seconds later, never third",function()
		local h=harness()
		local ok,status=h:Pull()
		assert(ok and status=="FIRST_PULLED_SECOND_IN_5_SECONDS")
		assert(h:Count()==1 and h.Session.Started[1] and not h.Session.Started[2])
		assert(h.Developer:GetAttribute("DevLevel2PumpBusy")==true)
		h:Advance(4.999) assert(h:Count()==1)
		h:Advance(.001) assert(h:Count()==2 and h.Session.Started[2] and not h.Session.Started[3])
		assert(h.State:GetAttribute("Level2_PumpStartedAt2")-h.State:GetAttribute("Level2_PumpStartedAt1")==5)
		assert(h.Developer:GetAttribute("DevLevel2PumpStatus")=="TWO_PUMPS_PULLED")
		assert(h.Developer:GetAttribute("DevLevel2PumpBusy")==false)
		assert(#h.Tweens==6 and #h.Sounds==2,"real actuator did not run lever/gauge/audio")
		h:Advance(5) assert(#h.Drains==1 and h.Drains[1].At==110)
		h:Advance(5) assert(#h.Drains==2 and h.Drains[2].At==115 and h:Count()==2)
	end)
	test("normal prompt and Studio debug retain distance and line-of-sight checks",function()
		local h=harness()
		h.ByIndex[1].Prompt.Triggered:Fire(h.Developer)
		h.Controller.DebugActivatePump(1,h.Developer)
		assert(h:Count()==0,"ordinary remote-distance activation bypassed proximity")
		h.Root.Position=h.ByIndex[1].Lever.Position h.Flags.Wall=true
		h.ByIndex[1].Prompt.Triggered:Fire(h.Developer)
		assert(h:Count()==0,"ordinary activation bypassed line of sight")
		assert(h:Pull() and h:Count()==1,"privileged actuator did not support remote lever testing")
	end)
	test("nondeveloper and nonplayer inputs cannot activate the public method",function()
		local h=harness()
		local outsider=h:Player("Outsider",false)
		for _,subject in ipairs({outsider,9488575949,"Developer"}) do
			local ok,reason=h.Controller.DevActivatePumpPair(subject)
			assert(not ok and reason=="NOT_ALLOWED")
		end
		assert(h:Count()==0 and #h.Delayed==0)
	end)
	for _,scenario in ipairs({"level","round","generated","dead","escaped","notParticipant","generation"}) do
		test("reject invalid live context: "..scenario,function()
			local h=harness()
			if scenario=="level" then h.Workspace:SetAttribute("SelectedLevel",3)
			elseif scenario=="round" then h.Workspace:SetAttribute("RoundActive",false)
			elseif scenario=="generated" then h.Workspace:SetAttribute("WorldGenerated",false)
			elseif scenario=="dead" then h.Humanoid.Health=0
			elseif scenario=="escaped" then h.Developer:SetAttribute("Escaped",true)
			elseif scenario=="notParticipant" then h.Developer:SetAttribute("InRound",false)
			elseif scenario=="generation" then h.World:SetAttribute("Level2_Generation",2) end
			assert(not h:Pull() and h:Count()==0 and #h.Delayed==0)
		end)
	end
	test("overlap and repeated clicks cannot duplicate either lever",function()
		local h=harness() assert(h:Pull())
		local ok,reason=h:Pull() assert(not ok and reason=="THROTTLED")
		h:Advance(1.1)
		ok,reason=h:Pull() assert(not ok and reason=="SEQUENCE_BUSY")
		local other=h:Player("Other Developer",true)
		ok,reason=h.Controller.DevActivatePumpPair(other)
		assert(not ok and reason=="SEQUENCE_BUSY")
		h:Advance(4) assert(h:Count()==2 and not h.Session.Started[3])
	end)
	test("one existing pump selects the next two available pumps",function()
		local h=harness()
		h.Root.Position=h.ByIndex[1].Lever.Position
		h.ByIndex[1].Prompt.Triggered:Fire(h.Developer)
		assert(h:Count()==1)
		assert(h:Pull() and h.Session.Started[2] and not h.Session.Started[3])
		h:Advance(5) assert(h:Count()==3 and h.Session.Started[3])
	end)
	test("fewer than two available pumps does not partially activate",function()
		local h=harness()
		for _,index in ipairs({1,2}) do
			h.Root.Position=h.ByIndex[index].Lever.Position
			h.ByIndex[index].Prompt.Triggered:Fire(h.Developer)
		end
		local ok,reason=h:Pull()
		assert(not ok and reason=="NEED_TWO_AVAILABLE_PUMPS" and not h.Session.Started[3])
	end)
	test("another player pulling reserved second pump never substitutes third",function()
		local h=harness() assert(h:Pull())
		h:Advance(2)
		h.Root.Position=h.ByIndex[2].Lever.Position
		h.ByIndex[2].Prompt.Triggered:Fire(h.Developer)
		h:Advance(3)
		assert(h:Count()==2 and not h.Session.Started[3])
		assert(h.Developer:GetAttribute("DevLevel2PumpStatus")=="SECOND_ALREADY_RUNNING")
	end)
	for _,scenario in ipairs({"death","character","disconnect","round","level","generated","escaped","notParticipant","generation","worldRemoved","stop"}) do
		test("late second lever is cancelled: "..scenario,function()
			local h=harness() assert(h:Pull()) h:Advance(2)
			if scenario=="death" then h.Humanoid.Health=0 h.Humanoid.Died:Fire() h.Humanoid.Health=100
			elseif scenario=="character" then h.Developer.CharacterRemoving:Fire(h.Developer.Character)
			elseif scenario=="disconnect" then h.Players.PlayerRemoving:Fire(h.Developer)
			elseif scenario=="round" then h.Workspace:SetAttribute("RoundActive",false) h.Workspace:SetAttribute("RoundActive",true)
			elseif scenario=="level" then h.Workspace:SetAttribute("SelectedLevel",3) h.Workspace:SetAttribute("SelectedLevel",2)
			elseif scenario=="generated" then h.Workspace:SetAttribute("WorldGenerated",false)
			elseif scenario=="escaped" then h.Developer:SetAttribute("Escaped",true)
			elseif scenario=="notParticipant" then h.Developer:SetAttribute("InRound",false)
			elseif scenario=="generation" then h.World:SetAttribute("Level2_Generation",2)
			elseif scenario=="worldRemoved" then h.World.Parent=nil h.World.Parent=h.Workspace
			elseif scenario=="stop" then h.Controller.Stop() end
			h:AssertCancelled()
		end)
	end
	test("same-session permissions are rechecked before second lever",function()
		local h=harness() assert(h:Pull())
		h.Developer.Allowed=false
		h:AssertCancelled()
	end)
	test("new objective generation cannot receive a stale second activation",function()
		local h=harness() assert(h:Pull())
		local old=h.Session
		h.World:SetAttribute("Level2_Generation",2)
		h.Session=h.Controller.__FixtureStart(h.Manifest,2)
		h:Advance(6)
		assert(old.StartedCount==1 and h.Session.StartedCount==0)
	end)
	local passed=0
	for _,result in ipairs(results) do if result.Passed then passed+=1 end end
	return {Passed=passed,Total=#results,Results=results}
end
