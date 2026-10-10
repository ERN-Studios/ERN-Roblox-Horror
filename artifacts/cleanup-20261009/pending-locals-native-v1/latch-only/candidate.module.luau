return function()
local os={clock=function()return 100 end}

local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end

-- ── engine stubs: only the boundary, never the logic under test ──
local sent = {}
local eventTrace = {}
local status = {}
function status:FireClient(target, ...) table.insert(sent, {target = target, args = {...}});eventTrace[#eventTrace+1]={target=target.Name,args={...}} end
function status:FireAllClients(...) table.insert(sent, {target = 'all', args = {...}});eventTrace[#eventTrace+1]={target='all',args={...}} end
local function teamEvents()
    local out = {}
    for _, entry in ipairs(sent) do
        if entry.args[1] == 'objective' then table.insert(out, entry) end
    end
    return out
end

local function makePlayer(name, inRound)
    local p = {Name = name, Attributes = {InRound = inRound}, Character = {}}
    function p:GetAttribute(key) return self.Attributes[key] end
    function p:SetAttribute(key, value) self.Attributes[key] = value end
    function p.Character:FindFirstChildOfClass() return p.Humanoid end
    function p.Character:FindFirstChild() return nil end
    return p
end

local roster = {}
local Players = {}
function Players:GetPlayers() return roster end
function Players:FindFirstChild(name) for _, p in ipairs(roster) do if p.Name == name then return p end end end

local workspaceAttributes = {RoundActive = true}
local workspace = {}
function workspace:GetAttribute(key) return workspaceAttributes[key] end
function workspace:SetAttribute(key, value) workspaceAttributes[key] = value end
function workspace:FindFirstChild() return nil end

local Color3 = {fromRGB = function(r, g, b) return {r, g, b} end}
local task = {delay = function() end}
local game = {GetService = function() return {FindFirstChild = function() return nil end} end}
local function attr(_, default) return default end
local function updateCarriedFuse() end
local function updateEntityObjectiveTarget() end
local function showFuseInBox() end
local function entityToArea() end
local function setLeverHandle(lever, on) lever.on = on end
local FUSES_PER_BOX, FLICK_PER_FUSE, SPEED_PER_FUSE = 1, 0.6, 0.06
local ENTITY_AREA_CELLS, CELLv, LEVER_WINDOW = 5, 24, 10

-- ── the production announceTeam, verbatim ──
local remote = status
local Analytics = {Objective = function() end}
local TeamObjectives, serial = {}, 0
function TeamObjectives.Announce(actorName, detail, level, key)
	if type(actorName) ~= "string" or type(detail) ~= "string" then return end
	-- Attributed to the ACTOR only, never the party: every caller passes a
	-- player's own name and names are unique within a server. Measurement only.
	Analytics.Objective(Players:FindFirstChild(actorName), level)
	serial += 1
	local payload = {Actor = actorName, Detail = detail, Level = level, Serial = serial,
		Key = type(key) == "string" and key or nil}
	for _, recipient in ipairs(Players:GetPlayers()) do
		-- Dead/escaped teammates retain InRound until their round closes.
		if recipient:GetAttribute("InRound") == true then
			remote:FireClient(recipient, "objective", payload)
		end
	end
end
local function announceTeam(actorName, kind, detail)
	TeamObjectives.Announce(actorName, detail, 1, "level1:" .. kind)
end

-- ── the production prompt handlers, verbatim ──
local session, canUsePrompt
local allowed = true
canUsePrompt = function() return allowed end

local mikkel = makePlayer('MikkelCzar', true)
local mate = makePlayer('Mate', true)
local lobby = makePlayer('Lobby', nil)
roster = {mikkel, mate, lobby}

-- fuse pickup off a dropped stack
local owningSession, count, model, prompt, claimed
local fuseHandler

-- fuse box
local box, boxIndex
local boxHandler

-- lever
local lever
local leverHandler

local function freshSession()
local folder={}
local boxCount=3
local roundPlayerSet={[mikkel]=true,[mate]=true}
	session = {
		active = true, stage = "fuses", conns = {}, folder = folder,
		boxes = {}, levers = {}, circuits = {}, relays = {}, fuses = {}, carried = {}, exit = nil,
		boxesDone = 0, boxCount = boxCount,
		escaped = {}, escapeAnnounced = false, -- who's out + first-escape latch
		participants = roundPlayerSet, fuseCharacters = {},
	}
    session.fuseCharacters[mikkel] = {Character = mikkel.Character, Humanoid = mikkel.Humanoid}
    session.fuseCharacters[mate] = {Character = mate.Character, Humanoid = mate.Humanoid}
    owningSession = session
    session.updateEntityObjectiveTarget = updateEntityObjectiveTarget
    for index = 1, 3 do
        session.circuits[index] = {Attributes = {},
            SetAttribute = function(self, key, value) self.Attributes[key] = value end,
            GetAttribute = function(self, key) return self.Attributes[key] end}
    end
    table.clear(sent)
end

local function freshBox(index)
    boxIndex = index
    box = {count = 0, complete = false, prompt = {Enabled = true}, model = {},
        ind = {}, indicatorLight = {}, statusLabel = {}, body = {Position = 0}}
    session.boxes[index] = box
    return box
end

local function freshLever(index)
    lever = {latched = false, activeUntil = 0, prompt = {Enabled = true}, model = {},
        pullSound = nil, cf = {Position = 0}}
    session.levers[index] = lever
    return lever
end

fuseHandler = function(player)
		if claimed or session ~= owningSession or not model.Parent then return end
		if player:GetAttribute("InRound") ~= true or workspace:GetAttribute("RoundActive") ~= true then return end
		if not canUsePrompt(player, prompt, model) then return end
		local record = owningSession.fuseCharacters[player]
		if not record or record.Character ~= player.Character or record.Humanoid ~= player.Character:FindFirstChildOfClass("Humanoid") then return end
		-- No yield between validation, consuming this stack, and updating inventory.
		claimed = true
		prompt.Enabled = false
		owningSession.carried[player] = (owningSession.carried[player] or 0) + count
		model:Destroy()
		updateCarriedFuse(player, owningSession.carried[player])
		status:FireClient(player, "carry", owningSession.carried[player])
		-- Replaces the private "Fuse picked up": the party learns who has it, and
		-- the picker still sees the count on their own carry row.
		announceTeam(player.Name, "fuse",
			count == 1 and "took a fuse" or ("took " .. count .. " fuses"))
		if owningSession.updateEntityObjectiveTarget then owningSession.updateEntityObjectiveTarget() end
end
boxHandler = function(player)
			if not session or not session.active or box.complete then return end
			if not canUsePrompt(player, box.prompt, box.model) then return end
			local have = session.carried[player] or 0
			if have <= 0 then
				status:FireClient(player, "msg", "You have no fuses")
				return
			end
			session.carried[player] = have - 1
			updateCarriedFuse(player, session.carried[player])
			status:FireClient(player, "carry", session.carried[player])
			box.count += 1
			local research=game:GetService("ServerStorage"):FindFirstChild("ZyntraResearchProgress")
			if research then research:Fire(player,"Fuse") end
			updateEntityObjectiveTarget()
			showFuseInBox(box, box.count)
			box.ind.Color = Color3.fromRGB(235, 165, 45)
			box.indicatorLight.Color = box.ind.Color
			box.indicatorLight.Brightness = 1.1
			box.statusLabel.Text = "PARTIAL POWER"
			box.statusLabel.TextColor3 = Color3.fromRGB(245, 185, 65)
			box.prompt.ObjectText = ("Fuse Box (%d/%d)"):format(box.count, FUSES_PER_BOX)

			-- ramp the danger; the entity shows up in the AREA (not on top of you)
			workspace:SetAttribute("FlickerBoost",
				math.min(attr("FlickerBoost", 0) + FLICK_PER_FUSE, 4))
			-- fuse boxes ramp the entity's speed by at most +10% total (the big
			-- finale boost happens later, when the exit opens: END_SPEED_MUL)
			workspace:SetAttribute("EntitySpeedMul",
				math.min(attr("EntitySpeedMul", 1) + SPEED_PER_FUSE, 1.1))
			-- summon the entity to the AREA — but NOT if it's already near the
			-- player (don't teleport it right on top of them / it's already here)
			local pchar = player.Character
			local phrp = pchar and pchar:FindFirstChild("HumanoidRootPart")
			local ent = workspace:FindFirstChild("Entity")
			local eroot = ent and ent.PrimaryPart
			local alreadyNear = phrp and eroot
				and (phrp.Position - eroot.Position).Magnitude < ENTITY_AREA_CELLS * CELLv
			if not alreadyNear then
				entityToArea(box.body.Position, ENTITY_AREA_CELLS)
			end

			if box.count >= FUSES_PER_BOX then
				box.complete = true
				box.prompt.Enabled = false
				box.ind.Color = Color3.fromRGB(50, 220, 60)
				box.indicatorLight.Color = box.ind.Color
				box.indicatorLight.Brightness = 1.8
				box.indicatorLight.Range = 10
				box.statusLabel.Text = "POWER RESTORED"
				box.statusLabel.TextColor3 = Color3.fromRGB(90, 255, 115)
				session.boxesDone += 1
				status:FireAllClients("boxes", session.boxesDone, session.boxCount)
				-- This pair's cable now carries power OUT of the box: the client
				-- current reverses toward the lever off this one attribute, so the
				-- visual can never disagree with the authoritative box state.
				local circuit = session.circuits[boxIndex]
				if circuit then circuit:SetAttribute("Powered", true) end
				announceTeam(player.Name, "box",
					("powered a box \u{B7} %d/%d"):format(session.boxesDone, session.boxCount))
				if session.boxesDone >= session.boxCount then
					session.onAllBoxes()
				end
			else
				-- Unreachable while FUSES_PER_BOX is 1, and the one line that keeps
				-- a partial deposit from being the only silent action in the level.
				announceTeam(player.Name, "box",
					("fed a box \u{B7} %d/%d"):format(box.count, FUSES_PER_BOX))
			end
end
leverHandler = function(player)
			if not session or not session.active or session.stage ~= "levers" then return end
			-- Same contract as the relays: only a living, present member of the
			-- launched party may drive the exit circuit.
			if not canUsePrompt(player, lever.prompt, lever.model) then return end
			if lever.latched then return end
			if lever.pullSound then lever.pullSound:Play() end
			lever.latched = true
			local research=game:GetService("ServerStorage"):FindFirstChild("ZyntraResearchProgress")
			if research then research:Fire(player,"Lever") end
			lever.prompt.Enabled = false
			setLeverHandle(lever, true)
			updateEntityObjectiveTarget()
			if session.updateLeverLights then session.updateLeverLights() end
			if session.broadcastLeverStatus then session.broadcastLeverStatus() end

			local on = 0
			for _, lv in ipairs(session.levers) do
				if lv.latched then on += 1 end
			end
			announceTeam(player.Name, "lever",
				("pulled lever \u{B7} %d/%d"):format(on, #session.levers))
			if on == #session.levers then session.onLevers(lever.cf.Position) end
end

local function boxOnLevers() end

-- ═══ 1. a validated fuse pickup announces exactly one team event ═══
freshSession()
count, claimed = 1, false
model = {Parent = true, Destroy = function(self) self.Parent = nil end}
prompt = {Enabled = true}
fuseHandler(mikkel)
local events = teamEvents()
expect(#events, 2, 'one team event per in-round player (three players, one in the lobby)')
local recipients = {}
for _, entry in ipairs(events) do recipients[entry.target.Name] = true end
expect(recipients.Lobby, nil, 'the lobby player is never told about a round it is not in')
expect(events[1].args[2].Actor, 'MikkelCzar', 'actor name')
expect(events[1].args[2].Key, 'level1:fuse', 'kind')
expect(events[1].args[2].Detail, 'took a fuse', 'detail')

-- ═══ 2. a refused prompt announces nothing ═══
freshSession()
allowed = false
count, claimed = 1, false
model = {Parent = true, Destroy = function(self) self.Parent = nil end}
prompt = {Enabled = true}
fuseHandler(mikkel)
expect(#teamEvents(), 0, 'canUsePrompt refused -> no team prompt')
allowed = true

-- ═══ 3. a multi-fuse stack says so ═══
freshSession()
count, claimed = 3, false
model = {Parent = true, Destroy = function(self) self.Parent = nil end}
prompt = {Enabled = true}
fuseHandler(mate)
expect(teamEvents()[1].args[2].Detail, 'took 3 fuses', 'a stack of three')

-- ═══ 4. powering a fuse box: one event, running count, circuit powered ═══
freshSession()
session.onAllBoxes = boxOnLevers
session.carried[mikkel] = 1
freshBox(2)
boxHandler(mikkel)
local boxEvents = teamEvents()
expect(#boxEvents, 2, 'one team event per in-round player')
expect(boxEvents[1].args[2].Key, 'level1:box', 'kind')
expect(boxEvents[1].args[2].Detail, 'powered a box \u{B7} 1/3', 'what changed and what remains')
expect(session.circuits[2]:GetAttribute('Powered'), true, 'the pair circuit is marked powered')
expect(session.circuits[1]:GetAttribute('Powered'), nil, 'and only that pair')

-- ═══ 5. a deposit with no fuse is a private refusal, not a team prompt ═══
freshSession()
session.onAllBoxes = boxOnLevers
session.carried[mikkel] = 0
freshBox(1)
boxHandler(mikkel)
expect(#teamEvents(), 0, 'no fuse carried -> no team prompt')
expect(sent[1].args[1], 'msg', 'the actor alone is told')

-- ═══ 6. the last box announces before the lever phase opens ═══
freshSession()
session.boxesDone = 2
local opened = false
session.onAllBoxes = function() opened = true end
session.carried[mikkel] = 1
freshBox(3)
boxHandler(mikkel)
expect(teamEvents()[1].args[2].Detail, 'powered a box \u{B7} 3/3', 'the final box')
expect(opened, true, 'and the lever phase still opens')

-- ═══ 7. a lever pull announces once; re-triggering inside its window does not ═══
freshSession()
session.stage = 'levers'
freshLever(1)
session.levers[2] = {latched = false, activeUntil = 0, prompt = {Enabled = true}}
session.levers[3] = {latched = false, activeUntil = 0, prompt = {Enabled = true}}
session.onLevers = function() end
session.broadcastLeverStatus = function() end
session.updateLeverLights = function() end
session.updateEntityObjectiveTarget = updateEntityObjectiveTarget
leverHandler(mate)
local leverEvents = teamEvents()
expect(#leverEvents, 2, 'one per in-round player')
expect(leverEvents[1].args[2].Key, 'level1:lever', 'kind')
expect(leverEvents[1].args[2].Detail, 'pulled lever \u{B7} 1/3', 'running lever count')
table.clear(sent)
leverHandler(mate)
expect(#teamEvents(), 0, 'the same lever, still inside its window, says nothing new')

-- ═══ 8. a second lever counts up ═══
table.clear(sent)
session.levers[2].activeUntil = 0
lever = session.levers[2]
leverHandler(mikkel)
expect(teamEvents()[1].args[2].Detail, 'pulled lever \u{B7} 2/3', 'second lever')



local surfaceLightCache={old=true}
local function clearPuzzle()
	workspace:SetAttribute("Level1RelaysExtracted", nil)
	surfaceLightCache = nil -- the maze (and its lights) is rebuilt every round
	if not session then
		workspace:SetAttribute("Level1ActiveCircuitCount", nil)
		workspace:SetAttribute("EntityObjectiveTarget", nil)
		workspace:SetAttribute("EntityObjectiveStage", nil)
		return
	end
	session.active = false
	for _, c in ipairs(session.conns) do pcall(function() c:Disconnect() end) end
	if session.folder then session.folder:Destroy() end
	session = nil
	workspace:SetAttribute("Level1ActiveCircuitCount", nil)
	workspace:SetAttribute("LightMode", "NORMAL")
	workspace:SetAttribute("FlickerBoost", 0)
	workspace:SetAttribute("EntitySpeedMul", 1)
	workspace:SetAttribute("EntityObjectiveTarget", nil)
	workspace:SetAttribute("EntityObjectiveStage", nil)
end

local disconnected,destroyed=0,0
freshSession()
local saved=session
session.conns={
 {Disconnect=function() disconnected+=1;error("controlled disconnect failure") end},
 {Disconnect=function() disconnected+=1 end},
}
session.folder={Destroy=function() destroyed+=1 end}
workspaceAttributes.Level1RelaysExtracted=3
workspaceAttributes.Level1ActiveCircuitCount=3
workspaceAttributes.EntityObjectiveTarget="old"
workspaceAttributes.EntityObjectiveStage="fuses"
count,claimed=1,false
model={Parent=true,Destroy=function(self)self.Parent=nil end}
prompt={Enabled=true}
clearPuzzle()
expect(saved.active,false,"clearPuzzle deactivates old private session")
expect(session,nil,"clearPuzzle clears private session")
expect(disconnected,2,"disconnect fault does not skip later connection cleanup")
expect(destroyed,1,"clearPuzzle destroys its controlled folder once")
expect(surfaceLightCache,nil,"clearPuzzle clears rebuilt light cache")
expect(workspaceAttributes.Level1RelaysExtracted,nil,"cleanup clears relays counter")
expect(workspaceAttributes.Level1ActiveCircuitCount,nil,"cleanup clears active circuits")
expect(workspaceAttributes.EntityObjectiveTarget,nil,"cleanup clears objective target")
expect(workspaceAttributes.EntityObjectiveStage,nil,"cleanup clears objective stage")
expect(workspaceAttributes.LightMode,"NORMAL","cleanup restores light mode")
expect(workspaceAttributes.FlickerBoost,0,"cleanup clears flicker boost")
expect(workspaceAttributes.EntitySpeedMul,1,"cleanup restores entity speed")
local beforeLate=#eventTrace
fuseHandler(mikkel)
expect(#eventTrace,beforeLate,"old fuse callback after cleanup cannot emit")
expect(saved.carried[mikkel],nil,"old callback cannot mutate former inventory")
clearPuzzle()
expect(disconnected,2,"empty-session cleanup does not disconnect twice")
expect(destroyed,1,"empty-session cleanup does not destroy twice")
freshSession()
expect(session.active,true,"fresh reentry session is active")
expect(session.boxesDone,0,"fresh reentry starts at zero boxes")
count,claimed=1,false
model={Parent=true,Destroy=function(self)self.Parent=nil end}
prompt={Enabled=true}
fuseHandler(mikkel)
expect(#teamEvents(),2,"reentry retains both in-round recipients")
local afterPickup=#eventTrace
fuseHandler(mikkel)
expect(#eventTrace,afterPickup,"duplicate fuse claim cannot emit twice")
expect(session.carried[mikkel],1,"duplicate fuse claim cannot increase inventory")
local failedSession=session
session.conns={}
session.folder={Destroy=function()error("controlled owned folder failure")end}
local failed=pcall(clearPuzzle)
expect(failed,false,"actual folder failure remains observable")
expect(session,failedSession,"actual folder error retains session for retry")
expect(failedSession.active,false,"folder error still deactivates session")
session.folder={Destroy=function()destroyed+=1 end}
clearPuzzle()
expect(session,nil,"cleanup retry clears failed session")
expect(destroyed,2,"cleanup retry destroys only its current controlled folder")
return {checks=checks,eventTrace=eventTrace,finalWorkspace=workspaceAttributes,
 disconnected=disconnected,destroyed=destroyed,sessionCleared=session==nil}

end
