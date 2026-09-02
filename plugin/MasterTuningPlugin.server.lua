-- MongoTV -- Master Tuning
--
-- A Studio dock panel over ReplicatedStorage.MasterConfiguration. It reads the
-- registry, shows every tunable grouped by level, and writes overrides straight
-- into the MasterTuning attributes -- no remote, no running game. That is the
-- point of the plugin: level design happens in Edit, and stopping to enter Play
-- for every room-size change is what makes tuning not happen at all.
--
-- EDIT MODE ONLY. While a simulation is running the panel refuses to read or
-- write and says so. Two reasons, and the second is the important one:
--
--   1. Studio plugins keep running when you press Play, but they stay bound to
--      the EDIT DataModel. An override written from here during Play would land
--      on objects the running game cannot see, so it would look like the panel
--      did nothing.
--   2. Worse, that write WOULD persist into the place once Play stops -- a
--      change made while looking at a running game, silently applied to the
--      saved place. Use the in-game panel (K) for tuning during a round.
--
-- It writes ONLY MasterTuning attributes. It never edits a configuration module,
-- never touches world geometry, and never sets a value outside the range the
-- registry declares -- Master.Coerce is the same clamp the server applies.
--
-- Install with:  python plugin/build_plugin.py
-- Studio picks it up on the next restart, or immediately via Plugins > Manage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WIDGET_ID = "MongoTVMasterTuning"
local ROW_HEIGHT = 24
local HEADER_HEIGHT = 26
local RUN_STATE_POLL = 1

-- No icon: the rbxasset:// paths for Studio's own icons move between versions,
-- and a missing one logs "Unable to load plugin icon" on every Studio start
-- without telling you which plugin did it. A text button cannot fail.
local toolbar = plugin:CreateToolbar("MongoTV")
local button = toolbar:CreateButton("Master Tuning",
	"Tune level sizes, entities and timings without starting the game", "")

local widget = plugin:CreateDockWidgetPluginGui(
	WIDGET_ID,
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 360, 520, 300, 320))
widget.Title = "MongoTV -- Master Tuning"
widget.Name = WIDGET_ID

--- Edit mode only. IsRunning() is true for Play, Run and Play Solo alike.
local function editable(): boolean
	return not RunService:IsRunning()
end

-- ------------------------------------------------------------------- theming

local studioTheme = settings().Studio.Theme

local function colour(name: string): Color3
	return studioTheme:GetColor(Enum.StudioStyleGuideColor[name])
end

-- ---------------------------------------------------- the registry, always fresh
--
-- Cloned before requiring. Studio's plugin VM caches require() for the lifetime
-- of the session, so a MasterConfiguration edited during that session would keep
-- serving the old registry -- and this panel exists to be edited alongside the
-- game. A clone is a different instance, so it gets its own cache entry.
local function loadRegistry(): any?
	local module = ReplicatedStorage:FindFirstChild("MasterConfiguration")
	if not (module and module:IsA("ModuleScript")) then return nil end
	local copy = module:Clone()
	copy.Parent = ReplicatedStorage
	local ok, result = pcall(require, copy)
	copy:Destroy()
	return if ok then result else nil
end

-- ------------------------------------------------------------------ the shell

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BorderSizePixel = 0
background.BackgroundColor3 = colour("MainBackground")
background.Parent = widget

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, 0, 0, 34)
status.BackgroundTransparency = 1
status.Font = Enum.Font.SourceSans
status.TextSize = 13
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = colour("DimmedText")
status.Text = ""
status.Parent = background

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 0, 0, 34)
scroll.Size = UDim2.new(1, 0, 1, -34)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 8
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = background

local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 2)
list.Parent = scroll

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 10)
padding.Parent = scroll

-- ---------------------------------------------------------------- row builders

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function makeHeader(text: string, dim: boolean?)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	label.BackgroundTransparency = 1
	label.Font = if dim then Enum.Font.SourceSans else Enum.Font.SourceSansBold
	label.TextSize = if dim then 13 else 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.TextColor3 = colour(if dim then "DimmedText" else "BrightText")
	label.Text = text
	label.LayoutOrder = nextOrder()
	label.Parent = scroll
	return label
end

local refresh -- forward declaration; rows re-render the whole list after a write

local function makeRow(Master: any, entry: any)
	local override = Master.GetOverride(entry.Key)
	local default = Master.GetDefault(entry.Key)
	local overridden = override ~= nil

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.LayoutOrder = nextOrder()
	row.Parent = scroll

	local label = Instance.new("TextLabel")
	label.Name = entry.Key
	label.Size = UDim2.new(1, -132, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSans
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextColor3 = colour(if overridden then "BrightText" else "MainText")
	label.Text = (if overridden then "\u{25CF} " else "") .. entry.Label
	label.Parent = row

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, 74, 1, -4)
	box.Position = UDim2.new(1, -128, 0, 2)
	box.BackgroundColor3 = colour("InputFieldBackground")
	box.BorderColor3 = colour(if overridden then "DialogMainButton" else "InputFieldBorder")
	box.TextColor3 = colour("MainText")
	box.Font = Enum.Font.Code
	box.TextSize = 13
	box.ClearTextOnFocus = false
	-- The legal range belongs where it is actually needed: in the field.
	box.PlaceholderText = string.format("%s-%s", tostring(entry.Minimum), tostring(entry.Maximum))
	box.Text = tostring(if overridden then override else (default or "?"))
	box.Parent = row

	local reset = Instance.new("TextButton")
	reset.Size = UDim2.new(0, 48, 1, -4)
	reset.Position = UDim2.new(1, -50, 0, 2)
	reset.BackgroundColor3 = colour("Button")
	reset.BorderColor3 = colour("ButtonBorder")
	reset.TextColor3 = colour(if overridden then "MainText" else "DimmedText")
	reset.Font = Enum.Font.SourceSans
	reset.TextSize = 12
	reset.Text = "Reset"
	reset.AutoButtonColor = overridden
	reset.Active = overridden
	reset.Parent = row

	-- A note, or the rebuild warning, gets its own dim line. Only a handful of
	-- entries carry a note, so this costs almost nothing and says the one thing a
	-- number and a range cannot: why the value matters.
	if entry.Note or not entry.Live then
		local note = Instance.new("TextLabel")
		note.Size = UDim2.new(1, -8, 0, 15)
		note.BackgroundTransparency = 1
		note.Font = Enum.Font.SourceSans
		note.TextSize = 11
		note.TextXAlignment = Enum.TextXAlignment.Left
		note.TextWrapped = true
		note.AutomaticSize = Enum.AutomaticSize.Y
		note.TextColor3 = colour("DimmedText")
		note.Text = "    " .. (entry.Note or "Takes effect on the next round build.")
		note.LayoutOrder = nextOrder()
		note.Parent = scroll
	end

	box.FocusLost:Connect(function(enterPressed)
		if not enterPressed then
			refresh()
			return
		end
		if not editable() then
			status.Text = "Stop the simulation first -- this panel is Edit mode only."
			refresh()
			return
		end
		local wanted = Master.Coerce(entry.Key, box.Text)
		if wanted == nil then
			status.Text = string.format("'%s' is not a number. %s unchanged.", box.Text, entry.Label)
			refresh()
			return
		end
		local ok, problem = Master.SetOverride(entry.Key, wanted)
		status.Text = if ok
			then string.format("%s = %s%s", entry.Label, tostring(wanted),
				if entry.Live then "" else "  (on the next round build)")
			else ("Refused: " .. tostring(problem))
		refresh()
	end)

	reset.MouseButton1Click:Connect(function()
		if not overridden then return end
		if not editable() then
			status.Text = "Stop the simulation first -- this panel is Edit mode only."
			return
		end
		Master.SetOverride(entry.Key, nil)
		status.Text = entry.Label .. " reset to " .. tostring(default or "its default") .. "."
		refresh()
	end)
end

-- ------------------------------------------------------------------- rendering

function refresh()
	order = 0
	for _, child in ipairs(scroll:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end
	end

	-- Refuse to render the controls at all while a simulation is running, rather
	-- than showing values that belong to the edit place while the user is looking
	-- at a running game.
	if not editable() then
		status.Text = "Edit mode only."
		makeHeader("Simulation is running")
		makeHeader("This panel edits the SAVED place, not the running game, so its "
			.. "values would not match what you are looking at -- and the write would "
			.. "persist once you stop.", true)
		makeHeader("Stop the simulation to use it, or press K in-game for the "
			.. "developer tuning panel, which does reach the live round.", true)
		return
	end

	local Master = loadRegistry()
	if not Master then
		status.Text = "ReplicatedStorage.MasterConfiguration was not found."
		makeHeader("Registry missing")
		makeHeader("Open the place that has MasterConfiguration in ReplicatedStorage.", true)
		return
	end

	-- Group the registry the way it is authored: level, then group, in order.
	local seenLevel, seenGroup = nil, nil
	local overrides = 0
	for _, entry in ipairs(Master.Entries) do
		if entry.Level ~= seenLevel then
			seenLevel = entry.Level
			seenGroup = nil
			makeHeader(entry.Level)
		end
		if entry.Group ~= seenGroup then
			seenGroup = entry.Group
			makeHeader("  " .. entry.Group, true)
		end
		if Master.GetOverride(entry.Key) ~= nil then overrides += 1 end
		makeRow(Master, entry)
	end

	if status.Text == "" then
		status.Text = string.format("%d tunable values, %d overridden.",
			#Master.Entries, overrides)
	end
end

-- ------------------------------------------------------------------- lifecycle

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
	if widget.Enabled then
		status.Text = ""
		refresh()
	end
end)

-- Re-render when something else changes an override: the running game, another
-- developer's push, or a hand edit in the Properties pane.
local watching: RBXScriptConnection? = nil
local function watchFolder()
	if watching then watching:Disconnect() end
	local folder = ReplicatedStorage:FindFirstChild("MasterTuning")
	if folder then
		watching = folder.AttributeChanged:Connect(function()
			if widget.Enabled then refresh() end
		end)
	end
end
watchFolder()
ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "MasterTuning" then watchFolder() end
end)

-- Studio gives a plugin no "play started" signal, so the run state is polled --
-- once a second, and only while the widget is open, so it costs nothing when it
-- is closed. Without this the panel would keep showing live controls after the
-- user pressed Play.
task.spawn(function()
	local lastEditable = editable()
	while true do
		task.wait(RUN_STATE_POLL)
		local now = editable()
		if now ~= lastEditable then
			lastEditable = now
			if widget.Enabled then
				status.Text = ""
				refresh()
			end
		end
	end
end)

if widget.Enabled then refresh() end
