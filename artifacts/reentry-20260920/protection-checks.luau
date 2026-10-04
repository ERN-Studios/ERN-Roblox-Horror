local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local function signal()
 local s={listeners={}}
 function s:Connect(fn) local c={Connected=true}; function c:Disconnect() self.Connected=false end; table.insert(self.listeners,{fn,c}); return c end
 function s:Fire(...) for _,r in ipairs(self.listeners) do if r[2].Connected then r[1](...) end end end
 return s
end
local function attrs(obj)
 obj.attributes={};obj.signals={}
 function obj:GetAttribute(k)return self.attributes[k]end
 function obj:GetAttributeChangedSignal(k) self.signals[k]=self.signals[k]or signal();return self.signals[k]end
 function obj:SetAttribute(k,v) local old=self.attributes[k];self.attributes[k]=v;if old~=v then self:GetAttributeChangedSignal(k):Fire()end end
 return obj
end
local now=100
local Workspace=attrs({});function Workspace:GetServerTimeNow()return now end
local Players={PlayerRemoving=signal()}
local RunService={IsServer=function()return true end}
local game={GetService=function(_,name)return ({Players=Players,Workspace=Workspace,RunService=RunService})[name]end}
local Instance={new=function() local s=signal();return{Event=s,Fire=function(_,...)s:Fire(...)end}end}
local typeof=function(v)return type(v)=="table" and v.IsA and "Instance" or type(v)end
local tasks={};local task={delay=function(delay,fn)table.insert(tasks,{at=now+delay,fn=fn})end}
local function advance(seconds)
 now+=seconds
 local due=tasks;tasks={}
 for _,t in ipairs(due)do if t.at<=now then t.fn()else table.insert(tasks,t)end end
end
local p=attrs({Parent=Players,CharacterAdded=signal(),CharacterRemoving=signal()})
function p:IsA(name)return name=="Player"end
local function life()
 local hum={Health=100,Died=signal()}
 local char={hum=hum,FindFirstChildOfClass=function(self)return self.hum end,IsDescendantOf=function()return true end}
 return char
end
Workspace:SetAttribute("RoundActive",true);p:SetAttribute("InRound",true);p.Character=life()
local Protection=(function()
--!strict
-- Shared server authority for Entity Shield and Emergency Re-entry grace.
-- Capture GetContext BEFORE a yielding inventory reservation, then Activate
-- with that exact context afterward. This module never charges or refunds.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
assert(RunService:IsServer(), "PlayerProtection must run on the server")

local Protection = {}
local DURATION = 5
local REENTRY_DURATION = 10
local states: {[Player]: any} = {}
local roundEpoch = 0
local activated = Instance.new("BindableEvent")
Protection.Activated = activated.Event

local function newEpoch()
	return table.freeze({})
end

local function validPlayer(player: Player): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

function Protection.Clear(player: Player)
	local state = states[player]
	if not state then return end
	state.Active = nil
	state.Epoch = newEpoch()
	player:SetAttribute("PlayerProtectionActive", false)
	player:SetAttribute("PlayerProtectionExpiresAt", 0)
	player:SetAttribute("PlayerProtectionSource", nil)
end

local function stateFor(player: Player)
	local state = states[player]
	if state then return state end
	state = {Epoch=newEpoch(), Active=nil, Character=nil, Humanoid=nil, Connections={}}
	states[player] = state
	local function invalidate()
		if states[player] == state then Protection.Clear(player) end
	end
	for _, name in ipairs({"InRound", "Escaped", "Level2_ExitTransition"}) do
		table.insert(state.Connections, player:GetAttributeChangedSignal(name):Connect(invalidate))
	end
	-- Character events may be delivered after LoadCharacterAsync returns. A
	-- delayed event for the previous body must never clear the new life's grace.
	table.insert(state.Connections, player.CharacterAdded:Connect(function(character)
		if player.Character == character and state.Character ~= character then invalidate() end
	end))
	table.insert(state.Connections, player.CharacterRemoving:Connect(function(character)
		if state.Character == character then invalidate() end
	end))
	Protection.Clear(player)
	return state
end

local function currentLife(player: Player, state: any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if state.Character ~= character or state.Humanoid ~= humanoid then
		Protection.Clear(player)
		if state.DeathConnection then state.DeathConnection:Disconnect() end
		state.Character = character
		state.Humanoid = humanoid
		state.DeathConnection = humanoid and humanoid.Died:Connect(function()
			if states[player] == state and state.Humanoid == humanoid then
				Protection.Clear(player)
			end
		end) or nil
	end
	return character, humanoid
end

local function eligibility(player: Player, character: Model?, humanoid: Humanoid?): string?
	if Workspace:GetAttribute("RoundActive") ~= true then return "RoundInactive" end
	if player:GetAttribute("InRound") ~= true then return "NotInRound" end
	if player:GetAttribute("Escaped") == true
		or player:GetAttribute("Level2_ExitTransition") == true then return "Exited" end
	if not character or not character:IsDescendantOf(Workspace) or not humanoid then
		return "CharacterUnavailable"
	end
	if humanoid.Health <= 0 then return "Dead" end
	return nil
end

function Protection.IsActive(player: Player, character: Model?): boolean
	if not validPlayer(player) then return false end
	local state = states[player]
	if not state or not state.Active then return false end
	local active = state.Active
	local currentCharacter, humanoid = currentLife(player, state)
	if active ~= state.Active or active.Character ~= currentCharacter
		or active.Epoch ~= state.Epoch or active.RoundEpoch ~= roundEpoch
		or eligibility(player, currentCharacter, humanoid)
		or Workspace:GetServerTimeNow() >= active.ExpiresAt then
		Protection.Clear(player)
		return false
	end
	-- A caller holding an older character cannot borrow the new one's effect.
	return character == nil or character == currentCharacter
end

function Protection.GetContext(player: Player): (any?, string?)
	if not validPlayer(player) then return nil, "InvalidPlayer" end
	local state = stateFor(player)
	local character, humanoid = currentLife(player, state)
	if Protection.IsActive(player, character) then return nil, "AlreadyActive" end
	local problem = eligibility(player, character, humanoid)
	if problem then return nil, problem end
	return table.freeze({Character=character, Epoch=state.Epoch, RoundEpoch=roundEpoch}), nil
end

local function activate(player: Player, context: any, duration: number, source: string): (boolean, any)
	if not validPlayer(player) then return false, "InvalidPlayer" end
	local state = states[player]
	if not state or type(context) ~= "table" then return false, "InvalidContext" end
	local character, humanoid = currentLife(player, state)
	-- Expiry cleanup can replace the epoch; do it before comparing the context.
	if Protection.IsActive(player, character)
		and not (source == "Reentry" and state.Active.Source == "Reentry") then
		return false, "AlreadyActive"
	end
	if context.Character ~= character or context.Epoch ~= state.Epoch
		or context.RoundEpoch ~= roundEpoch then return false, "StaleContext" end
	local problem = eligibility(player, character, humanoid)
	if problem then return false, problem end
	local active = {
		Character=character, Epoch=state.Epoch, RoundEpoch=roundEpoch,
		ExpiresAt=Workspace:GetServerTimeNow() + duration, Source=source,
	}
	state.Active = active
	player:SetAttribute("PlayerProtectionSource", source)
	player:SetAttribute("PlayerProtectionActive", true)
	player:SetAttribute("PlayerProtectionExpiresAt", active.ExpiresAt)
	local function expire()
		if states[player] ~= state or state.Active ~= active then return end
		local remaining = active.ExpiresAt - Workspace:GetServerTimeNow()
		if remaining > 0 then
			task.delay(remaining, expire)
		else
			Protection.Clear(player)
		end
	end
	task.delay(duration, expire)
	activated:Fire(player, character, active.ExpiresAt)
	return true, active.ExpiresAt
end

function Protection.Activate(player: Player, context: any): (boolean, any)
	return activate(player, context, DURATION, "Shield")
end

-- Server-only; the same life token can renew re-entry once placement finishes.
-- Old expiry callbacks cannot clear the replacement effect. Paid shields cannot
-- stack with grace and never inherit its ten-second duration.
function Protection.ActivateReentry(player: Player, context: any): (boolean, any)
	return activate(player, context, REENTRY_DURATION, "Reentry")
end

local function roundChanged()
	-- RoundActive changes fence consecutive rounds even when SelectedLevel is
	-- unchanged. Also observe a direct level change as an invalidation boundary.
	roundEpoch += 1
	for player in pairs(states) do Protection.Clear(player) end
end
Workspace:GetAttributeChangedSignal("RoundActive"):Connect(roundChanged)
Workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(roundChanged)
Players.PlayerRemoving:Connect(function(player)
	local state = states[player]
	if not state then return end
	Protection.Clear(player)
	for _, connection in ipairs(state.Connections) do connection:Disconnect() end
	if state.DeathConnection then state.DeathConnection:Disconnect() end
	states[player] = nil
end)

return table.freeze(Protection)

end)()
local ctx=Protection.GetContext(p)
local ok,expires=Protection.Activate(p,ctx)
check(ok and expires==105,"Shield stays five seconds")
check(not Protection.ActivateReentry(p,ctx),"Cannot renew a paid shield as reentry")
advance(5);check(not Protection.IsActive(p),"Shield expires")
ctx=Protection.GetContext(p);ok,expires=Protection.ActivateReentry(p,ctx)
check(ok and expires==115 and p:GetAttribute("PlayerProtectionSource")=="Reentry","Ten-second grace")
check(Protection.GetContext(p)==nil,"Cannot reserve a shield during grace")
check(not Protection.Activate(p,ctx),"Cannot stack shield during grace")
advance(3);ok,expires=Protection.ActivateReentry(p,ctx)
check(ok and expires==118,"Full ten seconds after streaming")
advance(7);check(Protection.IsActive(p),"Old expiry cannot clear renewal")
advance(3);check(not Protection.IsActive(p),"Renewed effect expires")
local old=p.Character;p.Character=life();ctx=Protection.GetContext(p)
check(Protection.ActivateReentry(p,ctx),"New life activates")
p.CharacterRemoving:Fire(old);p.CharacterAdded:Fire(old);p.CharacterAdded:Fire(p.Character)
check(Protection.IsActive(p),"Delayed old-character events preserve new grace")
check(not Protection.IsActive(p,old),"Old character cannot borrow immunity")
p.Character.hum.Health=0;p.Character.hum.Died:Fire()
check(not Protection.IsActive(p),"Death clears grace")
p.Character=life();ctx=Protection.GetContext(p);check(Protection.ActivateReentry(p,ctx),"Next life activates")
p:SetAttribute("Escaped",true);check(not Protection.IsActive(p),"Escape clears grace")
p:SetAttribute("Escaped",nil);ctx=Protection.GetContext(p)
Workspace:SetAttribute("RoundActive",false);Workspace:SetAttribute("RoundActive",true)
check(not Protection.ActivateReentry(p,ctx),"Stale round cannot activate")
ctx=Protection.GetContext(p);Protection.ActivateReentry(p,ctx)
Workspace:SetAttribute("SelectedLevel",2);check(not Protection.IsActive(p),"Level change clears grace")
ctx=Protection.GetContext(p);Protection.ActivateReentry(p,ctx);Players.PlayerRemoving:Fire(p)
check(p:GetAttribute("PlayerProtectionSource")==nil and not Protection.IsActive(p),"Disconnect clears state")
print(tostring(checks).." production-module protection checks passed")
