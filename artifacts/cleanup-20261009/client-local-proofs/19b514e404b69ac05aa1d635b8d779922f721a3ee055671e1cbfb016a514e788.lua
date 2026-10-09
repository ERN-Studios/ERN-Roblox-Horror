-- First Entry Guide: the new-player TUTORIAL (TUTORIAL_20261004, owner: "what it is about, how they play, how they
-- play with others, earn and use tokens - simple, fast and easily skippable"). It replaced the single welcome card.
--
-- Four short pages in one card: THE GAME, HOW YOU PLAY, PLAY TOGETHER, RESEARCH TOKENS. NEXT / BACK step through
-- them (Enter, Space, the arrow keys, gamepad A / bumpers); SKIP is on every page (Escape, gamepad B) and closes
-- it at once. A brand-new player (ZyntraFirstLogin, published by ZyntraMonetization once the profile has loaded)
-- gets it once, as soon as the lobby cover is gone. Never on a round server or in a round.
--
-- HELP (HELP_20261004, owner: "a Help tab they can open that explains every important part of the game very
-- simply"): a small HELP button under BADGES on the lobby's left rail opens a panel with ten topics down the left
-- and a few plain lines for each on the right, plus PLAY THE TUTORIAL to see the four pages again.
-- `workspace.DevShowWelcome = true` (Studio) shows it regardless, for testing. Numbers on the tokens page are read
-- from ReplicatedStorage.ZyntraConfig so they cannot go stale.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
-- MOBILE_QA_20261008: the screen is asked of UIDevice (what THIS device shows and where its safe area ends), not
-- of the raw camera viewport, which counts Roblox's top bar: that put the HELP button on top of MUTE or under the
-- bottom edge on phones.
local UIDevice = require(game:GetService("ReplicatedStorage"):WaitForChild("UIDevice"))

-- SPAWN_VIEW_20261004 (owner): whoever arrives in the lobby looks down the tunnel toward the DJ stage, with the
-- arrival gate behind them. The server already stands the body that way (GameManager.scatterAt); the camera keeps
-- whatever direction it had, so it is turned here, once per lobby spawn, as soon as the default camera owns the
-- view again (the loading cover and the briefing do not use it).
task.spawn(function()
	local function aim(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then return end
		local started = os.clock()
		while os.clock() - started < 20 do
			if character.Parent == nil or player:GetAttribute("InRound") == true then return end
			local lobby = workspace:FindFirstChild("ServerLobby")
			local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
			local stage = workspace:FindFirstChild("LobbyReimaginedPreview")
			local camera = workspace.CurrentCamera
			if spawn and spawn:IsA("BasePart") and stage and camera and camera.CameraType == Enum.CameraType.Custom
				and (root.Position - spawn.Position).Magnitude <= 30 then
				local toward = (stage:GetPivot().Position - spawn.Position) * Vector3.new(1, 0, 1)
				if toward.Magnitude < 1 then return end
				toward = toward.Unit
				local head = root.Position + Vector3.new(0, 2, 0)
				camera.CFrame = CFrame.lookAt(head - toward * 12 + Vector3.new(0, 3.5, 0), head + toward * 30)
				return
			end
			task.wait(0.1)
		end
	end
	player.CharacterAdded:Connect(aim)
	if player.Character then aim(player.Character) end
end)

local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled or workspace:GetAttribute("ForceTouchUI") == true
local GREEN, PAPER, INK, SOFT = Color3.fromRGB(120, 255, 190), Color3.fromRGB(240, 244, 236), Color3.fromRGB(9, 14, 12), Color3.fromRGB(176, 190, 180)
local AMBER = Color3.fromRGB(255, 203, 79)

-- prices and rewards straight from the config
local config = nil
pcall(function() config = require(game:GetService("ReplicatedStorage"):WaitForChild("ZyntraConfig", 10)) end)
local function find(root, key, depth)                               -- the first table that carries `key`, a few levels down
	if type(root) ~= "table" or depth > 4 then return nil end
	if root[key] ~= nil then return root end
	for _, value in pairs(root) do
		local found = find(value, key, depth + 1)
		if found then return found end
	end
	return nil
end
local function costOf(name, fallback)
	local found = nil
	local function walk(node, depth)
		if found or type(node) ~= "table" or depth > 5 then return end
		if node.Name == name and type(node.TokenCost) == "number" then found = node.TokenCost return end
		for _, value in pairs(node) do walk(value, depth + 1) end
	end
	walk(config, 0)
	return found or fallback
end
local perClear = config and tonumber(config.LevelCompletionTokens) or 2
local starting = (find(config, "StartingTokens", 0) or {}).StartingTokens or 25
local shield, potion, markers = costOf("Entity Shield", 5), costOf("Speed Potion", 3), costOf("Route Marker Pack", 2)

local PAGES = {
	{kicker = "THE GAME", title = "WELCOME TO THE BACKROOMS", rows = {
		{"?", "A CO-OP HORROR GAME", "Six levels. Each one is a different place with a different thing living in it."},
		{"!", "GET IN, GET OUT", "Every level gives you a job to do and an exit to reach. Do it and leave alive."},
		{"~", "THEY CAN HEAR YOU", "Noise and light give you away. Stay quiet."},
	}},
	{kicker = "HOW YOU PLAY", title = "QUIET, LIGHT, HIDE", rows = {
		{"1", "MOVE QUIETLY", touch and "Use the sneak button to move without a sound. Sprinting is fast and loud."
			or "Hold Ctrl to sneak without a sound. Shift sprints: fast, and loud."},
		{"2", "USE YOUR FLASHLIGHT", touch and "The flashlight button switches it on and off. The battery runs down."
			or "F switches it on and off. The battery runs down."},
		{"3", "FOLLOW THE OBJECTIVE", "The panel on screen says what to do next. If something comes, hide or run."},
	}},
	{kicker = "PLAY TOGETHER", title = "BRING A TEAM", rows = {
		{"1", "WALK TO A LEVEL GATE", "The gates are along the tunnel. Every level is open; LEVEL 1 is the place to start."},
		{"2", "STEP ON A PAD", "Choose 1 to 6 players and press CREATE PARTY. Friends step on the same pad to join."},
		{"3", "FRIENDS PAY OFF", "Each Roblox friend in your round gives you +10% tokens. If you go down, you watch your team."},
	}},
	{kicker = "RESEARCH TOKENS", title = "EARN THEM, SPEND THEM", accent = AMBER, rows = {
		{"+", "EARN", ("You start with %d. Clear a level: +%d. More from DAILY REWARDS and the LUCKY WHEEL on the left."):format(starting, perClear)},
		{"-", "SPEND IN THE SHOP", ("Entity Shield %d  ·  Speed Potion %d  ·  Route Markers %d. Open SHOPS on the left."):format(shield, potion, markers)},
		{"^", "UPGRADE FOR GOOD", "UPGRADES makes your stamina and your flashlight battery last longer, permanently."},
	}, foot = "We are a team of only 2 people making this game. A like, a favourite or a note in our Discord goes a long way."},
}

local open = false
local function show()
	if open or player:GetAttribute("InRound") == true or workspace:GetAttribute("ReservedRoundServer") == true then return end
	open = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "WelcomeCard"
	gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = false, true, 60
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.Size, shade.BackgroundColor3, shade.BackgroundTransparency, shade.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 1, 0
	shade.Active = true
	shade.Parent = gui
	local W, H = 620, 452
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint, card.Position, card.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(W, H)
	card.BackgroundColor3, card.BackgroundTransparency, card.BorderSizePixel = INK, 0.03, 0
	card.Parent = shade
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color, stroke.Thickness, stroke.Transparency = GREEN, 2, 0.25
	local scale = Instance.new("UIScale", card)
	local function fit()
		local view = UIDevice.Layout().Viewport
		scale.Scale = math.clamp(math.min((view.X - 28) / W, (view.Y - 28) / H), 0.5, 1.3)
	end
	fit()
	local resized = UIDevice.Changed:Connect(fit)
	local function text(parent, name, content, size, colour, x, y, w, h, font)
		local item = Instance.new("TextLabel")
		item.Name, item.Text, item.TextSize, item.TextColor3 = name, content, size, colour
		item.Font = font or Enum.Font.GothamMedium
		item.BackgroundTransparency, item.TextWrapped = 1, true
		item.TextXAlignment, item.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
		item.Position, item.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
		item.Parent = parent
		return item
	end
	local function button(name, label, colour, textColour, x, anchor, width)
		local item = Instance.new("TextButton")
		item.Name, item.Text, item.TextSize, item.Font, item.TextColor3 = name, label, 18, Enum.Font.GothamBlack, textColour
		item.AnchorPoint, item.Position, item.Size = Vector2.new(anchor, 1), UDim2.new(anchor, x, 1, -18), UDim2.fromOffset(width, 50)
		item.BackgroundColor3, item.BorderSizePixel, item.AutoButtonColor = colour, 0, true
		item.Parent = card
		Instance.new("UICorner", item).CornerRadius = UDim.new(0, 10)
		return item
	end
	local kicker = text(card, "Kicker", "", 13, GREEN, 34, 24, 420, 16, Enum.Font.Code)
	local title = text(card, "Title", "", 30, PAPER, 34, 44, W - 68, 38, Enum.Font.GothamBlack)
	local skip = Instance.new("TextButton")                             -- always there, top right
	skip.Name, skip.Text, skip.TextSize, skip.Font, skip.TextColor3 = "Skip", touch and "SKIP" or "SKIP  [ESC]", 13, Enum.Font.GothamBold, SOFT
	skip.AnchorPoint, skip.Position, skip.Size = Vector2.new(1, 0), UDim2.new(1, -18, 0, 16), UDim2.fromOffset(touch and 84 or 112, touch and 40 or 30)
	skip.BackgroundColor3, skip.BackgroundTransparency, skip.BorderSizePixel = Color3.fromRGB(30, 40, 36), 0.2, 0
	skip.Parent = card
	Instance.new("UICorner", skip).CornerRadius = UDim.new(0, 8)
	local body = Instance.new("Frame")
	body.Name, body.BackgroundTransparency = "Body", 1
	body.Position, body.Size = UDim2.fromOffset(0, 100), UDim2.fromOffset(W, 250)
	body.Parent = card
	local back = button("Back", "BACK", Color3.fromRGB(30, 40, 36), PAPER, 34, 0, 120)
	local nextButton = button("Next", "NEXT", Color3.fromRGB(42, 150, 100), Color3.new(1, 1, 1), -34, 1, 230)
	local dots = {}
	for index = 1, #PAGES do
		local dot = Instance.new("Frame")
		dot.Name, dot.BorderSizePixel = "Dot" .. index, 0
		dot.AnchorPoint, dot.Size = Vector2.new(0.5, 0.5), UDim2.fromOffset(9, 9)
		dot.Position = UDim2.new(0.5, (index - (#PAGES + 1) / 2) * 20 - 40, 1, -43)
		dot.Parent = card
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		dots[index] = dot
	end
	local page = 1
	local function draw()
		local data = PAGES[page]
		local accent = data.accent or GREEN
		body:ClearAllChildren()
		kicker.Text, kicker.TextColor3 = ("ZYNTRA  //  %s   %d / %d"):format(data.kicker, page, #PAGES), accent
		title.Text = data.title
		stroke.Color = accent
		for index, row in ipairs(data.rows) do
			local y = (index - 1) * 72
			local badge = Instance.new("TextLabel")
			badge.Name = "Badge" .. index
			badge.Position, badge.Size = UDim2.fromOffset(34, y), UDim2.fromOffset(44, 44)
			badge.BackgroundColor3, badge.BackgroundTransparency, badge.BorderSizePixel = accent, 0.82, 0
			badge.Text, badge.TextSize, badge.TextColor3, badge.Font = row[1], 24, accent, Enum.Font.GothamBlack
			badge.Parent = body
			Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
			text(body, "Head" .. index, row[2], 19, PAPER, 94, y, W - 128, 22, Enum.Font.GothamBold)
			text(body, "Text" .. index, row[3], 15, SOFT, 94, y + 24, W - 128, 40)
		end
		if data.foot then text(body, "Foot", data.foot, 13, SOFT, 34, 216, W - 68, 34) end
		for index, dot in ipairs(dots) do
			dot.BackgroundColor3 = index == page and accent or Color3.fromRGB(70, 84, 78)
		end
		back.Visible = page > 1
		nextButton.Text = page == #PAGES and "START PLAYING" or "NEXT"
	end
	draw()
	gui.Parent = player:WaitForChild("PlayerGui")
	player:SetAttribute("WelcomeCardOpen", true)
	TweenService:Create(shade, TweenInfo.new(0.3), {BackgroundTransparency = 0.45}):Play()

	local connections = {resized}
	local function close()
		if not open then return end
		open = false
		for _, connection in ipairs(connections) do connection:Disconnect() end
		player:SetAttribute("WelcomeCardOpen", nil)
		gui:Destroy()
	end
	local function step(by)
		if page + by > #PAGES then close() return end
		page = math.clamp(page + by, 1, #PAGES)
		draw()
	end
	skip.Activated:Connect(close)
	-- a test can turn the pages without an input device: gui:SetAttribute("Page", n); 0 closes
	table.insert(connections, gui:GetAttributeChangedSignal("Page"):Connect(function()
		local to = gui:GetAttribute("Page")
		if to == 0 then close() elseif type(to) == "number" and PAGES[to] then page = to draw() end
	end))
	back.Activated:Connect(function() step(-1) end)
	nextButton.Activated:Connect(function() step(1) end)
	table.insert(connections, UserInputService.InputBegan:Connect(function(event)
		local key = event.KeyCode
		if key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then close()
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.Space or key == Enum.KeyCode.Right
			or key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.ButtonR1 then step(1)
		elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.ButtonL1 then step(-1) end
	end))
	table.insert(connections, player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") == true then close() end
	end))
end

-- HELP: every important part of the game, a few plain lines each ------------------------------------------------
local KEYS = touch and {sneak = "the sneak button", sprint = "the sprint button", light = "the flashlight button", use = "Tap the prompt"}
	or {sneak = "Hold Ctrl", sprint = "Hold Shift", light = "F", use = "Hold E"}
local TOPICS = {
	{"THE GOAL", {
		{"What you do", "Pick a level, go in with your team, finish its objective and reach the exit alive."},
		{"What stops you", "Every level has something hunting in it. It finds you by sound and by sight."},
		{"If you clear it", ("You get Research Tokens (+%d per level) and the level counts toward your badges."):format(perClear)},
	}},
	{"CONTROLS", touch and {
		{"Move and look", "Left stick to move, drag the screen to look."},
		{"Sneak and sprint", "Sneak is silent. Sprint is fast, loud, and uses stamina."},
		{"Flashlight", "The flashlight button switches it on and off."},
		{"Use things", "Tap the prompt that appears next to an object. Some need you to keep holding."},
		{"Your items", "Shield, potion, marker and detector have their own buttons once you own them."},
	} or {
		{"Move and look", "WASD to move, mouse to look, Space to jump."},
		{"Sneak and sprint", "Ctrl sneaks without a sound. Shift sprints: fast, loud, and uses stamina."},
		{"Flashlight", "F switches it on and off. On a gamepad: R1. Sprint on a gamepad: hold L2."},
		{"Use things", "Hold E on the prompt next to an object until the ring is full."},
		{"Your items", "Q shield, T speed potion, X route marker, Z detector, once you own them."},
	}},
	{"STAYING ALIVE", {
		{"Noise", "Sprinting and running are heard from far away. Sneak when it is near."},
		{"Light", "Your flashlight helps you see and helps it see you. The battery runs down."},
		{"Stamina", "Sprinting drains it. Stop to get it back."},
		{"When it comes", "Break its line of sight, hide, or get away. Do not stand and watch."},
	}},
	{"THE LEVELS", {
		{"1  Office", "Get the power back on and reach the way out. Something tall walks the halls."},
		{"2  Poolrooms", "Start the pumps to open the exit. Keep an eye on what is in the water."},
		{"3  Mall", "Find the CDs. Hide under tables, but the Manager checks them."},
		{"4  Cinema", "The power is out. Find the breaker order and stay away from the Usher."},
		{"5  Void rooms", "Jump the ledges. Doors open when the whole team stands on the plate. A fall is death."},
		{"6  Playground", "Hide and seek. Touch the yellow post in three searches without being seen, then run for the exit."},
	}},
	{"PLAYING TOGETHER", {
		{"Start a party", "Walk to a level gate, step on a pad, choose 1 to 6 players and press CREATE PARTY."},
		{"Join one", "Step on a pad that someone else has opened before it launches."},
		{"Friends", "Each Roblox friend in your round gives you +10% tokens."},
		{"Leaving", "The LOBBY chip in the top left takes you back to the lobby during a round."},
	}},
	{"IF YOU DIE", {
		{"You spectate", "You watch your teammates. They can still finish the level."},
		{"Party down", "If everyone is down you get 15 seconds to use an Emergency Re-entry before the round ends."},
		{"Emergency Re-entry", "Puts you back in the round once. It is bought with Robux in the shop."},
	}},
	{"TOKENS", {
		{"Earning", ("You start with %d. Clearing a level gives +%d, more with friends."):format(starting, perClear)},
		{"Free tokens", "DAILY REWARDS and the LUCKY WHEEL on the left rail give tokens and items."},
		{"Spending", "SHOPS for items, UPGRADES for permanent stamina and battery."},
	}},
	{"ITEMS", {
		{"Entity Shield", ("%d tokens. Saves you from one attack."):format(shield)},
		{"Speed Potion", ("%d tokens. 30%% faster for 6 seconds, once per round."):format(potion)},
		{"Route Markers", ("%d tokens for 3. Point the way for your whole team."):format(markers)},
		{"Upgrades", "Each one makes stamina or battery last a little longer for good. The price rises by one each time."},
	}},
	{"REWARDS & BADGES", {
		{"Daily Rewards", "Come back each day and stay a few minutes: the Rewards button on the left."},
		{"Lucky Wheel", "A spin for tokens, potions or a shield: the Wheel button on the left."},
		{"Badges", "20 achievements. The BADGES button shows which you have and what is left."},
	}},
	{"SETTINGS & SUPPORT", {
		{"Comfort", "SETTINGS in the shop terminal: less camera shake, less flashing, captions."},
		{"Sound", "The Mute button on the left rail silences the lobby music."},
		{"Tell us", "We are two people making this. Bugs and ideas are welcome in our Discord (#bugs, #feedback)."},
	}},
}
local helpGui, helpClose = nil, nil
local function help()
	if helpGui then helpClose() return end
	if open or player:GetAttribute("InRound") == true then return end
	do
		local switch = player:FindFirstChild("PlayerScripts") and player.PlayerScripts:FindFirstChild("ZyntraRailSwitch")
		if switch and switch:IsA("BindableFunction") then pcall(switch.Invoke, switch, "HelpPanelOpen") end
	end
	local W, H = 760, 500
	local gui = Instance.new("ScreenGui")
	-- 117: the height the lobby's windows draw at, under the rail's 119 (HelpPanelOpen is one of UIDevice's
	-- screen-owning modals since MOBILE_QA_20261008, so the rail, token pill and chip stand over it as over the shop)
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "HelpPanel", false, true, 117
	helpGui = gui
	local shade = Instance.new("Frame")
	shade.Size, shade.BackgroundColor3, shade.BackgroundTransparency, shade.BorderSizePixel, shade.Active = UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 0.5, 0, true
	shade.Parent = gui
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint, panel.Position, panel.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(W, H)
	panel.BackgroundColor3, panel.BackgroundTransparency, panel.BorderSizePixel = INK, 0.03, 0
	panel.Parent = shade
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
	local edge = Instance.new("UIStroke", panel)
	edge.Color, edge.Thickness, edge.Transparency = GREEN, 2, 0.25
	local scale = Instance.new("UIScale", panel)
	local columns = function() end                 -- set once the two columns exist
	local function fit()
		-- The rectangle the lobby's own windows take: the modal viewport, on touch the whole safe height, and never
		-- under the rail (ZyntraRailRight). Where that is smaller than the authored 760 x 500 the panel takes what
		-- there is at full text size (on touch) and its two columns scroll, instead of the whole panel shrinking.
		local device = UIDevice.Layout()
		local area = device.ModalViewport
		local left, top, room, tall = area.Left, area.Top, area.Width, area.Height
		if device.IsTouch then top, tall = device.Safe.Top, device.Safe.Bottom - device.Safe.Top end
		local railRight = player:GetAttribute("ZyntraRailRight")
		if type(railRight) == "number" and left < railRight + 8 then
			room, left = room - (railRight + 8 - left), railRight + 8
		end
		local s = math.clamp(math.min(room / W, tall / H), device.IsTouch and 1 or 0.8, 1.25)
		scale.Scale = s
		panel.Size = UDim2.fromOffset(math.min(W, math.floor(room / s)), math.min(H, math.floor(tall / s)))
		panel.Position = UIDevice.LocalPosition(gui, left + room / 2, top + tall / 2)
		columns(panel.Size.X.Offset < 560)
	end
	local connections = {UIDevice.Changed:Connect(fit), player:GetAttributeChangedSignal("ZyntraRailRight"):Connect(fit)}
	local function label(parent, content, size, colour, font)
		local item = Instance.new("TextLabel")
		item.Text, item.TextSize, item.TextColor3, item.Font = content, size, colour, font or Enum.Font.GothamMedium
		item.BackgroundTransparency, item.TextWrapped = 1, true
		item.TextXAlignment, item.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
		item.Parent = parent
		return item
	end
	local head = label(panel, "HELP", 28, PAPER, Enum.Font.GothamBlack)
	head.Position, head.Size = UDim2.fromOffset(28, 18), UDim2.fromOffset(200, 34)
	local sub = label(panel, "ZYNTRA  //  FIELD MANUAL", 12, GREEN, Enum.Font.Code)
	sub.Position, sub.Size = UDim2.fromOffset(30, 52), UDim2.fromOffset(300, 16)
	local function close()
		if helpGui ~= gui then return end
		helpGui = nil
		for _, connection in ipairs(connections) do connection:Disconnect() end
		player:SetAttribute("HelpPanelOpen", nil)
		UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
		gui:Destroy()
	end
	helpClose = close
	local x = Instance.new("TextButton")
	x.Name, x.Text, x.TextSize, x.Font, x.TextColor3 = "Close", "×", 26, Enum.Font.GothamBold, PAPER
	x.AnchorPoint, x.Position, x.Size = Vector2.new(1, 0), UDim2.new(1, -16, 0, 14), UDim2.fromOffset(44, 44)
	x.BackgroundColor3, x.BorderSizePixel = Color3.fromRGB(30, 40, 36), 0
	x.Parent = panel
	Instance.new("UICorner", x).CornerRadius = UDim.new(0, 8)
	x.Activated:Connect(close)
	local replay = Instance.new("TextButton")
	replay.Name, replay.Text, replay.TextSize, replay.Font, replay.TextColor3 = "Tutorial", "PLAY THE TUTORIAL", 13, Enum.Font.GothamBold, Color3.new(1, 1, 1)
	replay.AnchorPoint, replay.Position, replay.Size = Vector2.new(1, 0), UDim2.new(1, -70, 0, 20), UDim2.fromOffset(190, 34)
	replay.BackgroundColor3, replay.BorderSizePixel = Color3.fromRGB(42, 150, 100), 0
	replay.Parent = panel
	Instance.new("UICorner", replay).CornerRadius = UDim.new(0, 8)
	replay.Activated:Connect(function() close() show() end)
	-- topics down the left, the chosen one on the right
	local list = Instance.new("ScrollingFrame")
	list.Name = "Topics"
	list.Position, list.Size = UDim2.fromOffset(20, 84), UDim2.new(0.3, -14, 1, -104)
	list.BackgroundTransparency, list.BorderSizePixel, list.ScrollBarThickness = 1, 0, 4
	list.CanvasSize, list.AutomaticCanvasSize = UDim2.new(), Enum.AutomaticSize.Y
	list.Parent = panel
	local listLayout = Instance.new("UIListLayout", list)
	listLayout.Padding = UDim.new(0, 6)
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position, content.Size = UDim2.new(0.3, 22, 0, 84), UDim2.new(0.7, -42, 1, -104)
	content.BackgroundColor3, content.BackgroundTransparency, content.BorderSizePixel = Color3.fromRGB(16, 24, 21), 0.2, 0
	content.ScrollBarThickness, content.ScrollBarImageColor3 = 5, GREEN
	content.CanvasSize, content.AutomaticCanvasSize = UDim2.new(), Enum.AutomaticSize.Y
	content.Parent = panel
	Instance.new("UICorner", content).CornerRadius = UDim.new(0, 10)
	local pad = Instance.new("UIPadding", content)
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 18), UDim.new(0, 18), UDim.new(0, 14), UDim.new(0, 14)
	local contentLayout = Instance.new("UIListLayout", content)
	contentLayout.Padding, contentLayout.SortOrder = UDim.new(0, 4), Enum.SortOrder.LayoutOrder
	local buttons = {}
	local function choose(index)
		for _, child in ipairs(content:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		content.CanvasPosition = Vector2.zero
		local topic = TOPICS[index]
		local order = 0
		local function add(textValue, size, colour, font, gap)
			order += 1
			local item = label(content, textValue, size, colour, font)
			item.LayoutOrder, item.AutomaticSize, item.Size = order, Enum.AutomaticSize.Y, UDim2.new(1, 0, 0, 0)
			if gap then
				order += 1
				local space = Instance.new("Frame")
				space.BackgroundTransparency, space.Size, space.LayoutOrder = 1, UDim2.new(1, 0, 0, gap), order
				space.Parent = content
			end
		end
		add(topic[1], 22, PAPER, Enum.Font.GothamBlack, 8)
		for _, row in ipairs(topic[2]) do
			add(row[1], 16, GREEN, Enum.Font.GothamBold)
			add(row[2], 15, SOFT, Enum.Font.GothamMedium, 10)
		end
		for i, item in ipairs(buttons) do
			item.BackgroundColor3 = i == index and Color3.fromRGB(42, 150, 100) or Color3.fromRGB(24, 34, 30)
			item.TextColor3 = i == index and Color3.new(1, 1, 1) or PAPER
		end
	end
	for index, topic in ipairs(TOPICS) do
		local item = Instance.new("TextButton")
		item.Name, item.Text, item.TextSize, item.Font = "Topic" .. index, "  " .. topic[1], 14, Enum.Font.GothamBold
		item.TextXAlignment, item.Size, item.BorderSizePixel = Enum.TextXAlignment.Left, UDim2.new(1, -8, 0, touch and 40 or 33), 0
		item.Parent = list
		Instance.new("UICorner", item).CornerRadius = UDim.new(0, 8)
		item.Activated:Connect(function() choose(index) end)
		buttons[index] = item
	end
	choose(1)
	-- a narrow panel (a small phone beside a two-column rail) gives the topic list more of its width and smaller
	-- names, and drops the kicker line that would run under PLAY THE TUTORIAL
	columns = function(narrow)
		local share = narrow and 0.4 or 0.3
		list.Size = UDim2.new(share, -14, 1, -104)
		content.Position, content.Size = UDim2.new(share, 22, 0, 84), UDim2.new(1 - share, -42, 1, -104)
		sub.Visible = not narrow
		for _, item in ipairs(buttons) do item.TextSize = narrow and 12 or 14 end
	end
	-- one window at a time: opening this one closes the rail's, and it closes when one of theirs opens
	for _, flag in ipairs({"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen", "LuckyWheelOpen",
		"DailyRewardsOpen", "AchievementsOpen"}) do
		table.insert(connections, player:GetAttributeChangedSignal(flag):Connect(function()
			if player:GetAttribute(flag) == true then close() end
		end))
	end
	table.insert(connections, gui:GetAttributeChangedSignal("Topic"):Connect(function()      -- for tests, as above
		local to = gui:GetAttribute("Topic")
		if to == 0 then close() elseif type(to) == "number" and TOPICS[to] then choose(to) end
	end))
	table.insert(connections, UserInputService.InputBegan:Connect(function(event)
		if event.KeyCode == Enum.KeyCode.Escape or event.KeyCode == Enum.KeyCode.ButtonB then close() end
	end))
	table.insert(connections, player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") == true then close() end
	end))
	gui.Parent = player:WaitForChild("PlayerGui")
	player:SetAttribute("HelpPanelOpen", true)
	UIDevice.SuppressTouchMovement(true)         -- the thumbstick and RUN stand down under it
	fit()                                        -- once it is on screen: its origin is only known then, and the rail has moved
end

do   -- the rail closes HELP through here before it opens one of its own windows (ZyntraStore.RAIL_WINDOWS)
	local closer = Instance.new("BindableFunction")
	closer.Name = "CloseHelpPanel"
	closer.OnInvoke = function()
		if helpGui then helpClose() end
		return true
	end
	closer.Parent = player:WaitForChild("PlayerScripts")
end

-- the HELP button: under BADGES on the lobby's left rail
task.spawn(function()
	local playerGui = player:WaitForChild("PlayerGui")
	local holder = Instance.new("ScreenGui")
	holder.Name, holder.ResetOnSpawn, holder.IgnoreGuiInset, holder.DisplayOrder = "HelpButton", false, false, 5
	local again = Instance.new("TextButton")
	again.Name, again.Text, again.TextSize, again.Font, again.TextColor3 = "Open", "Help", 13, Enum.Font.GothamBold, PAPER
	again.BackgroundColor3, again.BorderSizePixel, again.Size, again.Visible = Color3.fromRGB(22, 29, 32), 0, UDim2.fromOffset(64, 30), false
	again.Parent = holder
	Instance.new("UICorner", again).CornerRadius = UDim.new(0, 8)
	local line = Instance.new("UIStroke", again)
	line.Color, line.Thickness, line.ApplyStrokeMode = GREEN, 1.5, Enum.ApplyStrokeMode.Border
	holder.Parent = playerGui
	again.Activated:Connect(help)
	holder:GetAttributeChangedSignal("Toggle"):Connect(help)                  -- for tests: any change opens or closes it
	while true do
		local badges = nil
		for _, item in ipairs(playerGui:GetChildren()) do
			local button = item:IsA("ScreenGui") and item ~= holder and item.Enabled and item:FindFirstChild("Open")
			if button and button:IsA("TextButton") and button.Text == "Badges" then badges = button end
		end
		local inLobby = player:GetAttribute("InRound") ~= true and workspace:GetAttribute("ReservedRoundServer") ~= true
			and player:GetAttribute("LuckyWheelOpen") ~= true and player:GetAttribute("LobbyLoadingDone") == true
		again.Visible = inLobby and badges ~= nil and badges.Visible and not open and not UIDevice.ScreenOwningModalOpen()
		if not inLobby and helpGui then help() end
		if badges then
			-- under BADGES where the safe area has room; on a phone, where the rail runs to the bottom edge and BADGES
			-- stands beside its foot, above BADGES; failing that beside it. Never over a rail button.
			local at, size = badges.AbsolutePosition, badges.AbsoluteSize
			local bottom = UIDevice.Layout().Safe.Bottom - 6
			local rail = {}
			local store = playerGui:FindFirstChild("ZyntraStore")
			for _, item in ipairs(store and store:GetChildren() or {}) do
				if item:IsA("GuiButton") and item.Visible and item.AbsolutePosition.X < 120 and item.AbsoluteSize.X < 140 then
					table.insert(rail, item)
				end
			end
			local function free(x, y)
				if y < 0 or y + 30 > bottom then return false end
				for _, item in ipairs(rail) do
					local p, s = item.AbsolutePosition, item.AbsoluteSize
					if x < p.X + s.X and x + size.X > p.X and y < p.Y + s.Y and y + 30 > p.Y then return false end
				end
				return true
			end
			again.Size = UDim2.fromOffset(size.X, 30)
			local spots = {{at.X, at.Y + size.Y + 8}, {at.X, at.Y - 38}, {at.X + size.X + 8, at.Y}}
			local spot = spots[3]
			for _, candidate in ipairs(spots) do
				if free(candidate[1], candidate[2]) then spot = candidate break end
			end
			again.Position = UDim2.fromOffset(spot[1], spot[2])
		end
		task.wait(0.5)
	end
end)

local function wanted()
	if RunService:IsStudio() and workspace:GetAttribute("DevShowWelcome") == true then return true end
	return player:GetAttribute("ZyntraFirstLogin") == true
end
-- wait for the lobby to be on screen and for the profile to say whether this is a first visit
local deadline = os.clock() + 90
while os.clock() < deadline and player:GetAttribute("LobbyLoadingDone") ~= true do task.wait(0.25) end
local profileDeadline = os.clock() + 20
while os.clock() < profileDeadline and player:GetAttribute("ZyntraFirstLogin") == nil and not wanted() do task.wait(0.25) end
if workspace:GetAttribute("ReservedRoundServer") == true or player:GetAttribute("InRound") == true or not wanted() then return end
task.wait(1.2)                                                      -- let the lobby be seen for a moment first
show()
