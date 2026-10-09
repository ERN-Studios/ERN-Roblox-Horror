--!strict
-- Level 3 Reader Client
-- Compact, mobile-safe Energon Reader and server-authored alert toasts.
-- Direction is calculated locally from replicated state; the server remains the
-- sole authority for module collection, exit unlocks, and completion.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer

local LEVEL = 3
local WORLD_NAME = "Level 3 Generated World"
local STATE_FOLDER_NAME = "Level 3 State"
local REMOTES_FOLDER_NAME = "Level 3 Remotes"
local CLIENT_EVENT_NAME = "ClientEvent"

local UPDATE_INTERVAL = 0.10
local MAXIMUM_RANGE = 650
local ACCURACY_DEGREES = {155, 105, 64, 36, 18, 5}
local DISTANCE_NOISE = {0.60, 0.42, 0.27, 0.15, 0.07, 0.0}
-- Full bars inside a room, one bar at roughly the far side of a district: the
-- CD bar is plain proximity, not the exit's fogged signal.
local CD_SIGNAL_RANGE = 260
-- radians/second on a sine, so ~0.8Hz -- a text pulse, never a scene flash, and
-- it never exceeds .40 transparency so the row stays legible at its dimmest.
local ROOM_BLINK_RATE = 5.0

-- UI_STYLE_20260915 (Trello #98). The panel surface, the body/muted/caution
-- faces and the chrome now come from the shared tokens taken off Level 1's
-- Objectives panel and the Mission Brief card. ENERGON stays local: it is the
-- reader's own instrument colour and it carries signal strength.
local RoundHud = require(ReplicatedStorage:WaitForChild("RoundHud"))
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))
local ENERGON = Color3.fromRGB(66, 244, 218)
local PANEL = UIStyle.Color.Panel
local TEXT = UIStyle.Color.Body
local MUTED = UIStyle.Color.Muted
local AMBER = UIStyle.Color.Warning
-- The room indicator's red is the shared danger token, not a fourth level
-- inventing its own (UI_STYLE_20260915).
local DANGER = UIStyle.Color.Danger

local gui = Instance.new("ScreenGui")
gui.Name = "Level3ReaderGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 42
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

ContextActionService:UnbindAction("Level3ToggleExitReader")

local playerGuide = Instance.new("Frame")
playerGuide.Name = "CDPlayerGuide"
playerGuide.AnchorPoint = Vector2.new(.5, 0)
playerGuide.Size = UDim2.fromOffset(136, 50)
playerGuide.BackgroundTransparency = 1
playerGuide.Active = false
playerGuide.Visible = false
playerGuide.Parent = gui
local guideArrow = Instance.new("TextLabel")
guideArrow.Name = "DirectionArrow"
guideArrow.AnchorPoint = Vector2.new(.5, .5)
guideArrow.Position = UDim2.fromScale(.5, 0)
guideArrow.Size = UDim2.fromOffset(22, 22)
guideArrow.BackgroundTransparency = 1
UIStyle.readout(guideArrow, {TextColor=ENERGON, TextSize=20})
guideArrow.TextStrokeTransparency = .3
guideArrow.Text = "\u{25C6}"
guideArrow.Parent = playerGuide
local guideLabel = Instance.new("TextLabel")
guideLabel.Name = "Label"
guideLabel.Position = UDim2.fromOffset(0, 14)
guideLabel.Size = UDim2.new(1, 0, 0, 32)
guideLabel.BackgroundColor3 = PANEL
guideLabel.BackgroundTransparency = .12
guideLabel.BorderSizePixel = 0
UIStyle.readout(guideLabel, {TextColor=ENERGON, TextSize=12})
guideLabel.Text = "CD PLAYER"
guideLabel.Parent = playerGuide
local guideCorner = Instance.new("UICorner")
guideCorner.CornerRadius = UDim.new(0, 5)
guideCorner.Parent = guideLabel

local guidePlayerMode = false
local guideTarget: Vector3? = nil
local guideRoot: BasePart? = nil
local guideBearing, guideDistance = 0, 0
local guideMinX, guideMinY, guideMaxX, guideMaxY = 0, 0, 1, 1
local guideOffsetX, guideOffsetY = 0, 0
local guideProjectionFits = false
-- L3_GUIDE_MOVEMENT_BOUNDS_BEGIN
local function guideMovementCeiling(maxY: number, minY: number, controlsTop: number,
	thumbstickTop: number, jumpTop: number): (number, boolean)
	-- The card extends 46px below its pin; keep an additional 8px gutter.
	local ceiling = math.min(maxY, controlsTop-54, thumbstickTop-54, jumpTop-54)
	return ceiling, ceiling >= minY
end
-- L3_GUIDE_MOVEMENT_BOUNDS_END
local readerConnections: {RBXScriptConnection} = {}
local readerAlive = true

local function trackReaderConnection(connection: RBXScriptConnection): RBXScriptConnection
	if not readerAlive then
		connection:Disconnect()
		return connection
	end
	table.insert(readerConnections, connection)
	return connection
end


local function objectiveCard(): GuiObject?
    local hud = player.PlayerGui:FindFirstChild("RoundHud")
    local card = hud and hud:FindFirstChild("ObjectiveCard")
    return if card and card:IsA("GuiObject") then card else nil
end
local function applyLayout()
    local info = UIDevice.Layout()
    guideOffsetX, guideOffsetY = UIDevice.LocalOffset(gui, 0, 0)
    local width = math.clamp(info.Safe.Width - 32, 100, 136)
    local card = objectiveCard()
    local bottom = if card and card.Visible then card.AbsolutePosition.Y + card.AbsoluteSize.Y else info.Safe.Top + 40
    playerGuide.Size = UDim2.fromOffset(width, 50)
    guideMinX, guideMaxX = info.Safe.Left + width * .5 + 8, info.Safe.Right - width * .5 - 8
    guideMinY, guideMaxY = bottom + 24, info.Safe.Bottom - 90
    guideProjectionFits = guideMaxX >= guideMinX and guideMaxY >= guideMinY
    if info.IsTouch then
        local zones = info.Zones
        local ceiling, fits = guideMovementCeiling(guideMaxY, guideMinY,
            zones.Controls and zones.Controls.Top or math.huge,
            zones.Thumbstick and zones.Thumbstick.Top or math.huge,
            zones.Jump and zones.Jump.Top or math.huge)
        guideMaxY, guideProjectionFits = ceiling, guideProjectionFits and fits
    end
    guideMaxX, guideMaxY = math.max(guideMinX + 1, guideMaxX), math.max(guideMinY + 1, guideMaxY)
    guideLabel.TextSize = 12
    if not guideProjectionFits then playerGuide.Visible = false end
end
-- Rebuild on UIDevice.Changed, which fires for viewport, inset, form factor,
-- and (on desktop only) last-input changes. On a phone this can never fire for
-- an input flip, which is the whole point.
trackReaderConnection(UIDevice.Changed:Connect(applyLayout))

local viewportConnection: RBXScriptConnection? = nil
local function bindCamera()
	if viewportConnection then viewportConnection:Disconnect() end
	-- Cleared, not left holding a dead handle: teardownReader reads this to
	-- decide what still needs disconnecting, and a stale handle would have it
	-- disconnect something already gone.
	viewportConnection = nil
	if not readerAlive then return end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	applyLayout()
end
trackReaderConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
bindCamera()
local function stateFolder(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(STATE_FOLDER_NAME)
	return if folder and folder:IsA("Folder") then folder else nil
end

local function stateAttribute(name: string, workspaceMirror: string?): any
	local state = stateFolder()
	local value = state and state:GetAttribute(name)
	if value == nil and workspaceMirror then value = workspace:GetAttribute(workspaceMirror) end
	return value
end

local function numberAttribute(name: string, workspaceMirror: string?, fallback: number): number
	local value = stateAttribute(name, workspaceMirror)
	return if type(value) == "number" then value else fallback
end

-- SPECTATE_UI_PARITY_20260914 -- whose reader this panel is drawing.
--
-- While spectating, the camera sits on the WATCHED player's head
-- (SpectateController publishes them on the client-local `Spectating` /
-- `SpectateTargetUserId` attributes), so the needle, the signal bars and the
-- hiding blackout all have to come from THEIR body: a spectator must read the
-- panel the player they are watching is reading. `Level3_Hiding` is set by the
-- server on the player (Level 3 Hiding Controller), so it replicates and can be
-- read for anyone. Falls back to yourself whenever there is no living subject,
-- which is exactly the pre-spectate behaviour.
-- A subject only counts while they are a living, in-round, non-escaped
-- participant, i.e. exactly the players SpectateController is willing to pick.
local function spectateSubject(): Player?
	if player:GetAttribute("Spectating") ~= true then return nil end
	local userId = player:GetAttribute("SpectateTargetUserId")
	local watched = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if not watched or watched:GetAttribute("InRound") ~= true
		or watched:GetAttribute("Escaped") == true then return nil end
	local character = watched.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") then
		return watched
	end
	return nil
end

local function readerSubject(): Player
	return spectateSubject() or player
end

-- SPECTATE_UI_PARITY_20260914: an ESCAPED spectator used to fail this gate on
-- their own `Escaped` and lose the panel entirely while watching a living
-- teammate whose panel is the whole point. Being a spectator with a valid
-- subject is now its own way in; the world condition (level) still applies.
local function isActive(): boolean
	local levelActive = workspace:GetAttribute("SelectedLevel") == LEVEL
		and ((player:GetAttribute("Spectating") ~= true and player:GetAttribute("InRound") == true
				and player:GetAttribute("Escaped") ~= true)
			or spectateSubject() ~= nil)
	if RunService:IsStudio()
		and player:GetAttribute("UIRegressionForceLevel3Reader") == true then
		levelActive = workspace:GetAttribute("SelectedLevel") == LEVEL
	end
	return levelActive
		and player:GetAttribute("ZyntraDispatchClientActive") ~= true
		and readerSubject():GetAttribute("Level3_Hiding") ~= true
		-- A screen-owning modal takes the reader with it. The panel is a
		-- TextButton on touch, so leaving it up under an open terminal would put
		-- a live control beneath a modal.
		and not UIDevice.ScreenOwningModalOpen()
end

local function currentWorld(): Model?
	local world = workspace:FindFirstChild(WORLD_NAME)
	return if world and world:IsA("Model") then world else nil
end

local function exitPosition(): Vector3?
	local value = stateAttribute("Level3_ExitPosition", nil)
	if typeof(value) == "Vector3" then return value :: Vector3 end
	return nil
end


local cachedPlayerWorld: Model? = nil
local cachedPlayerControl: BasePart? = nil
local nextPlayerControlSearch = 0
local function cdPlayerPosition(): Vector3?
	local value = stateAttribute("Level3_CDPlayerPosition", "Level3CDPlayerPosition")
	if typeof(value) == "Vector3" then return value :: Vector3 end
	-- A bounded streamed-instance fallback for an older server. The replicated
	-- exact control-panel position remains available when the model is absent.
	local world = currentWorld()
	if world ~= cachedPlayerWorld then
		cachedPlayerWorld, cachedPlayerControl, nextPlayerControlSearch = world, nil, 0
	end
	if cachedPlayerControl and world and cachedPlayerControl:IsDescendantOf(world) then
		return cachedPlayerControl.Position
	end
	if not world or os.clock() < nextPlayerControlSearch then return nil end
	nextPlayerControlSearch = os.clock() + 1
	local control = world:FindFirstChild("Disc Player Control Panel", true)
	if control and control:IsA("BasePart")
		and control:GetAttribute("Level3_DiscPlayerControlPanel") == true then
		cachedPlayerControl = control
		return control.Position
	end
	return nil
end

local function generationMatches(payload: {[any]: any}): boolean
	local payloadGeneration = payload.Generation
	if type(payloadGeneration) ~= "number" then return true end
	local world = currentWorld()
	local liveGeneration = world and world:GetAttribute("Level3_Generation")
	return type(liveGeneration) ~= "number" or liveGeneration == payloadGeneration
end


local toastUntil = 0
local function cleanText(value: any, fallback: string, maximum: number): string
    local text = (if type(value) == "string" then value else fallback) :: string
    return text:gsub("[%c]", " "):sub(1, maximum)
end
local function feedAllowed(): boolean
    return workspace:GetAttribute("SelectedLevel") == LEVEL
        and (player:GetAttribute("InRound") == true or spectateSubject() ~= nil)
end
local function showToast(titleText: any, subtitle: any, instruction: any, duration: any)
    if not feedAllowed() then return end
    local first, second = cleanText(subtitle, "", 110), cleanText(instruction, "", 110)
    local detail = cleanText(titleText, "Level 3", 72)
    if first ~= "" then detail ..= ". " .. first end
    if second ~= "" then detail ..= ". " .. second end
    toastUntil = os.clock() + math.clamp(if type(duration) == "number" then duration else 2.4, .8, 6)
    RoundHud.Feed({Kind = "LEVEL", Detail = detail, Key = "level3:alert"})
end
local function handleClientEvent(payload: any)
    if type(payload) ~= "table" or not generationMatches(payload) or not feedAllowed() then return end
    local kind = payload.Type
    if kind == "Alert" then
        showToast(payload.Title, payload.Subtitle, payload.Instruction, payload.Duration)
    elseif kind == "ModuleCollected" then
        local progress = math.max(0, math.floor(tonumber(payload.CollectedProgress or payload.Progress) or 0))
        local goal = math.max(1, math.floor(tonumber(payload.Goal) or 5))
        RoundHud.Feed({Kind = "TEAM", Actor = cleanText(payload.CollectorName, "Someone", 36),
            Detail = (payload.RecoveredDrop == true and "recovered a CD" or "found a CD")
                .. string.format(" \u{B7} %d/%d", math.min(progress, goal), goal), Key = "level3:cd"})
        toastUntil = os.clock() + 2.2
    elseif kind == "CDInserted" then
        local progress = math.max(0, math.floor(tonumber(payload.InsertedCount or payload.Progress) or 0))
        local goal = math.max(1, math.floor(tonumber(payload.Goal) or 5))
        RoundHud.Feed({Kind = "TEAM", Actor = cleanText(payload.DepositorName, "Someone", 36),
            Detail = string.format("put %d CD%s in the player \u{B7} %d/%d",
                math.max(1, math.floor(tonumber(payload.Count) or 1)),
                math.floor(tonumber(payload.Count) or 1) == 1 and "" or "s",
                math.min(progress, goal), goal), Key = "level3:insert"})
        toastUntil = os.clock() + 2.3
    elseif kind == "CDDropped" then
        showToast("A carried CD was dropped", "Recover it at the player's last position", "", 2.4)
    elseif kind == "CDTransferred" and payload.RecipientUserId == player.UserId then
        showToast("A team CD is now on your back", "Take it to the CD player", "", 2.8)
    elseif kind == "ExitUnlocked" then
        showToast("All CDs are in the player", "Follow the compass to the revealed wall frame", "", 3)
    end
end
local clientEventConnection: RBXScriptConnection? = nil
local boundClientEvent: RemoteEvent? = nil
local function bindClientEvent()
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	local candidate = folder and folder:FindFirstChild(CLIENT_EVENT_NAME)
	local event = if candidate and candidate:IsA("RemoteEvent") then candidate else nil
	if event == boundClientEvent then return end
	if clientEventConnection then clientEventConnection:Disconnect() end
	clientEventConnection = nil
	boundClientEvent = event
	if event then clientEventConnection = event.OnClientEvent:Connect(handleClientEvent) end
end

trackReaderConnection(ReplicatedStorage.ChildAdded:Connect(bindClientEvent))
trackReaderConnection(ReplicatedStorage.ChildRemoved:Connect(bindClientEvent))
bindClientEvent()
-- L3_CD_READER_TARGET_20260921.
--
-- The reader points at the nearest disc a player can still PICK UP and says
-- whether one of them shares the room. Both answers come from server state
-- (Level3_CD<n>State/Room/Position on the Level 3 State folder, and
-- Level3_Room on the subject Player), never from the workspace: the CD model
-- streams out at range and a disc dropped across the mall may never have
-- replicated here at all. A CARRIED or INSERTED disc publishes no position, so
-- it cannot be pointed at.
--
-- The selection itself is this pure function over plain numbers -- no
-- instances, no Vector3 -- so tools/tests/test_level3_first_cd.py runs the very
-- code the client runs. Same-room is decided by ROOM ID, so a disc one wall
-- away in the adjacent room never lights the indicator however close it is.
local function chooseCDTarget(beacons: {any}, fromX: number, fromZ: number,
	subjectRoom: string): (any, number, boolean)
	local nearest, nearestDistance = nil, math.huge
	local sameRoom = false
	for _, beacon in ipairs(beacons) do
		local dx, dz = beacon.X - fromX, beacon.Z - fromZ
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance < nearestDistance then
			nearest = beacon
			nearestDistance = distance
		end
		if subjectRoom ~= "" and beacon.Room == subjectRoom then sameRoom = true end
	end
	return nearest, nearestDistance, sameRoom
end

local cdBeaconBuffer: {any} = {}
local cdBeaconPool: {any} = {}
local cdStateBuffer: {any} = {}
local cdStateKeys: {string}, cdPositionKeys: {string}, cdRoomKeys: {string} = {}, {}, {}
for index = 1, 12 do
	cdBeaconPool[index] = {Index=index, X=0, Y=0, Z=0, Room=""}
	cdStateKeys[index] = string.format("Level3_CD%dState", index)
	cdPositionKeys[index] = string.format("Level3_CD%dPosition", index)
	cdRoomKeys[index] = string.format("Level3_CD%dRoom", index)
end
local function pickableCDs(goal: number): {any}
	table.clear(cdBeaconBuffer)
	for index = 1, goal do
		local state = stateAttribute(cdStateKeys[index], nil)
		cdStateBuffer[index] = state
		local position = stateAttribute(cdPositionKeys[index], nil)
		if (state == "WORLD" or state == "DROPPED") and typeof(position) == "Vector3" then
			local room = stateAttribute(cdRoomKeys[index], nil)
			local beacon = cdBeaconPool[index]
			beacon.X, beacon.Y, beacon.Z = position.X, position.Y, position.Z
			beacon.Room = if type(room) == "string" then room else ""
			table.insert(cdBeaconBuffer, beacon)
		end
	end
	return cdBeaconBuffer
end
-- L3_CD_READER_TARGET_END_20260921

-- L3_CD_PLAYER_GUIDANCE_PURE_BEGIN
local function readerTargetMode(states: {any}, goal: number, inserted: number, unlocked: boolean): string
	if unlocked or inserted >= goal then return "EXIT" end
	local insertedStates = 0
	for index = 1, goal do
		local state = states[index]
		if state == "INSERTED" then insertedStates += 1
		elseif state ~= "CARRIED" then return "SCAN" end
	end
	return if insertedStates == goal then "EXIT" else "PLAYER"
end
local function precisePlanarBearing(fx: number, fz: number, dx: number, dz: number): number
	if fx*fx + fz*fz < .000001 or dx*dx + dz*dz < .000001 then return 0 end
	return math.atan2(fx*dz - fz*dx, fx*dx + fz*dz)
end
local function precisePlanarHeading(fx: number, fz: number, rx: number, rz: number,
	fallbackX: number, fallbackZ: number): (number, number)
	if fx*fx + fz*fz >= .000001 then return fx, fz end
	-- yAxis cross RightVector retains the camera's yaw when pitched straight
	-- up/down; character body yaw may point somewhere else in first person.
	if rx*rx + rz*rz >= .000001 then return rz, -rx end
	return fallbackX, fallbackZ
end
local function projectGuidePoint(x: number, y: number, depth: number, bearing: number,
	minX: number, minY: number, maxX: number, maxY: number): (number, number, number, boolean)
	if depth > 0 and x >= minX and x <= maxX and y >= minY and y <= maxY then
		return x, y, 0, true
	end
	local cx, cy = (minX+maxX)*.5, (minY+maxY)*.5
	local dx, dy = x-cx, y-cy
	-- Negative projection depth mirrors screen coordinates: use the full-circle
	-- camera bearing instead, so a player behind never masquerades as ahead.
	if depth <= 0 then dx, dy = math.sin(bearing), -math.cos(bearing) end
	if math.abs(dx)+math.abs(dy) < .000001 then dx, dy = 0, -1 end
	local sx = if math.abs(dx) > .000001 then (maxX-minX)*.5/math.abs(dx) else math.huge
	local sy = if math.abs(dy) > .000001 then (maxY-minY)*.5/math.abs(dy) else math.huge
	local scale = math.min(sx, sy)
	return cx+dx*scale, cy+dy*scale, math.deg(math.atan2(dx, -dy)), false
end
-- L3_CD_PLAYER_GUIDANCE_PURE_END

local function setPlayerGuide(enabled: boolean, target: Vector3?, root: BasePart?)
    guidePlayerMode, guideTarget, guideRoot = enabled, target, root
    if not enabled or not target or not root then playerGuide.Visible = false end
end
local function updatePlayerGuideGeometry()
	local root, target = guideRoot, guideTarget
	if not guidePlayerMode or not root or not root.Parent or not target
		or not isActive() then
		playerGuide.Visible = false
		return
	end
	local camera = workspace.CurrentCamera
	local forward = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	local fx, fz = forward.X, forward.Z
	if fx*fx + fz*fz < .000001 then
		local right = if camera then camera.CFrame.RightVector else root.CFrame.RightVector
		local fallback = root.CFrame.LookVector
		fx, fz = precisePlanarHeading(fx, fz, right.X, right.Z, fallback.X, fallback.Z)
	end
	local position = root.Position
	local dx, dy, dz = target.X-position.X, target.Y-position.Y, target.Z-position.Z
	guideBearing = precisePlanarBearing(fx, fz, dx, dz)
	guideDistance = math.sqrt(dx*dx + dy*dy + dz*dz)
	if not camera or not guideProjectionFits then playerGuide.Visible = false; return end
	-- UIDevice safe rectangles and GuiObject.AbsolutePosition share screen-GUI
	-- coordinates. Viewport projection omits the topbar conversion (58px in the
	-- measured desktop run); LocalOffset only removes this GUI's own origin.
	local projected = camera:WorldToScreenPoint(target)
	local x, y, rotation, onPoint = projectGuidePoint(projected.X, projected.Y, projected.Z,
		guideBearing, guideMinX, guideMinY, guideMaxX, guideMaxY)
	playerGuide.Position = UDim2.fromOffset(math.floor(x+guideOffsetX), math.floor(y+guideOffsetY))
	guideArrow.Rotation = rotation
	-- These two interned literals do not build strings/tables each frame.
	guideArrow.Text = if onPoint then "\u{25C6}" else "\u{25B2}"
	playerGuide.Visible = true
end

local function updatePlayerGuideReadout()
    local metres = guideDistance / 3.571
    guideLabel.Text = "CD PLAYER\n" .. (if metres < 10 then string.format("%.1fm", metres) else string.format("%dm", math.floor(metres+.5)))
end
local function updateReader(_dt: number)
    if not isActive() then setPlayerGuide(false, nil, nil); return end
    local goal = math.clamp(math.floor(numberAttribute("Level3_ModuleGoal", "Level3ModuleGoal", 5)), 1, 12)
    local progress = math.clamp(math.floor(numberAttribute("Level3_ModuleProgress", "Level3Modules", 0)), 0, goal)
    local subject = readerSubject()
    local root = subject.Character and subject.Character:FindFirstChild("HumanoidRootPart")
    local beacons = pickableCDs(goal)
    local unlocked = stateAttribute("Level3_ExitUnlocked", "Level3ExitUnlocked") == true
    local mode = readerTargetMode(cdStateBuffer, goal, progress, unlocked)
    local state: any = {Level = LEVEL, Title = "FIND THE CDS", Count = progress, Goal = goal,
        Tag = "CDS IN THE PLAYER", Lines = {"Follow the compass to the next CD."},
        Compass = {State = "locating"}, Done = progress >= goal}
    if mode == "PLAYER" then
        local target = cdPlayerPosition()
        state.Title, state.Lines = "INSERT THE CDS", {"Take the carried CDs to the CD player."}
        state.Compass = {State = target and "locked" or "locating", Target = target}
        setPlayerGuide(true, target, if root and root:IsA("BasePart") then root else nil)
        applyLayout()
        updatePlayerGuideGeometry()
        updatePlayerGuideReadout()
    elseif mode == "EXIT" then
        setPlayerGuide(false, nil, nil)
        state.Title, state.Lines = "GET OUT", {"Reach the revealed wall frame."}
        state.Compass = {State = unlocked and "locked" or "calibrating", Target = exitPosition()}
    else
        setPlayerGuide(false, nil, nil)
        local room = subject:GetAttribute("Level3_Room")
        if root and root:IsA("BasePart") then
            local cd, _distance, sameRoom = chooseCDTarget(beacons, root.Position.X, root.Position.Z,
                if type(room) == "string" then room else "")
            if cd then state.Compass = {State = sameRoom and "inRoom" or "locked", Target = Vector3.new(cd.X, cd.Y, cd.Z)} end
        end
    end
    RoundHud.SetObjective(state)
end
local READER_STATE_ATTRIBUTES = {
	"InRound", "Escaped", "ZyntraDispatchClientActive", "Level3_Hiding",
	-- A spectate target change swaps whose reader this is, so it takes the panel
	-- off the 0.10s tick and onto the same immediate path as the states above.
	"Spectating", "SpectateTargetUserId",
}
-- Read by isActive() and updateReader only under RunService:IsStudio(), so they
-- are only subscribed there. In a live game these attributes are never written
-- and a subscription to them would be a connection that can never fire.
local READER_STUDIO_ATTRIBUTES = {
	"UIRegressionForceLevel3Reader",
}

local readerSignalsBound = false
local function bindReaderStateSignals()
	-- Idempotent by a flag, not by hope: call this twice and the second call
	-- returns, so nothing is ever connected to a second time. Without it a
	-- re-entry would double every write and leave a second set of connections
	-- that teardown would then have to disconnect twice.
	if readerSignalsBound or not readerAlive then return end
	readerSignalsBound = true
	local function respond()
		if not readerAlive then return end
		updateReader(0)
	end
	trackReaderConnection(
		workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(respond))
	for _, attribute in ipairs(READER_STATE_ATTRIBUTES) do
		trackReaderConnection(
			player:GetAttributeChangedSignal(attribute):Connect(respond))
	end
	if RunService:IsStudio() then
		for _, attribute in ipairs(READER_STUDIO_ATTRIBUTES) do
			trackReaderConnection(
				player:GetAttributeChangedSignal(attribute):Connect(respond))
		end
	end
	-- UIDevice.OnScreenOwningModalChanged connects internally and returns
	-- NOTHING, so there is no handle here to track or to disconnect. That is the
	-- reason `respond` carries its own readerAlive guard above rather than
	-- leaning on the tracker: after teardown this one callback still fires, and
	-- the guard is what makes it do nothing instead of writing onto a destroyed
	-- panel. It is the single subscription in this file that outlives the reader,
	-- and it is inert.
	UIDevice.OnScreenOwningModalChanged(respond)
end

bindReaderStateSignals()

local accumulated = 0
trackReaderConnection(RunService.RenderStepped:Connect(function(dt)
    if not readerAlive then return end
    updatePlayerGuideGeometry()
    accumulated += dt
    if accumulated < UPDATE_INTERVAL then return end
    local elapsed = accumulated
    accumulated = 0
    bindClientEvent()
    updateReader(elapsed)
end))
-- CD_HINT_20261008 (owner: "a message and an arrow that points at the reader, with how to find the CDs; shown for
-- a short while"). Once per round, when the reader is first up and nothing has been collected yet: a small card
-- beside the panel (under it where there is no room beside it) whose arrows run toward the panel. It goes after
-- ten seconds, or the moment a CD is picked up, the reader is put away, a toast or anything else takes the screen.
-- Nothing flashes: the arrows drift a few pixels and come back.
do
	local HINT_SECONDS = 10
	local hint = Instance.new("Frame")
	hint.Name = "ReaderHint"
	hint.Visible = false
	hint.Parent = gui
	UIStyle.panel(hint)
	local hintStroke = hint:FindFirstChildOfClass("UIStroke")
	if hintStroke then hintStroke.Color = ENERGON end
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	UIStyle.readout(arrow, {TextColor = ENERGON, TextSize = 22})
	arrow.Parent = hint
	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.BackgroundTransparency = 1
	UIStyle.readout(heading, {TextColor = ENERGON, TextSize = 15})
	heading.Text = "FIND THE CDS"
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Parent = hint
	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	UIStyle.body(body, {TextColor = TEXT, TextSize = 13})
	body.Text = "The compass points to the nearest CD. Turn until the mark is in the middle, then walk."
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Parent = hint

	-- One world at a time, held strongly: a weak table keyed on the Model can lose its entry while the Model lives
	-- (nothing else in this script keeps a Lua reference to it), and the card would come back mid-round.
	local hintWorld: Model? = nil
	local hintSeconds = 0
	local function wanted(): Model?
		local world = currentWorld()
		if world ~= hintWorld then hintWorld, hintSeconds = world, 0 end
		if not world or hintSeconds >= HINT_SECONDS then return nil end
		if not (objectiveCard() and objectiveCard().Visible) or os.clock() < toastUntil or not isActive() or spectateSubject() ~= nil then return nil end
		if player:GetAttribute("LevelLoadingOpen") == true then return nil end
		local hud = player.PlayerGui:FindFirstChild("RoundHud")
		local feed = hud and hud:FindFirstChild("FeedRow1")
		if feed and feed:IsA("GuiObject") and feed.Visible then return nil end
		-- not under UIRegression's viewport fixture (its matrices measure the reader alone); `DevReaderHintInFixture`
		-- on the workspace lets a phone audit see the card anyway
		if workspace:GetAttribute("UIRegressionViewport") ~= nil and workspace:GetAttribute("DevReaderHintInFixture") ~= true then return nil end
		if stateAttribute("Level3_ExitUnlocked", "Level3ExitUnlocked") == true
			or numberAttribute("Level3_ModuleProgress", "Level3Modules", 0) > 0 then
			hintSeconds = HINT_SECONDS                                    -- they have found one: nothing left to say
			return nil
		end
		return world
	end
	local function place(seconds: number)
		local panel = objectiveCard()
		if not panel then return end
		local origin = gui.AbsolutePosition
		local size = panel.AbsoluteSize
		local right, top = panel.AbsolutePosition.X + size.X - origin.X, panel.AbsolutePosition.Y - origin.Y
		local drift = math.floor(3 + 3 * math.sin(seconds * 3.2))
		-- MOBILE_QA_20261008: the room beside the reader is measured to the LOBBY chip's real right edge (it is at
		-- 188, not the 150 this assumed), and a phone that has less than the card's 300 gets a narrower, taller card
		-- beside the reader instead of one under it: under it is where a phone's buttons are (667x375). With no room
		-- beside either (568x320) it stands under the chip, on the thumbstick's side; the card takes no input.
		local chip = player.PlayerGui:FindFirstChild("RoundExitGui")
		chip = chip and chip.Enabled and chip:FindFirstChild("LeaveChip")
		local chipRight = (chip and chip.Visible) and (chip.AbsolutePosition.X + chip.AbsoluteSize.X - gui.AbsolutePosition.X) or 0
		local room = right - size.X - 12 - (chipRight + 12)
		local touch = UIDevice.IsTouch()
		local beside = room >= 300 or (touch and room >= 170)
		if not beside and touch and chip and chip.Visible then
			local origin = gui.AbsolutePosition
			hint.AnchorPoint = Vector2.new(0, 0)
			hint.Position = UDim2.fromOffset(chip.AbsolutePosition.X - origin.X, chip.AbsolutePosition.Y + chip.AbsoluteSize.Y + 8 - origin.Y)
			hint.Size = UDim2.fromOffset(220, 122)
			arrow.Text = ">>"
			arrow.AnchorPoint = Vector2.new(1, 0.5)
			arrow.Position = UDim2.new(1, -8 + drift, 0.5, 0)
			arrow.Size = UDim2.fromOffset(34, 28)
			heading.Position, heading.Size = UDim2.fromOffset(12, 8), UDim2.new(1, -62, 0, 18)
			body.Position, body.Size = UDim2.fromOffset(12, 30), UDim2.new(1, -62, 1, -36)
		elseif beside then
			local width = math.min(300, room)
			hint.AnchorPoint = Vector2.new(1, 0)
			hint.Position = UDim2.fromOffset(right - size.X - 12, top)
			hint.Size = UDim2.fromOffset(width, math.max(74, size.Y, width < 300 and 150 or 0))
			arrow.Text = ">>"
			arrow.AnchorPoint = Vector2.new(1, 0.5)
			arrow.Position = UDim2.new(1, -8 + drift, 0.5, 0)
			arrow.Size = UDim2.fromOffset(34, 28)
			heading.Position, heading.Size = UDim2.fromOffset(12, 8), UDim2.new(1, -62, 0, 18)
			body.Position, body.Size = UDim2.fromOffset(12, 30), UDim2.new(1, -62, 1, -36)
		else
			local width = math.max(200, size.X)
			hint.AnchorPoint = Vector2.new(1, 0)
			hint.Position = UDim2.fromOffset(right, top + size.Y + 10)
			hint.Size = UDim2.fromOffset(width, 96)
			arrow.Text = "^ ^"
			arrow.AnchorPoint = Vector2.new(0.5, 0)
			arrow.Position = UDim2.new(0.5, 0, 0, 2 - drift)
			arrow.Size = UDim2.fromOffset(60, 22)
			heading.Position, heading.Size = UDim2.fromOffset(12, 24), UDim2.new(1, -24, 0, 18)
			body.Position, body.Size = UDim2.fromOffset(12, 44), UDim2.new(1, -24, 1, -50)
		end
	end
	trackReaderConnection(RunService.RenderStepped:Connect(function(dt)
		local world = wanted()
		if not world then
			if hint.Visible then hint.Visible = false end
			return
		end
		hintSeconds += dt
		local seconds = hintSeconds
		place(seconds)
		if not hint.Visible then hint.Visible = true end
		script:SetAttribute("Level3_ReaderHintSeconds", math.floor(seconds * 10) / 10)
	end))
end
-- C_READER_TEARDOWN_20260831.
--
-- One teardown, idempotent, that every exit path funnels into. The triggers are
-- the three ways this reader can actually stop existing: the LocalScript being
-- destroyed, the ScreenGui being destroyed, and the gui being pulled out of the
-- tree WITHOUT being destroyed (PlayerGui cleared, gui reparented). The last
-- one is checked as `not gui:IsDescendantOf(game)` rather than
-- `gui.Parent == nil`, because a reparent into a detached folder leaves Parent
-- non-nil and the reader just as dead.
--
-- The three trigger connections are deliberately NOT tracked. Each is made on
-- an instance that is being destroyed or detached at the moment it fires, so
-- none can outlive what it watches; tracking them would only mean disconnecting
-- a connection from inside its own handler.
local function teardownReader()
	if not readerAlive then return end
	readerAlive = false
	playerGuide.Visible = false
	guidePlayerMode, guideTarget, guideRoot = false, nil, nil
	cachedPlayerWorld, cachedPlayerControl = nil, nil
	for _, connection in ipairs(readerConnections) do
		if connection.Connected then connection:Disconnect() end
	end
	table.clear(readerConnections)
	-- The two rebinding connections, by name, for the reason given in
	-- C_READER_CONNECTION_TRACKING_20260831.
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	if clientEventConnection then
		clientEventConnection:Disconnect()
		clientEventConnection = nil
	end
	boundClientEvent = nil
	-- The R / ButtonY binding is not an RBXScriptConnection and so was never in
	-- the list. ContextActionService holds it against the action NAME until that
	-- name is unbound, which outlives the gui on its own.
	pcall(function()
		ContextActionService:UnbindAction("Level3ToggleExitReader")
	end)
end

script.Destroying:Connect(teardownReader)
gui.Destroying:Connect(teardownReader)
gui.AncestryChanged:Connect(function()
	if not gui:IsDescendantOf(game) then teardownReader() end
end)
