-- RoundUI
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "RoundUI"
-- Top-of-screen status bar: elevator countdown, deaths, win/lose.
-- No timer and no alive-count — winning is the puzzle, and nobody should know
-- how many teammates are still alive.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local remote = RS:WaitForChild("Remotes"):WaitForChild("RoundStatus")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "RoundGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 10)
label.Size = UDim2.new(0, 520, 0, 34)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.85 -- barely-there backdrop; the text carries it
label.BorderSizePixel = 0
label.Font = Enum.Font.Gotham
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(235, 232, 222)
label.Text = ""
label.Visible = false -- hide the black bar until there's actually a message
label.Parent = gui
local rlc = Instance.new("UICorner"); rlc.CornerRadius = UDim.new(0, 6); rlc.Parent = label

-- only show the bar when it has text (empty text left a blank black box)
local function setMsg(t)
	label.Text = t or ""
	label.Visible = (t ~= nil and t ~= "")
end

local dead = false

remote.OnClientEvent:Connect(function(ev, a, b)
	if ev == "waiting" then
		setMsg("Waiting for players…")

	elseif ev == "elevator" then
		dead = false
		setMsg("Doors opening in " .. a .. "…")

	elseif ev == "start" then
		-- round handed to the puzzle; PuzzleUI shows the objective from here
		dead = false
		setMsg("")

	elseif ev == "death" then
		-- no on-screen announcement — the positional death scream is the signal
		-- now. We still track OUR OWN death so the win banner reads correctly.
		if a == player.Name then
			dead = true
		end

	elseif ev == "lose" then
		setMsg("EVERYONE DIED — YOU LOSE")

	elseif ev == "win" then
		setMsg(dead and "THE OTHERS ESCAPED" or "YOU ESCAPED")
	end
end)
