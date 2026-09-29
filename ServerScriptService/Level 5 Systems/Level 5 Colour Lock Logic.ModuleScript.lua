-- Pure validation shared by the server controller and CLI tests. No Roblox services.
local Logic = {}
Logic.Choices = {"RED", "YELLOW", "BLUE", "GREEN"}
Logic.Symbols = {"◯", "△", "□", "◇"}
Logic.Solution = {1, 2, 3, 4}
function Logic.ValidateSequence(sequence)
	if type(sequence) ~= "table" then return false end
	local count = 0
	for key, value in pairs(sequence) do
		count += 1
		if count > 4 or type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 4
			or type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > 4 then return false end
	end
	return count == 4
end
function Logic.Matches(sequence)
	if not Logic.ValidateSequence(sequence) then return false end
	for index = 1, 4 do if sequence[index] ~= Logic.Solution[index] then return false end end
	return true
end
function Logic.CanUse(state)
	return state.live == true and state.roundActive == true and state.level == 5
		and state.inRound == true and state.escaped ~= true and state.spectating ~= true
		and type(state.health) == "number" and state.health > 0
		and type(state.distance) == "number" and state.distance >= 0 and state.distance <= 14
		and state.lineOfSight == true
end
return Logic
