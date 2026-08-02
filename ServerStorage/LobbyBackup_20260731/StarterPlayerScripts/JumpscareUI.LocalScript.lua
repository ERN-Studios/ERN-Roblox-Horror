-- JumpscareUI
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "JumpscareUI"
--
-- The death sequence for the DYING player, in one place so it can't desync:
--   1. Entity kill → the entity's face SNAPS onto the whole screen and the scream
--      plays at the same instant (SoundController listens to the same Jumpscare
--      remote, so image + sound are always together — no lag, no double).
--   2. The scare fades to black.
--   3. Black is held for a couple of seconds (SpectateController has already moved
--      the camera to a teammate underneath).
--   4. Black fades out to reveal that teammate's POV.
-- Pit falls (no Jumpscare remote) skip the face/scream but still fade to black.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
local player = Players.LocalPlayer

-- the entity's face, shown full-screen the instant it kills you
local JUMPSCARE_IMAGE = "rbxassetid://85716983692957"

-- timing knobs
local FACE_HOLD  = 0.7   -- how long the face stays before it starts fading (entity kills)
local BLACK_FADE = 1.2   -- fade the scare down to full black
local BLACK_HOLD = 2.0   -- hold on black before revealing spectate ("a couple of seconds")
local REVEAL     = 0.6   -- fade the black out to show the teammate's POV
local DIED_GRACE = 0.4   -- on death, wait this long for the Jumpscare remote (entity kills)
-- before assuming it was a plain fall (so the face never arrives late)

local dying = false

local function runDeath(withFace)
	if dying then return end -- only one sequence per life (guards the remote+Died double)
	dying = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "JumpscareGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false -- we clean it up ourselves
	gui.DisplayOrder = 100   -- above the spectate HUD
	gui.Parent = player:WaitForChild("PlayerGui")

	local black = Instance.new("Frame")
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.ZIndex = 1
	black.Parent = gui

	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Crop
	img.Image = JUMPSCARE_IMAGE
	img.ImageTransparency = 1
	img.ZIndex = 2
	img.Parent = gui

	-- 1. entity kill: face snaps on (scream plays via SoundController on the same remote)
	if withFace and JUMPSCARE_IMAGE ~= "" then
		img.ImageTransparency = 0
		task.wait(FACE_HOLD)
	end

	-- 2. fade the scare to black
	TweenService:Create(black, TweenInfo.new(BLACK_FADE), { BackgroundTransparency = 0 }):Play()
	if withFace then
		TweenService:Create(img, TweenInfo.new(BLACK_FADE), { ImageTransparency = 1 }):Play()
	end
	task.wait(BLACK_FADE)
	black.BackgroundTransparency = 0
	img.ImageTransparency = 1

	-- 3. hold on black; SpectateController has already snapped the camera to a teammate
	task.wait(BLACK_HOLD)

	-- 4. reveal the teammate's POV
	TweenService:Create(black, TweenInfo.new(REVEAL), { BackgroundTransparency = 1 }):Play()
	task.wait(REVEAL)
	gui:Destroy()
end

-- entity kill → face + scream + fade
remote.OnClientEvent:Connect(function()
	runDeath(true)
end)

-- any death → make sure we fade to black even without the entity face (e.g. pit falls),
-- and reset for the next life on respawn
local function hookChar(char)
	dying = false
	local pg = player:FindFirstChild("PlayerGui")
	local old = pg and pg:FindFirstChild("JumpscareGui")
	if old then old:Destroy() end

	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function()
		task.wait(DIED_GRACE) -- give the Jumpscare remote a moment to land (entity kills)
		runDeath(false)       -- no-op if the entity-kill sequence already started
	end)
end

if player.Character then hookChar(player.Character) end
player.CharacterAdded:Connect(hookChar)
