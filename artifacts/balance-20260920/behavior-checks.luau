local checks=0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b));checks+=1 end
local Config={Passes={AdvancedEquipment={StaminaBonus=.5}},TokenPercentPerLevel=.05}
local attrs={};local player={UserId=9488575949,GetAttribute=function(_,k)return attrs[k]end,SetAttribute=function(_,k,v)attrs[k]=v end}
local passPurchases,passReadFailed={},{}
local ownsPass=function()return false end
local function advancedStaminaBonus(player)
	return player and player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true
		and Config.Passes.AdvancedEquipment.StaminaBonus or 0
end

local function passOwnership(player, key, pass)
	-- Owner-authorized permanent in-experience entitlement. Does not grant other passes.
	if key == "AdvancedEquipment" and player.UserId == 9488575949 then return true end -- LaverSneglen
	local purchases = passPurchases[player]
	if purchases and purchases[key] then return true end
	local answer = ownsPass(player, pass)
	if answer == nil then
		passReadFailed[player] = true
		-- Unknown: keep whatever this session already published rather than
		-- downgrading an owner to false.
		return player:GetAttribute("ZyntraOwns" .. key) == true
	end
	return answer
end

eq(passOwnership(player,"AdvancedEquipment",{}),true)
eq(passOwnership(player,"Supporter",{}),false)
player.UserId=123;eq(passOwnership(player,"AdvancedEquipment",{}),false)
ownsPass=function()return true end;eq(passOwnership(player,"AdvancedEquipment",{}),true)
local step=.05
for _,level in ipairs({0,1,9,25}) do
 local data={StaminaLevel=level}
 for _,owned in ipairs({false,true}) do
  attrs.ZyntraOwnsAdvancedEquipment=owned
	player:SetAttribute("ZyntraStaminaMultiplier", 1 + data.StaminaLevel * step + advancedStaminaBonus(player))
	player:SetAttribute("ZyntraStaminaMultiplier", 1 + data.StaminaLevel * step + advancedStaminaBonus(player))
  eq(attrs.ZyntraStaminaMultiplier,1+level*.05+(owned and .5 or 0))
  eq(data.StaminaLevel,level)
 end
end
local Players={};local party={};function Players:GetPlayers()return party end
for count=1,6 do
 party={}
 for i=1,count do party[#party+1]={GetAttribute=function()return true end} end
 party[#party+1]={GetAttribute=function()return false end}
	local roundPlayers, roundPlayerSet = {}, {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") == true then
			roundPlayers[#roundPlayers + 1] = player
			roundPlayerSet[player] = true
		end
	end
	local n = math.clamp(#roundPlayers, 1, 6)
	local boxCount = math.ceil(n / 2) -- 1–2 players: 1 pair; 3–4: 2; 5–6: 3
 eq(boxCount,({1,1,2,2,3,3})[count])
 eq(#roundPlayers,count)
end
local allow=true;local canUsePrompt=function()return allow end
local setLeverHandle=function(l,v)l.handle=v end
local updateEntityObjectiveTarget=function()end
local announcements,exits,scheduled=0,0,0
local announceTeam=function()announcements+=1 end
local task={delay=function()scheduled+=1 end}
local session={active=true,stage="levers",levers={},onLevers=function()exits+=1 end}
local lever
local function pull(player)
			if not session or not session.active or session.stage ~= "levers" then return end
			-- Same contract as the relays: only a living, present member of the
			-- launched party may drive the exit circuit.
			if not canUsePrompt(player, lever.prompt, lever.model) then return end
			if lever.latched then return end
			if lever.pullSound then lever.pullSound:Play() end
			lever.latched = true
			lever.prompt.Enabled = false
			setLeverHandle(lever, true)
			updateEntityObjectiveTarget()
			if session.updateLeverLights then session.updateLeverLights() end
			if session.broadcastLeverStatus then session.broadcastLeverStatus() end

			local on = 0
			for _, lv in ipairs(session.levers) do
				if lv.latched then on += 1 end
			end
			announceTeam(player.Name, "lever",
				("PULLED LEVER %d/%d"):format(on, #session.levers))
			if on == #session.levers then session.onLevers(lever.cf.Position) end
end
for i=1,3 do session.levers[i]={latched=false,prompt={Enabled=true},cf={Position=0}} end
lever=session.levers[1];allow=false;pull(player);eq(lever.latched,false)
allow=true;pull(player);eq(lever.latched,true);eq(lever.prompt.Enabled,false);eq(exits,0)
pull(player);eq(announcements,1);eq(scheduled,0)
lever=session.levers[2];pull(player);eq(exits,0)
lever=session.levers[3];pull(player);eq(exits,1);eq(announcements,3)
eq(session.levers[1].latched,true);eq(scheduled,0)
local chaseActive=function()return true end
local SPOT_SOUND="asset";local SPOT_VOLUME=.96;local lastSpotScreamAt=-math.huge
local SoundService={};local soundCount=0;local Instance={}
function Instance.new(kind)
 soundCount+=1
 return {Play=function(self)eq(self.Parent,SoundService);eq(self.Volume,.96)end,Ended={Connect=function()end},Destroy=function()end}
end
local hp={Health=100};player.Character={FindFirstChildOfClass=function()return hp end}
local function playEntitySpotScream()
	if not chaseActive() or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	if SPOT_SOUND == "" or (os.clock() - lastSpotScreamAt) < 4 then return false end
	lastSpotScreamAt = os.clock()
	local sound = Instance.new("Sound")
	sound.Name = "SpotScream"
	sound.SoundId = SPOT_SOUND
	sound.Volume = SPOT_VOLUME
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function() sound:Destroy() end)
	task.delay(12, function() sound:Destroy() end)
	return true
end

attrs.InRound=false;eq(playEntitySpotScream(),false);eq(soundCount,0)
attrs.InRound=true;attrs.Escaped=true;eq(playEntitySpotScream(),false)
attrs.Escaped=false;hp.Health=0;eq(playEntitySpotScream(),false)
hp.Health=100;eq(playEntitySpotScream(),true);eq(soundCount,1)
eq(playEntitySpotScream(),false);eq(soundCount,1)
print("PASS",checks,"behavior checks: entitlement, additive stamina without repeated grants, 1–6 player scaling, persistent/idempotent lever pulls, targeted warning eligibility")
