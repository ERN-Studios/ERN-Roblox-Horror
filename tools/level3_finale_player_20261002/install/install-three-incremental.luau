-- Reviewed scoped Source delta installer; parent only, correct Studio Edit context.
-- No place restore, instance creation, external upload, or unrelated script writes.
local E, SES = game:GetService("EncodingService"), game:GetService("ScriptEditorService")
local R, H = game:GetService("RunService"), game:GetService("HttpService")
assert(not R:IsRunning(), "Edit only")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong place/universe")
local rows = {{path=([[_ServerScriptService.Level 3 Systems.Level 3 World Builder]]):sub(2),className=([[_ModuleScript]]):sub(2),baselineSHA256=([[_7ff641c16e65879663bf41771ecb547687c4634847ecacd64a87b76629ec6587]]):sub(2),editorSHA256=([[_7ff641c16e65879663bf41771ecb547687c4634847ecacd64a87b76629ec6587]]):sub(2),candidateSHA256=([[_7ff641c16e65879663bf41771ecb547687c4634847ecacd64a87b76629ec6587]]):sub(2),baselineBytes=108625,candidateBytes=108625,write=false,patches={}},
{path=([[_ServerScriptService.Level 3 Systems.Level 3 Worn Party Visual Adapter]]):sub(2),className=([[_ModuleScript]]):sub(2),baselineSHA256=([[_c53420d67edb315810450d420f0e1de739281bd4d753d8a69929695a66b6a568]]):sub(2),editorSHA256=([[_c53420d67edb315810450d420f0e1de739281bd4d753d8a69929695a66b6a568]]):sub(2),candidateSHA256=([[_6c16bd4ca1d6f32008c5f1f9acaeec3265908bd45531430beba9c456c53ca2ba]]):sub(2),baselineBytes=29939,candidateBytes=30263,write=true,patches={{before=([[_            label.Size = size
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.Code
            label.TextSize = fontSize
            label.TextColor3 = color
            label.TextXAlignment = Enum.TextXAlignment.Left
]]):sub(2),after=([[_            label.Size = size
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.Code
            label.FontFace = Font.new(label.FontFace.Family, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
            label.TextSize = fontSize
            label.TextColor3 = color
            label.TextXAlignment = Enum.TextXAlignment.Left
]]):sub(2)},{before=([[_        status.Size = UDim2.fromScale(.63,.26)
        status.TextScaled = false
        status.TextSize = 52
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.TextColor3 = Color3.fromRGB(103,247,177)
        status.TextStrokeTransparency = 1
]]):sub(2),after=([[_        status.Size = UDim2.fromScale(.63,.26)
        status.TextScaled = false
        status.TextSize = 52
        status.FontFace = Font.new(status.FontFace.Family, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.TextColor3 = Color3.fromRGB(103,247,177)
        status.TextStrokeTransparency = 1
]]):sub(2)},{before=([[_        instruction.Size = UDim2.fromScale(.92,.16)
        instruction.TextScaled = false
        instruction.TextSize = 40
        instruction.TextXAlignment = Enum.TextXAlignment.Left
        instruction.TextColor3 = Color3.fromRGB(161,198,166)
        instruction.TextStrokeTransparency = 1
]]):sub(2),after=([[_        instruction.Size = UDim2.fromScale(.92,.16)
        instruction.TextScaled = false
        instruction.TextSize = 40
        instruction.FontFace = Font.new(instruction.FontFace.Family, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
        instruction.TextXAlignment = Enum.TextXAlignment.Left
        instruction.TextColor3 = Color3.fromRGB(161,198,166)
        instruction.TextStrokeTransparency = 1
]]):sub(2)}}},
{path=([[_ServerScriptService.Level 3 Systems.Level 3 Objective Controller]]):sub(2),className=([[_ModuleScript]]):sub(2),baselineSHA256=([[_4271bc4890412385b496aebd626e33336e913fbf90bf9646d378ae62a31d8e38]]):sub(2),editorSHA256=([[_4271bc4890412385b496aebd626e33336e913fbf90bf9646d378ae62a31d8e38]]):sub(2),candidateSHA256=([[_4271bc4890412385b496aebd626e33336e913fbf90bf9646d378ae62a31d8e38]]):sub(2),baselineBytes=74217,candidateBytes=74217,write=false,patches={}},
{path=([[_ServerScriptService.Level 3 Systems.Level 3 Mall Manager AI Controller]]):sub(2),className=([[_ModuleScript]]):sub(2),baselineSHA256=([[_c78189234adcd884ef21371d5f4dfe0ebf7d54efbfc45c290f37a0e3ffeae490]]):sub(2),editorSHA256=([[_c78189234adcd884ef21371d5f4dfe0ebf7d54efbfc45c290f37a0e3ffeae490]]):sub(2),candidateSHA256=([[_74e0238d0c20cd381e60baf5f8567c0882f84dcb0b29bb52deb51039edc87599]]):sub(2),baselineBytes=189602,candidateBytes=189956,write=true,patches={{before=([[_	return bestMembers, anchor, centroid
end

local function spawnOverlapParams(records: {any}): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored = {}
	for _, record in ipairs(records) do table.insert(ignored, record.Character) end
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	params.MaxParts = 1
]]):sub(2),after=([[_	return bestMembers, anchor, centroid
end

local function spawnOverlapParams(records: {any}, ignoreAllAvatars: boolean?): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored = {}
	if ignoreAllAvatars then
		-- Match navigation's current-avatar exclusions: a retired round life
		-- cannot veto the fixed reveal with a body the Manager already walks through.
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then table.insert(ignored, player.Character) end
		end
	else
		for _, record in ipairs(records) do table.insert(ignored, record.Character) end
	end
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	params.MaxParts = 1
]]):sub(2)},{before=([[_	end
	-- Exactly the authored far endpoint; never move the reveal toward a player.
	local position = Vector3.new(hall.EndPoint.X, hall.FloorY, hall.EndPoint.Z)
	if not spawnVolumeFits(position, spawnOverlapParams(records)) then return nil end
	-- Face a runner in the exit lane before the first authoritative chase tick.
	table.sort(records, function(a, b)
		local aInHall = insideFinalHall({Manifest=manifest}, a.Position)
]]):sub(2),after=([[_	end
	-- Exactly the authored far endpoint; never move the reveal toward a player.
	local position = Vector3.new(hall.EndPoint.X, hall.FloorY, hall.EndPoint.Z)
	if not spawnVolumeFits(position, spawnOverlapParams(records, true)) then return nil end
	-- Face a runner in the exit lane before the first authoritative chase tick.
	table.sort(records, function(a, b)
		local aInHall = insideFinalHall({Manifest=manifest}, a.Position)
]]):sub(2)}}},
{path=([[_StarterPlayer.StarterPlayerScripts.Level 3 Reader Client]]):sub(2),className=([[_LocalScript]]):sub(2),baselineSHA256=([[_b452be2e27d398c282ce8c2d26f3add7e78074a71a5d9799f086591a93c1fb9e]]):sub(2),editorSHA256=([[_b452be2e27d398c282ce8c2d26f3add7e78074a71a5d9799f086591a93c1fb9e]]):sub(2),candidateSHA256=([[_fb853734db1bde20c2c0e61a69ccb37a01b5780816ad48c875337ecb1a30f2d6]]):sub(2),baselineBytes=70098,candidateBytes=71506,write=true,patches={{before=([[_local guideBearing, guideDistance = 0, 0
local guideMinX, guideMinY, guideMaxX, guideMaxY = 0, 0, 1, 1
local guideOffsetX, guideOffsetY = 0, 0

-- C_READER_TOGGLE_REMOVED_20260830 -- WHAT SHIPPED BROKEN.
-- `ReaderToggle` was a permanently-visible 150x44 chip reading "CLOSE READER
]]):sub(2),after=([[_local guideBearing, guideDistance = 0, 0
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

-- C_READER_TOGGLE_REMOVED_20260830 -- WHAT SHIPPED BROKEN.
-- `ReaderToggle` was a permanently-visible 150x44 chip reading "CLOSE READER
]]):sub(2)},{before=([[_	guideMaxX = layoutInfo.Safe.Right - guideWidth * .5 - 8
	guideMinY = layoutInfo.Safe.Top + panelHeight + 24
	guideMaxY = layoutInfo.Safe.Bottom - 90
	if guideMaxY <= guideMinY then
		guideMinY = layoutInfo.Safe.Top + 24
		guideMaxY = math.max(guideMinY + 1, layoutInfo.Safe.Bottom - 56)
	end
	guideMaxX = math.max(guideMinX + 1, guideMaxX)
	playerCompassArrow.Size = UDim2.fromOffset(compactLandscape and 10 or 18, compactLandscape and 10 or 18)
	playerCompassArrow.TextSize = compactLandscape and 10 or 18
	playerCompassLabel.TextSize = compactLandscape and 9 or (narrow and 10 or 12)
]]):sub(2),after=([[_	guideMaxX = layoutInfo.Safe.Right - guideWidth * .5 - 8
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
]]):sub(2)},{before=([[_	guideBearing = precisePlanarBearing(fx, fz, dx, dz)
	guideDistance = math.sqrt(dx*dx + dy*dy + dz*dz)
	playerCompassArrow.Rotation = math.deg(guideBearing)
	if not camera then playerGuide.Visible = false; return end
	local projected = camera:WorldToViewportPoint(target)
	local x, y, rotation, onPoint = projectGuidePoint(projected.X, projected.Y, projected.Z,
		guideBearing, guideMinX, guideMinY, guideMaxX, guideMaxY)
	playerGuide.Position = UDim2.fromOffset(math.floor(x+guideOffsetX), math.floor(y+guideOffsetY))
]]):sub(2),after=([[_	guideBearing = precisePlanarBearing(fx, fz, dx, dz)
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
]]):sub(2)}}}}
assert(#rows == 5, "Unexpected scope")
local function hash(source)
    local digest = E:ComputeBufferHash(buffer.fromstring(source), Enum.HashAlgorithm.Sha256)
    local bytes = {}
    for index=0,buffer.len(digest)-1 do bytes[index+1]=string.format("%02x",buffer.readu8(digest,index)) end
    return table.concat(bytes)
end
local function at(path)
    local object = game
    for name in path:gmatch("[^.]+") do object=assert(object:FindFirstChild(name),"Missing path: "..path) end
    return object
end
local targets, parents, expected, prepared = {}, {}, {}, {}
for _,row in ipairs(rows) do
    assert(row.className == "ModuleScript" or row.className == "LocalScript", "Unexpected class")
    assert(row.baselineSHA256 == row.editorSHA256, "Unresolved captured editor conflict")
    targets[row.path] = at(row.path)
    parents[row.path] = targets[row.path].Parent
    expected[row.path] = row.baselineSHA256
end
local function verifyAll()
    assert(not R:IsRunning() and game.PlaceId == 131311258779917 and game.GameId == 10559217407,
        "Context changed")
    for _,row in ipairs(rows) do
        local object = at(row.path)
        assert(object == targets[row.path] and object.Parent == parents[row.path]
            and object.ClassName == row.className, "Instance/class/parent changed: "..row.path)
        assert(hash(object.Source) == expected[row.path]
            and hash(SES:GetEditorSource(object)) == expected[row.path],
            "Fresh Source/editor changed: "..row.path)
    end
end
verifyAll() -- All five are checked before any candidate preparation or mutation.
local prewrite = {}
for _,row in ipairs(rows) do
    local current = targets[row.path].Source
    assert(#current == row.baselineBytes, "Baseline byte mismatch")
    table.insert(prewrite,{path=row.path,className=targets[row.path].ClassName,
        sourceSHA256=hash(current),editorSHA256=hash(SES:GetEditorSource(targets[row.path])),
        bytes=#current,editorMatch=current==SES:GetEditorSource(targets[row.path])})
    for _,patch in ipairs(row.patches) do
        local first,last = current:find(patch.before,1,true)
        assert(first and not current:find(patch.before,last+1,true),"Nonunique exact patch: "..row.path)
        current = current:sub(1,first-1)..patch.after..current:sub(last+1)
    end
    assert(#current == row.candidateBytes and hash(current) == row.candidateSHA256,
        "Prepared candidate mismatch: "..row.path)
    local compiled,problem = loadstring(current,"="..row.path)
    assert(compiled, "Candidate compile failed: "..row.path..": "..tostring(problem))
    prepared[row.path] = current
end
verifyAll() -- Compile/preparation may yield; all baselines must still match.
for _,row in ipairs(rows) do
    if row.write then
    local object = targets[row.path]
    SES:UpdateSourceAsync(object,function(current)
        -- The whole set is rechecked, including already-written candidate hashes.
        verifyAll()
        assert(hash(current) == expected[row.path],"Callback baseline changed: "..row.path)
        return prepared[row.path]
    end)
    assert(object.Source == prepared[row.path] and SES:GetEditorSource(object) == prepared[row.path],
        "Post-write Source/editor conflict: "..row.path)
    expected[row.path] = row.candidateSHA256
    verifyAll()
    end
end
verifyAll()
local receipt = {task="level3-finale-player-20261002",installedAtUTC=DateTime.now():ToIsoDate(),
    placeId=game.PlaceId,universeId=game.GameId,sourceCount=#rows,writeCount=3,sceneChanged=false,
    nativeBeforeSHA256="bc32152e6fd668aab75108576c454ef84a3c914ec4e606f094e5599c5e34f378",
    prewrite=prewrite,sources={}}
for _,row in ipairs(rows) do
    local object = targets[row.path]
    assert(hash(object.Source)==row.candidateSHA256 and SES:GetEditorSource(object)==prepared[row.path],
        "Final Source/editor mismatch: "..row.path)
    table.insert(receipt.sources,{path=row.path,className=object.ClassName,
        sourceSHA256=hash(object.Source),editorSHA256=hash(SES:GetEditorSource(object)),
        candidateSHA256=row.candidateSHA256,bytes=#object.Source,editorMatch=true})
end
print("LEVEL3_FINALE_PLAYER_SCOPED_INSTALL_OK",H:JSONEncode(receipt))
return receipt
