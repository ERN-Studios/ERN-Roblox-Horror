-- Stored protection charges. Inventory and activation remain server-owned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
-- UI_STYLE_20260915 (Trello #98): chrome only. This control was already the
-- closest thing in the game to the reference; it was missing the stroke's
-- transparency, so its border read a full step harder than every panel's.
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))
local Client = require(ReplicatedStorage:WaitForChild("ProtectionClient"))

local gui = Instance.new("ScreenGui")
gui.Name = "ProtectionHUD"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
-- Living players can cancel an L1 capture through this control. Real modals
-- and loading covers suppress it explicitly; JumpscareGui has order 1000.
gui.DisplayOrder = 1001
gui.Enabled = false
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "ProtectionUse"
button.Size = UDim2.fromOffset(138, 52)
button.AnchorPoint = Vector2.new(0, 1)
button.TextWrapped = false
button.AutoButtonColor = false
button.Selectable = false
button.Modal = false
button.Active = false
button.Visible = false
button.Parent = gui
-- Chip chrome, and the soft green the objectives toggle prints in. TextSize is
-- rewritten per form factor further down (10 on the narrowest bands), so the
-- helper's 12 is only the seed.
UIStyle.button(button, {
	Background = Color3.fromRGB(20, 35, 31),
	Transparency = 0,
	Radius = UIStyle.Radius.Chip,
	TextColor = Color3.fromRGB(158, 244, 195),
	TextSize = 12,
})

local connections, characterConnections = {}, {}
local boundCharacter, boundHumanoid
local healthConnection
local touch, registered, destroyed = false, false, false
local held = {}

local function connect(signal, callback, list)
	local connection = signal:Connect(callback)
	table.insert(list or connections, connection)
	return connection
end

local function disconnectAll(list)
	for _, connection in ipairs(list) do connection:Disconnect() end
	table.clear(list)
end

local function covered()
	local roundGui = playerGui:FindFirstChild("RoundGui")
	if not roundGui or not roundGui.Enabled then return false end
	-- These are the actual RoundUI frames, including the brief interval before
	-- their corresponding replicated/modal attributes catch up.
	for _, name in ipairs({"LevelLoading", "QueueHostShade"}) do
		local frame = roundGui:FindFirstChild(name)
		if frame and frame.Visible then return true end
	end
	return false
end

local function contextAvailable()
	return not destroyed and boundCharacter ~= nil and player.Character == boundCharacter
		and boundCharacter.Parent ~= nil and boundHumanoid ~= nil
		and boundCharacter:FindFirstChildOfClass("Humanoid") == boundHumanoid
		and boundHumanoid.Health > 0 and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true and player:GetAttribute("Spectating") ~= true
		and player:GetAttribute("Level2_ExitTransition") ~= true
		and workspace:GetAttribute("RoundActive") == true
		and workspace:GetAttribute("RoundLoadingState") == "ready"
		and player:GetAttribute("RoundEntryControlsReady") == true
		and player:GetAttribute("DispatchBriefingOpen") ~= true
		and not UIDevice.ScreenOwningModalOpen() and not covered()
		and not GuiService.MenuIsOpen and UIS:GetFocusedTextBox() == nil
end

-- SPECTATE_UI_PARITY_20260914 -- the player we are WATCHING, or nil.
-- SpectateController publishes `Spectating` / `SpectateTargetUserId` on the
-- LocalPlayer. A subject only counts while they are a living, in-round,
-- non-escaped participant, i.e. exactly the players SpectateController picks.
local function spectateSubject()
	if player:GetAttribute("Spectating") ~= true then return nil end
	local userId = player:GetAttribute("SpectateTargetUserId")
	local watched = type(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
	if not watched or watched:GetAttribute("InRound") ~= true
		or watched:GetAttribute("Escaped") == true then return nil end
	local character = watched.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") then
		return watched
	end
	return nil
end

-- PlayerProtectionActive / PlayerProtectionExpiresAt are SERVER-set on the
-- Player (ServerScriptService/PlayerProtection.ModuleScript.lua), so they
-- replicate and the watched player's shield can be read for anyone.
local function secondsRemaining(subject)
	subject = subject or player
	local expires = subject:GetAttribute("PlayerProtectionExpiresAt")
	if subject:GetAttribute("PlayerProtectionActive") ~= true or type(expires) ~= "number"
		or expires ~= expires or expires == math.huge or expires == -math.huge then return 0 end
	return math.clamp(expires - workspace:GetServerTimeNow(), 0, 5)
end

local function canPress(state, remaining)
	if not contextAvailable() or GuiService.SelectedObject ~= nil then return false end
	if state.Pending then
		-- Q never retries a shop purchase. Both views still share one owner.
		return state.Pending.Action == "UseProtection" and state.CanRetry == true
	end
	return remaining <= 0 and state.Available == true and not state.ServerPending and state.Charges > 0
end

-- SPECTATE_UI_PARITY_20260914: while spectating, this HUD stops being a control
-- and becomes a READ-ONLY mirror of the watched player's shield -- timer only.
-- No charge count (Charges is ProtectionClient's view of OUR OWN inventory, so
-- printing it beside their timer would be a lie), no key binding, never
-- pressable, and no touch control rect: `mirroring` is what tells applyLayout
-- both of those. It stands down the moment the subject changes or goes invalid.
local mirroring = false
local applyLayout

local function refresh()
	if destroyed then return end
	local subject = spectateSubject()
	if (subject ~= nil) ~= mirroring then
		mirroring = subject ~= nil
		applyLayout() -- re-places the button and (un)registers the control rect
		return        -- ...and tail-calls this function with the flip consumed
	end
	if subject then
		local watchedRemaining = secondsRemaining(subject)
		local showing = watchedRemaining > 0
		gui.Enabled, button.Visible = showing, showing
		button.Active, button.AutoButtonColor = false, false
		button.Text = "SAFE\n" .. string.format("%.1fs", watchedRemaining)
		button.TextTransparency = 0
		return
	end
	local state = Client.GetState()
	local remaining = secondsRemaining()
	local visible = contextAvailable()
	gui.Enabled, button.Visible = visible, visible
	button.Active = visible and canPress(state, remaining)
	button.AutoButtonColor = button.Active
	local count = state.Charges > 99 and "99+" or tostring(state.Charges)
	local title, detail
	if remaining > 0 then
		title, detail = "SAFE", string.format("%.1fs", remaining)
		if button.Active then title = "RETRY" end
	elseif state.Pending then
		title = touch and "SHIELD" or "Entity Shield"
		detail = button.Active and "RETRY" or "WAIT"
	elseif not state.Available or state.ServerPending then
		title, detail = touch and "SHIELD" or "Entity Shield", "WAIT"
	else
		title = touch and "SHIELD" or "Entity Shield"
		detail = touch and ("x" .. count) or (count .. " CHARGES")
	end
	if not touch then
		local binding = UIDevice.Binding("Q", "D-PAD DOWN")
		if binding ~= "" then detail ..= "\n[" .. binding .. "]" end
	end
	button.Text = title .. "\n" .. detail
	button.TextTransparency = (button.Active or remaining > 0) and 0 or .3
end

function applyLayout()
	if destroyed then return end
	local layout = UIDevice.Layout()
	touch = layout.IsTouch
	-- The read-only mirror is a label, not a control, so it never takes a touch
	-- control slot -- it uses the plain placement on every device.
	local control = touch and not mirroring
	if control ~= registered then
		registered = control
		if registered then UIDevice.RegisterControlRect("ProtectionUse", button)
		else UIDevice.UnregisterControlRect(button) end
	end
	if control then
		local slot = layout.ControlPlan.Slots.ProtectionUse
		assert(slot and slot.Width >= 44 and slot.Height >= 44, "ProtectionUse needs a 44px control slot")
		button.AnchorPoint = Vector2.new(1, 1)
		button.Size = UDim2.fromOffset(slot.Width, slot.Height)
		button.Position = UDim2.new(1, -slot.Right, 1, -slot.Bottom)
		button.TextSize = 10
	else
		button.AnchorPoint = Vector2.new(0, 1)
		button.Size = UDim2.fromOffset(138, 52)
		-- The desktop torch ends at x84. Stamina sits near bottom22. This
		-- button starts at x98 and ends 92px above the bottom, away from both.
		local x = math.clamp(gui.AbsolutePosition.X + 98, layout.Safe.Left + 8, layout.Safe.Right - 146)
		local bottom = math.clamp(gui.AbsolutePosition.Y + gui.AbsoluteSize.Y - 92,
			layout.Safe.Top + 60, layout.Safe.Bottom - 8)
		button.Position = UIDevice.LocalPosition(gui, x, bottom)
		button.TextSize = 12
	end
	refresh()
end

local function press()
	local state = Client.GetState()
	if not canPress(state, secondsRemaining()) then return end
	if state.Pending then Client.Retry() else Client.Request("UseProtection") end
	refresh()
end

local function bindHumanoid()
	if destroyed then return end
	if healthConnection then healthConnection:Disconnect(); healthConnection = nil end
	boundHumanoid = boundCharacter and boundCharacter:FindFirstChildOfClass("Humanoid")
	if boundHumanoid then healthConnection = boundHumanoid.HealthChanged:Connect(refresh) end
	refresh()
end

local function bindCharacter(character)
	if player.Character ~= character or destroyed then return end
	disconnectAll(characterConnections)
	boundCharacter = character
	connect(character.ChildAdded, bindHumanoid, characterConnections)
	connect(character.ChildRemoved, bindHumanoid, characterConnections)
	bindHumanoid()
end

connect(player.CharacterAdded, bindCharacter)
connect(player.CharacterRemoving, function(character)
	if boundCharacter ~= character then return end
	boundCharacter = nil
	disconnectAll(characterConnections)
	bindHumanoid()
end)
connect(UIS.InputBegan, function(input, processed)
	local key = input.KeyCode
	if key ~= Enum.KeyCode.Q and key ~= Enum.KeyCode.DPadDown then return end
	if held[key] then return end
	held[key] = true
	if processed or input.UserInputState ~= Enum.UserInputState.Begin then return end
	press()
end)
connect(UIS.InputEnded, function(input) held[input.KeyCode] = nil end)
connect(UIS.WindowFocusReleased, function() table.clear(held) end)
connect(button.Activated, function(input)
	if input and (input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1) then press() end
end)
connect(Client.Changed, refresh)
connect(UIDevice.Changed, applyLayout)
connect(GuiService:GetPropertyChangedSignal("MenuIsOpen"), refresh)
connect(GuiService:GetPropertyChangedSignal("SelectedObject"), refresh)
connect(UIS.TextBoxFocused, refresh)
connect(UIS.TextBoxFocusReleased, refresh)
for _, name in ipairs({"InRound", "Escaped", "Spectating", "SpectateTargetUserId",
	"Level2_ExitTransition", "RoundEntryControlsReady",
	"DispatchBriefingOpen", "ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen",
	"PlayerProtectionActive", "PlayerProtectionExpiresAt"}) do
	connect(player:GetAttributeChangedSignal(name), refresh)
end
for _, name in ipairs({"RoundActive", "RoundLoadingState"}) do
	connect(workspace:GetAttributeChangedSignal(name), refresh)
end
-- Observe local covers and the server display clock even when no attribute
-- changes. This never requests, retries, activates or clears protection.
connect(RunService.RenderStepped, refresh)
connect(script.Destroying, function()
	destroyed = true
	disconnectAll(connections)
	disconnectAll(characterConnections)
	if healthConnection then healthConnection:Disconnect() end
	if registered then UIDevice.UnregisterControlRect(button) end
	gui:Destroy()
end)
if player.Character then bindCharacter(player.Character) end
applyLayout()
