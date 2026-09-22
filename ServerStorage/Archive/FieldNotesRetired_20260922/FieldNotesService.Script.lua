-- FieldNotesService -- one optional Field Note prop per round. (Trello #85/#88)
--
-- WHAT THIS IS. A round places at most ONE readable document somewhere along a
-- route the party can already walk. Holding the prompt logs the next unowned
-- note for that level into the player's permanent collection through
-- ServerStorage.ZyntraInventory. That is the whole feature: it spends nothing,
-- it grants no stat, it never gates an exit, and a round in which the prop
-- cannot be placed at all is a completely normal round.
--
-- WHY OPTIONAL IS LOAD-BEARING, not a disclaimer. Two of the three levels are
-- generated fresh from a seed every round, so there is no authored spot to put
-- anything and no guarantee that a spot which existed last round exists now.
-- Every failure path here therefore ends in "place nothing" rather than in a
-- retry loop. The Pool Slide is the cautionary tale: its failing spawn retried
-- forever and cost 78% of the server's frame budget for days before a
-- frame-time measurement found it. This file computes at most
-- MAX_PATH_CANDIDATES routes, once, in one spawned thread, and then stops
-- whatever the answer was.
--
-- HOW A SPOT IS CHOSEN.
--   1. Collect the level world's walkable-looking floor parts (see isFloor).
--   2. Shuffle them with a Random seeded off the ROUND's own layout seed, so a
--      pinned seed reproduces the same note position -- which is what makes a
--      placement bug reproducible at all.
--   3. Ask PathfindingService for a real route from the party's spawn pad to
--      the first MAX_PATH_CANDIDATES of them, and throw away everything that
--      does not answer Success. This is the only filter that can tell a
--      corridor from a sealed light well, and it is why a ceiling slab or a
--      walled-off recovery chamber cannot win.
--   4. Take the MEDIAN surviving route by length. Not the shortest (that is the
--      spawn pad the party is standing on) and not the longest (that is the
--      exit, and a collectible at the exit is a collectible nobody detours for).
--
-- WHAT IS DELIBERATELY NOT HERE. No per-player props, no respawn on pickup, no
-- second note if the first goes unread. The prop stays put for the whole round
-- and every participant may read it once, which is what makes it a shared
-- discovery rather than a race.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")

-- Names, not a config module. Each of these already appears as a literal in the
-- files that build them (MazeGenerator, both World Builders, both Round
-- Adapters); a fourth copy here is the project's existing convention and costs
-- less than a require that would drag a level's whole configuration into a
-- service that only needs one string.
local WORLD_ROOTS = {
	[1] = "Maze",
	[2] = "Level 2 Generated World",
	[3] = "Level 3 Generated World",
}

-- ElevatorSpawn FIRST. Both are compatibility markers parented to workspace by
-- all three builders, but on Level 2 MazeStart sits on the arrival deck at
-- `topY` while ElevatorSpawn is the pad the party actually lands on -- and the
-- route length that decides the placement has to be measured from where the
-- players are, not from the marker the choreography uses.
local START_MARKERS = {"ElevatorSpawn", "MazeStart"}

local MAX_PATH_CANDIDATES = 14 -- routes computed per round, hard ceiling
local MIN_FLOOR_SIZE = 4       -- studs, both horizontal axes
local START_CLEARANCE = 60     -- studs from the spawn pad; "not at spawn"
local FLOOR_LIFT = 0.1         -- studs above the floor top, so it never z-fights
local PROMPT_DISTANCE = 8      -- what the client's prompt enforces
local REACH_DISTANCE = 10      -- what the SERVER re-checks on Triggered
local TRIGGER_COOLDOWN = 2     -- seconds per player

local BOARD_SIZE = Vector3.new(2.4, 3, 0.16)
local BASE_SIZE = Vector3.new(2.8, 0.2, 1)

-- The collection's text. Required here for ONE reason: to answer "does this
-- level have notes at all" before any of the expensive work starts, and to make
-- the DiscoverNote reply unambiguous. With the module present, a `false` from
-- ZyntraInventory can only mean "this player already owns every note on this
-- level" -- the module-absent branch of that contract is unreachable, because
-- without the module this service never places a prop to trigger.
local okNotes, FieldNotes = pcall(function()
	return require(ReplicatedStorage:WaitForChild("ZyntraFieldNotes", 30))
end)
if not okNotes or type(FieldNotes) ~= "table" or type(FieldNotes.ByLevel) ~= "table" then
	warn("[FieldNotes] ZyntraFieldNotes is missing; no notes will be placed this session")
	FieldNotes = nil
end

local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))

local function ensureChild(parent, name, className)
	local found = parent:FindFirstChild(name)
	if found and not found:IsA(className) then
		found:Destroy()
		found = nil
	end
	if not found then
		found = Instance.new(className)
		found.Name = name
		found.Parent = parent
	end
	return found
end

local remotes = ensureChild(ReplicatedStorage, "Remotes", "Folder")
local remote = ensureChild(remotes, "FieldNote", "RemoteEvent")
local folder = ensureChild(workspace, "FieldNotes", "Folder")

-- ── round state ─────────────────────────────────────────────────────────────
-- `generation` is the only thing that makes the yielding placement thread safe.
-- ComputeAsync yields, a round can end while it is yielding, and the answer
-- that comes back then belongs to a world that no longer exists.
local generation = 0
local placed = nil        -- the Model currently in the world, or nil
-- ONE ATTEMPT PER (ROUND, LEVEL), and this field is what enforces it. Without
-- it every later RoundLoadingState or SelectedLevel write would re-run the
-- whole candidate scan on a round where placement had already failed -- which
-- is the Pool Slide's retry-forever failure with a different name. A failed
-- attempt is a finished attempt.
local attemptedLevel = nil
local readers = {}        -- [userId] = noteId or true, this round only
local lastTrigger = {}    -- [userId] = os.clock() of the last accepted trigger

local function clearRound()
	generation += 1
	placed = nil
	attemptedLevel = nil
	readers = {}
	lastTrigger = {}
	folder:ClearAllChildren()
end

-- ── choosing a spot ─────────────────────────────────────────────────────────

-- "Could a player stand on the top of this and read a sign?" Everything here is
-- a cheap property read; the expensive reachability question is pathfinding's.
local function isFloor(part: BasePart): boolean
	if not part:IsA("BasePart") then return false end
	if not part.Anchored or not part.CanCollide then return false end
	if part.Size.X <= MIN_FLOOR_SIZE or part.Size.Z <= MIN_FLOOR_SIZE then return false end
	-- A wedge's "top" is a slope and a truss is a ladder. A Part that is not a
	-- Block is a ball or a cylinder, neither of which has a top face to stand a
	-- sign on. MeshParts stay eligible: Level 2's generated floors are MeshParts.
	local class = part.ClassName
	if class == "WedgePart" or class == "CornerWedgePart" or class == "TrussPart" then
		return false
	end
	if class == "Part" and (part :: any).Shape ~= Enum.PartType.Block then return false end
	-- Level 2's floors sit under wading-depth TERRAIN water, which is fine to
	-- stand a sign in; a part whose own material is Water is a pool surface and
	-- is not.
	if part.Material == Enum.Material.Water then return false end
	-- Tilted: a slide tub, a ramp, a diving board at an angle. The top face has
	-- to be level or the sign leans.
	if part.CFrame.UpVector.Y < 0.9 then return false end
	-- An invisible collidable slab with a floor's footprint is a barrier or a
	-- trigger volume, not somewhere a document would be left.
	if part.Transparency > 0.5 then return false end
	return true
end

-- The top-face CENTRE, always. A candidate is at least MIN_FLOOR_SIZE on both
-- horizontal axes, so its centre is at least MIN_FLOOR_SIZE/2 = 2 studs from
-- every edge -- comfortably past the 1.5-stud clearance the prop needs, without
-- a single line of edge arithmetic. It is also the point on a maze floor tile
-- furthest from the walls, which sit on the tile boundaries.
local function floorTop(part: BasePart): Vector3
	return part.Position + Vector3.new(0, part.Size.Y / 2, 0)
end

local function startPosition(): Vector3?
	for _, name in ipairs(START_MARKERS) do
		local marker = workspace:FindFirstChild(name)
		if marker and marker:IsA("BasePart") then return marker.Position end
	end
	return nil
end

-- The layout seed the round actually built with, so a pinned Level2Seed /
-- Level3Seed reproduces the same note position. Both builders publish it on the
-- world root itself. Level 1 publishes none, so it takes the clock and its
-- placement is reproducible only within a session -- which is honest: Level 1's
-- maze is not reproducible either.
local function roundSeed(world: Instance): number
	for _, name in ipairs({"Level2_Seed", "Level3_ResolvedSeed", "Level2_ResolvedSeed"}) do
		local value = world:GetAttribute(name)
		if type(value) == "number" and value == value and value > 0 then
			return math.floor(value) % 2147483647
		end
	end
	return math.floor(os.clock() * 1000) % 2147483647
end

local function pathLength(waypoints): number
	local total = 0
	for index = 2, #waypoints do
		total += (waypoints[index].Position - waypoints[index - 1].Position).Magnitude
	end
	return total
end

-- Fisher-Yates over the whole candidate list, driven by the round's own Random.
-- Shuffling and then taking a prefix -- rather than picking 14 indices -- keeps
-- the sample uniform over a list whose length changes with every seed.
local function sample(candidates, rng)
	for index = #candidates, 2, -1 do
		local swap = rng:NextInteger(1, index)
		candidates[index], candidates[swap] = candidates[swap], candidates[index]
	end
	local taken = {}
	for index = 1, math.min(MAX_PATH_CANDIDATES, #candidates) do
		taken[index] = candidates[index]
	end
	return taken
end

-- ── the prop ────────────────────────────────────────────────────────────────

local function buildProp(position: Vector3, yaw: number): (Model, ProximityPrompt)
	local model = Instance.new("Model")
	model.Name = "Field Note"

	local board = Instance.new("Part")
	board.Name = "Board"
	board.Size = BOARD_SIZE
	board.Anchored = true
	board.CanCollide = false -- it must never be something to trip over or shove
	board.CanTouch = false
	board.CanQuery = true    -- the prompt's own hit testing
	board.Material = Enum.Material.SmoothPlastic
	board.Color = UIStyle.Color.Card
	board.CFrame = CFrame.new(position + Vector3.new(0, FLOOR_LIFT + BOARD_SIZE.Y / 2, 0))
		* CFrame.Angles(0, yaw, 0)
	board.Parent = model
	model.PrimaryPart = board

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = BASE_SIZE
	base.Anchored = true
	base.CanCollide = false
	base.CanTouch = false
	base.CanQuery = false
	base.Material = Enum.Material.Metal
	base.Color = UIStyle.Color.Control
	base.CFrame = CFrame.new(position + Vector3.new(0, FLOOR_LIFT + BASE_SIZE.Y / 2, 0))
		* CFrame.Angles(0, yaw, 0)
	base.Parent = model

	-- BOTH FACES. The board's yaw is random -- there is no direction a generated
	-- level says a player will arrive from -- so a single-sided sign is blank
	-- from wherever half the party walks in. Two SurfaceGuis is the whole fix.
	--
	-- PixelsPerStud rather than TextScaled: TextScaled on a SurfaceGui never
	-- exceeds 100 px however large the surface is, so the only way to control
	-- how big the type reads in world space is to state the canvas density and
	-- then state the type size against it.
	for _, side in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
		local face = Instance.new("SurfaceGui")
		face.Name = "Face" .. side.Name
		face.Face = side
		face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		face.PixelsPerStud = 64
		face.LightInfluence = 0
		face.Brightness = 1.4
		face.Parent = board

		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.Size = UDim2.fromScale(1, 1)
		panel.Parent = face
		UIStyle.panel(panel, {
			Background = UIStyle.Color.Card,
			Transparency = UIStyle.Transparency.Card,
			Radius = UIStyle.Radius.Card,
			StrokeTransparency = UIStyle.Stroke.CardTransparency,
		})

		local eyebrow = Instance.new("TextLabel")
		eyebrow.Name = "Eyebrow"
		eyebrow.BackgroundTransparency = 1
		eyebrow.Position = UDim2.fromScale(0.08, 0.13)
		eyebrow.Size = UDim2.fromScale(0.84, 0.13)
		eyebrow.Text = "ZYNTRA // ARCHIVE"
		eyebrow.TextXAlignment = Enum.TextXAlignment.Center
		eyebrow.Parent = panel
		UIStyle.readout(eyebrow, {TextSize = 13})

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromScale(0.06, 0.32)
		title.Size = UDim2.fromScale(0.88, 0.34)
		title.Text = "FIELD\nNOTE"
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.Parent = panel
		UIStyle.title(title, {TextSize = 26})

		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.BorderSizePixel = 0
		rule.BackgroundColor3 = UIStyle.Color.Accent
		rule.BackgroundTransparency = 0.25
		rule.Position = UDim2.fromScale(0.3, 0.71)
		rule.Size = UDim2.fromScale(0.4, 0.012)
		rule.Parent = panel

		local stamp = Instance.new("TextLabel")
		stamp.Name = "Stamp"
		stamp.BackgroundTransparency = 1
		stamp.Position = UDim2.fromScale(0.06, 0.76)
		stamp.Size = UDim2.fromScale(0.88, 0.13)
		stamp.Text = "UNFILED DOCUMENT"
		stamp.TextXAlignment = Enum.TextXAlignment.Center
		stamp.Parent = panel
		UIStyle.readout(stamp, {TextSize = 11, TextColor = UIStyle.Color.Muted})
	end

	-- Enough to find it at the edge of a flashlight beam, not enough to light a
	-- corridor -- the levels are dark on purpose.
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = UIStyle.Color.Accent
	light.Brightness = 1.6
	light.Range = 14
	light.Shadows = false
	light.Parent = board

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Read"
	prompt.ActionText = "READ NOTE"
	prompt.ObjectText = "FIELD NOTE"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = board

	return model, prompt
end

-- ── reading it ──────────────────────────────────────────────────────────────

-- MaxActivationDistance, HoldDuration and RequiresLineOfSight are all enforced
-- by the CLIENT's prompt, so a Triggered signal proves nothing on its own. Same
-- shape as PuzzleManager's canUsePrompt and Level 2's canUsePump.
local function canRead(player: Player, prompt: ProximityPrompt, mine: number): boolean
	if mine ~= generation then return false end
	if workspace:GetAttribute("RoundActive") ~= true then return false end
	if player:GetAttribute("InRound") ~= true then return false end
	if not (prompt.Parent and prompt:IsDescendantOf(folder)) then return false end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and character.Parent and humanoid and humanoid.Health > 0 and root) then
		return false
	end
	local host = prompt.Parent :: BasePart
	return (root.Position - host.Position).Magnitude <= REACH_DISTANCE
end

local function onTriggered(player: Player, prompt: ProximityPrompt, mine: number, level: number)
	local userId = player.UserId
	local now = os.clock()
	local last = lastTrigger[userId]
	-- The window is CHECKED before validation and STAMPED only after it: a
	-- trigger that was refused (dead, out of reach, round over) must not lock
	-- out the legitimate one half a second later, and the refusal itself costs
	-- nothing but a handful of property reads.
	if last and now - last < TRIGGER_COOLDOWN then return end
	if not canRead(player, prompt, mine) then return end
	lastTrigger[userId] = now

	local already = readers[userId]
	if already then
		-- The prop is shared and stays put; a second read by the same player is
		-- not an error, it is just nothing new.
		remote:FireClient(player, "alreadyLogged", if type(already) == "string" then already else nil)
		return
	end

	local inventory = ServerStorage:FindFirstChild("ZyntraInventory")
	if not (inventory and inventory:IsA("BindableFunction")) then
		remote:FireClient(player, "unavailable")
		return
	end
	local ok, changed, noteId, message, status = pcall(function()
		return inventory:Invoke("DiscoverNote", player, level)
	end)
	if not ok then
		warn("[FieldNotes] DiscoverNote failed: " .. tostring(changed))
		remote:FireClient(player, "unavailable")
		return
	end

	if changed == true and type(noteId) == "string" and noteId ~= "" then
		readers[userId] = noteId
		remote:FireClient(player, "discovered", noteId)
	elseif status == "complete" then
		readers[userId] = true
		remote:FireClient(player, "alreadyLogged", nil)
	else
		-- A failed save must leave this player free to retry the same prop.
		remote:FireClient(player, "unavailable")
	end
end

-- ── placement ───────────────────────────────────────────────────────────────

local function place(mine: number, level: number)
	local world = workspace:FindFirstChild(WORLD_ROOTS[level])
	if not world then return end
	local origin = startPosition()
	if not origin then return end

	local candidates = {}
	for _, descendant in ipairs(world:GetDescendants()) do
		if isFloor(descendant)
			and (descendant.Position - origin).Magnitude >= START_CLEARANCE then
			table.insert(candidates, descendant)
		end
	end
	if #candidates == 0 then
		warn("[FieldNotes] no floor candidates on level " .. tostring(level) .. "; placed nothing")
		return
	end

	local rng = Random.new(roundSeed(world))
	local routed = {}
	for _, candidate in ipairs(sample(candidates, rng)) do
		-- Re-checked every iteration: ComputeAsync yields, and the round can end
		-- (or a second one begin) between any two of these.
		if mine ~= generation then return end
		local target = floorTop(candidate)
		local path = PathfindingService:CreatePath()
		local computed = pcall(function()
			path:ComputeAsync(origin, target)
		end)
		if computed and path.Status == Enum.PathStatus.Success then
			table.insert(routed, {Target = target, Length = pathLength(path:GetWaypoints())})
		end
	end
	if mine ~= generation then return end

	if #routed == 0 then
		-- The honest outcome, not a failure to retry. A generated maze can hand
		-- back a candidate set the pathfinder cannot route to; the note is
		-- optional precisely so this costs the round nothing.
		warn("[FieldNotes] nothing pathable on level " .. tostring(level) .. "; placed nothing")
		return
	end

	table.sort(routed, function(a, b) return a.Length < b.Length end)
	-- ceil, so a single success picks itself and an even count takes the lower
	-- of the two middles. Deterministic either way, which is the point.
	local chosen = routed[math.ceil(#routed / 2)]

	local model, prompt = buildProp(chosen.Target, rng:NextNumber() * math.pi * 2)
	prompt.Triggered:Connect(function(player)
		onTriggered(player, prompt, mine, level)
	end)
	model.Parent = folder
	placed = model
end

-- ── round lifecycle ─────────────────────────────────────────────────────────

local function evaluate()
	if workspace:GetAttribute("RoundActive") ~= true then
		-- RoundActive false is the ONE teardown trigger. A "loading" state must
		-- not tear down: the round is still active through the Level 2 -> Level 3
		-- continuation, which is a level change rather than a new round.
		if attemptedLevel ~= nil or placed or next(readers) then clearRound() end
		return
	end
	if workspace:GetAttribute("RoundLoadingState") ~= "ready" then return end
	if not FieldNotes then return end

	local level = workspace:GetAttribute("SelectedLevel")
	-- Not marked as attempted: a level this collection does not cover, or an
	-- attribute that has not been written yet, is a "not yet", not a failure.
	if type(level) ~= "number" or not (WORLD_ROOTS[level] and FieldNotes.ByLevel[level]) then
		return
	end
	if attemptedLevel ~= nil then
		if attemptedLevel == level then return end
		-- The level changed under a live round: the old prop is standing in a
		-- world that is being destroyed, so it goes with it.
		clearRound()
	end
	attemptedLevel = level
	generation += 1
	local mine = generation
	task.spawn(place, mine, level)
end

for _, attribute in ipairs({"RoundActive", "RoundLoadingState", "SelectedLevel"}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(evaluate)
end
Players.PlayerRemoving:Connect(function(player)
	readers[player.UserId] = nil
	lastTrigger[player.UserId] = nil
end)

evaluate()
