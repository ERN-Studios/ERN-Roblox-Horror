-- DanceEmote
-- Press G to toggle a looping dance. Cancels automatically when the player
-- moves, jumps, or dies, so it can never fight the locomotion animations.
-- Lobby-only: in a round G belongs to the glowstick drop (NoiseReporter).

local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

local DANCE_ID = "rbxassetid://108616760278872"
local DANCE_KEY = Enum.KeyCode.G

local char = script.Parent
local hum = char:WaitForChild("Humanoid")
local animator = hum:WaitForChild("Animator")

local anim = Instance.new("Animation")
anim.AnimationId = DANCE_ID

local track = animator:LoadAnimation(anim)
track.Priority = Enum.AnimationPriority.Action
track.Looped = true

local function stopDance()
	if track.IsPlaying then
		track:Stop(0.2)
	end
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= DANCE_KEY then return end
	if Players.LocalPlayer:GetAttribute("InRound") == true then return end
	if hum.Health <= 0 then return end

	if track.IsPlaying then
		stopDance()
	else
		-- Don't start mid-stride; the dance is a standing emote.
		if hum.MoveDirection.Magnitude > 0.1 then return end
		track:Play(0.2)
	end
end)

-- Any real movement cancels it.
hum.Running:Connect(function(speed)
	if speed > 0.1 then stopDance() end
end)
hum.Jumping:Connect(stopDance)
hum.Died:Connect(stopDance)
hum.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Freefall or new == Enum.HumanoidStateType.Landed then
		stopDance()
	end
end)
