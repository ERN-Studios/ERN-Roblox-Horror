from pathlib import Path
import difflib, hashlib, json

out = Path('tools/level3_finale_player_20261002/reader')
meta = json.loads((out/'fresh-baseline-metadata.json').read_text())
source = (out/'Reader.fresh.baseline.luau').read_text()
assert hashlib.sha256(source.encode()).hexdigest() == meta['sourceHash'] == meta['editorHash']
assert meta['editorMatch'] and meta['class'] == 'LocalScript'

def replace(old, new):
    global source
    assert source.count(old) == 1, old[:100]
    source = source.replace(old, new, 1)

ui = '''
-- A precise full-circle compass and a scene pin share the reader's existing
-- visibility/input gates. They are presentation only, never insert controls.
local playerCompassArrow = Instance.new("TextLabel")
playerCompassArrow.Name = "CDPlayerCompassArrow"
playerCompassArrow.BackgroundTransparency = 1
playerCompassArrow.AnchorPoint = Vector2.new(.5, .5)
playerCompassArrow.Position = UDim2.fromScale(.10, .5)
playerCompassArrow.Size = UDim2.fromOffset(18, 18)
UIStyle.readout(playerCompassArrow, {TextColor=ENERGON, TextSize=18})
playerCompassArrow.Text = "▲"
playerCompassArrow.Visible = false
playerCompassArrow.Parent = track
local playerCompassLabel = Instance.new("TextLabel")
playerCompassLabel.Name = "CDPlayerBearing"
playerCompassLabel.BackgroundTransparency = 1
playerCompassLabel.Position = UDim2.fromScale(.22, 0)
playerCompassLabel.Size = UDim2.fromScale(.75, 1)
UIStyle.readout(playerCompassLabel, {TextColor=ENERGON, TextSize=12})
playerCompassLabel.TextXAlignment = Enum.TextXAlignment.Left
playerCompassLabel.TextTruncate = Enum.TextTruncate.AtEnd
playerCompassLabel.Visible = false
playerCompassLabel.Parent = track

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
guideArrow.Text = "◆"
guideArrow.Parent = playerGuide
local guideLabel = Instance.new("TextLabel")
guideLabel.Name = "Label"
guideLabel.Position = UDim2.fromOffset(0, 14)
guideLabel.Size = UDim2.new(1, 0, 0, 32)
guideLabel.BackgroundColor3 = PANEL
guideLabel.BackgroundTransparency = .12
guideLabel.BorderSizePixel = 0
UIStyle.readout(guideLabel, {TextColor=ENERGON, TextSize=11})
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
'''
replace('signalLabel.Parent = panel\n', 'signalLabel.Parent = panel\n' + ui)

layout = '''
	-- Cache viewport/safe-area conversion here, not in the RenderStepped path.
	guideOffsetX, guideOffsetY = UIDevice.LocalOffset(gui, 0, 0)
	local guideWidth = math.clamp(layoutInfo.Safe.Width - 32, 100, 136)
	playerGuide.Size = UDim2.fromOffset(guideWidth, 50)
	guideMinX = layoutInfo.Safe.Left + guideWidth * .5 + 8
	guideMaxX = layoutInfo.Safe.Right - guideWidth * .5 - 8
	guideMinY = layoutInfo.Safe.Top + panelHeight + 24
	guideMaxY = layoutInfo.Safe.Bottom - 90
	guideProjectionFits = guideMaxX >= guideMinX and guideMaxY >= guideMinY
	if UIDevice.IsTouch() then
		local zones = layoutInfo.Zones
		local controlsTop = if zones and zones.Controls then zones.Controls.Top else math.huge
		local thumbstickTop = if zones and zones.Thumbstick then zones.Thumbstick.Top else math.huge
		local jumpTop = if zones and zones.Jump then zones.Jump.Top else math.huge
		local ceiling, clearHeight = guideMovementCeiling(guideMaxY, guideMinY,
			controlsTop, thumbstickTop, jumpTop)
		guideMaxY = ceiling
		guideProjectionFits = guideProjectionFits and clearHeight
	end
	guideMaxX = math.max(guideMinX + 1, guideMaxX)
	guideMaxY = math.max(guideMinY + 1, guideMaxY)
	-- Short screens retain the exact in-panel compass and distance when a scene
	-- card cannot fit without covering movement controls or the reader itself.
	if not guideProjectionFits then playerGuide.Visible = false end
	playerCompassArrow.Size = UDim2.fromOffset(compactLandscape and 10 or 18, compactLandscape and 10 or 18)
	playerCompassArrow.TextSize = compactLandscape and 10 or 18
	playerCompassLabel.TextSize = compactLandscape and 9 or (narrow and 10 or 12)
	guideLabel.TextSize = narrow and 10 or 11
'''
replace('\t-- The toast carries two lines of authored copy', layout + '\n\t-- The toast carries two lines of authored copy')

target = '''
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
'''
replace('local function generationMatches(payload:', target + '\nlocal function generationMatches(payload:')

old = '''local function pickableCDs(goal: number): {any}
	local beacons = {}
	for index = 1, goal do
		local state = stateAttribute(string.format("Level3_CD%dState", index), nil)
		local position = stateAttribute(string.format("Level3_CD%dPosition", index), nil)
		if (state == "WORLD" or state == "DROPPED") and typeof(position) == "Vector3" then
			local room = stateAttribute(string.format("Level3_CD%dRoom", index), nil)
			table.insert(beacons, {
				Index = index,
				X = position.X,
				Z = position.Z,
				Room = if type(room) == "string" then room else "",
			})
		end
	end
	return beacons
end'''
new = '''local cdBeaconBuffer: {any} = {}
local cdBeaconPool: {any} = {}
local cdStateBuffer: {any} = {}
local cdStateKeys: {string}, cdPositionKeys: {string}, cdRoomKeys: {string} = {}, {}, {}
for index = 1, 12 do
	cdBeaconPool[index] = {Index=index, X=0, Z=0, Room=""}
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
			beacon.X, beacon.Z = position.X, position.Z
			beacon.Room = if type(room) == "string" then room else ""
			table.insert(cdBeaconBuffer, beacon)
		end
	end
	return cdBeaconBuffer
end'''
replace(old, new)

geometry = '''
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
	needle.Visible, centerLine.Visible = not enabled, not enabled
	playerCompassArrow.Visible = enabled and target ~= nil
	playerCompassLabel.Visible = enabled and target ~= nil
	if not enabled or not target or not root then playerGuide.Visible = false end
end
local function updatePlayerGuideGeometry()
	local root, target = guideRoot, guideTarget
	if not guidePlayerMode or not root or not root.Parent or not target
		or not panel.Visible or not isActive() then
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
	playerCompassArrow.Rotation = math.deg(guideBearing)
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
	guideArrow.Text = if onPoint then "◆" else "▲"
	playerGuide.Visible = true
end
local function updatePlayerGuideReadout()
	local degrees = math.floor(math.abs(math.deg(guideBearing))+.5)
	playerCompassLabel.Text = if degrees <= 8 then "AHEAD"
		elseif degrees >= 150 then string.format("BEHIND  %d°", degrees)
		else string.format("%s  %d°", guideBearing < 0 and "LEFT" or "RIGHT", degrees)
	local metres = guideDistance / 3.571
	local distanceText = if metres < 10 then string.format("%.1fm", metres)
		else string.format("%dm", math.floor(metres+.5))
	signalLabel.Text = "CD PLAYER  " .. distanceText
	guideLabel.Text = "CD PLAYER\\n" .. distanceText
end
'''
replace('local function updateReader(dt: number)', geometry + '\nlocal function updateReader(dt: number)')
replace('''	UIDevice.SetInteractive(restoreButton, false)
	local hold = math.clamp''', '''	UIDevice.SetInteractive(restoreButton, false)
	playerGuide.Visible = false
	local hold = math.clamp''')
replace('''	if not active then
		toastSerial += 1''', '''	if not active then
		setPlayerGuide(false, nil, nil)
		toastSerial += 1''')
replace('''	if not (root and root:IsA("BasePart")) then
		signalLabel.Text = "SIGNAL // NO TRACE"''', '''	if not (root and root:IsA("BasePart")) then
		setPlayerGuide(false, nil, nil)
		signalLabel.Text = "SIGNAL // NO TRACE"''')
replace('''	-- A remaining disc outranks the exit. Once every CD has been collected the
	-- panel hands the needle straight back to the exit bearing it always had,
	-- and the DISC RELAY row above keeps saying how many still owe the VCR.
	local beacons = pickableCDs(goal)''', '''	-- Current states are authoritative: collected-ever progress does not fall
	-- on a drop, and a missing streamed beacon is not proof that a CD is held.
	local beacons = pickableCDs(goal)
	local mode = readerTargetMode(cdStateBuffer, goal, progress,
		stateAttribute("Level3_ExitUnlocked", "Level3ExitUnlocked") == true)
	if mode == "PLAYER" then
		title.Text = "> CD PLAYER"
		progressLabel.Text = string.format("INSERT CDS  %d/%d", progress, goal)
		local target = cdPlayerPosition()
		setPlayerGuide(true, target, root)
		signalLabel.TextColor3, signalLabel.TextTransparency = ENERGON, 0
		panelStroke.Color = ENERGON
		if target then
			updatePlayerGuideGeometry()
			updatePlayerGuideReadout()
		else signalLabel.Text = "CD PLAYER // LOCATING" end
		return
	end
	setPlayerGuide(false, nil, nil)''')
replace('''	local exit = exitPosition()
	if not cd and not exit then''', '''	if mode == "SCAN" and not cd then
		title.Text = "> CD READER"
		signalLabel.Text = "CD // LOCATING"
		signalLabel.TextColor3, signalLabel.TextTransparency = MUTED, 0
		needle.Position = UDim2.fromScale(.5, .5)
		return
	end
	-- Inserted/unlocked authority can replicate before the individual CD states.
	if mode == "EXIT" then cd = nil end
	local exit = exitPosition()
	if not cd and not exit then''')
replace('''trackReaderConnection(RunService.RenderStepped:Connect(function(dt)
	accumulated += dt''', '''trackReaderConnection(RunService.RenderStepped:Connect(function(dt)
	if not readerAlive then return end
	-- Smooth exact camera geometry every frame; target/state/text refresh remains
	-- on the existing 10Hz tick. No tables, scans, subscriptions or formatting here.
	updatePlayerGuideGeometry()
	accumulated += dt''')
replace('''	readerAlive = false
	for _, connection in ipairs(readerConnections) do''', '''	readerAlive = false
	playerGuide.Visible = false
	guidePlayerMode, guideTarget, guideRoot = false, nil, nil
	cachedPlayerWorld, cachedPlayerControl = nil, nil
	for _, connection in ipairs(readerConnections) do''')

candidate = out/'Reader.v4.candidate.luau'
candidate.write_text(source)
before = (out/'Reader.fresh.baseline.luau').read_text()
(out/'Reader.v4.diff').write_text(''.join(difflib.unified_diff(before.splitlines(True), source.splitlines(True), fromfile=meta['path']+' fresh Edit', tofile=meta['path']+' precise player guidance')))
manifest = dict(meta, operation='edit', baselinePath=str(out/'Reader.fresh.baseline.luau'), candidatePath=str(candidate), candidateHash=hashlib.sha256(source.encode()).hexdigest(), candidateBytes=len(source.encode()), targetContract={'state':'Level3_CDPlayerPosition','workspaceMirror':'Level3CDPlayerPosition','source':'actual post-Visual session.DiscPlayer.Position','cleanup':'both cleared by Objective'}, scope='Only public Level3 Reader Client; current-state secured mode, exact camera compass/projection, existing UI gates and teardown')
(out/'candidate-manifest.v4.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'candidateHash':manifest['candidateHash'],'candidateBytes':manifest['candidateBytes']}))
