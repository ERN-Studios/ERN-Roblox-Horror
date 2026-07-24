-- JumpscareUI
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "JumpscareUI"
-- Screen flicker + camera shake when the entity kills you.
-- OPTIONAL: paste asset ids below (find them in the Toolbox) for a face image / scream sound.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local remote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
local player = Players.LocalPlayer

-- Optional assets. Leave as "" and it still works (flicker + shake only).
-- Format: "rbxassetid://1234567890"
local JUMPSCARE_IMAGE = ""
local JUMPSCARE_SOUND = ""

remote.OnClientEvent:Connect(function()
	local gui = Instance.new("ScreenGui")
	gui.Name = "JumpscareGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false -- survives the respawn; we destroy it ourselves
	gui.DisplayOrder = 100
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Parent = gui

	if JUMPSCARE_IMAGE ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Crop
		img.Image = JUMPSCARE_IMAGE
		img.Parent = frame
	end

	if JUMPSCARE_SOUND ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = JUMPSCARE_SOUND
		s.Volume = 2
		s.Parent = gui
		s:Play()
	end

	-- camera shake
	task.spawn(function()
		local cam = workspace.CurrentCamera
		for _ = 1, 24 do
			cam.CFrame = cam.CFrame * CFrame.Angles(
				math.rad(math.random(-4, 4)),
				math.rad(math.random(-4, 4)), 0)
			task.wait(0.03)
		end
	end)

	-- flicker, hold black, clean up
	task.spawn(function()
		for i = 1, 10 do
			frame.BackgroundTransparency = (i % 2 == 0) and 0 or 0.6
			task.wait(0.05)
		end
		frame.BackgroundTransparency = 0
		task.wait(1.2)
		gui:Destroy()
	end)
end)
