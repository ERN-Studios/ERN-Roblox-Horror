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
label.BackgroundTransparency = 0.45
label.BorderSizePixel = 0
label.Font = Enum.Font.SpecialElite
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(225, 220, 200)
label.Text = ""
label.Parent = gui

local dead = false

remote.OnClientEvent:Connect(function(ev, a, b)
	if ev == "waiting" then
		label.Text = "Waiting for players…"

	elseif ev == "elevator" then
		dead = false
		label.Text = "Doors opening in " .. a .. "…"

	elseif ev == "start" then
		-- round handed to the puzzle; PuzzleUI shows the objective from here
		dead = false
		label.Text = ""

	elseif ev == "death" then
		-- name only — never a remaining-alive count
		if a == player.Name then
			dead = true
			label.Text = "You died — spectating"
		else
			label.Text = a .. " died"
		end

	elseif ev == "lose" then
		label.Text = "EVERYONE DIED — YOU LOSE"

	elseif ev == "win" then
		label.Text = dead and "THE OTHERS ESCAPED" or "YOU ESCAPED"
	end
end)
