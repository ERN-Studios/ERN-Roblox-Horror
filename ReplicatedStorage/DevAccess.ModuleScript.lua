-- One shared whitelist for every client and server developer command.
-- UserIds are permanent; usernames can change and should never be an authority boundary.
local DevAccess = {}

local ALLOWED_USER_IDS = {
	[40920547] = true,   -- mikkelczar
	[9488575949] = true, -- LaverSneglen
	[833029598] = true,  -- Detective_Costeau
}

function DevAccess.IsAllowed(subject)
	local userId
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		userId = subject.UserId
	elseif type(subject) == "number" then
		userId = subject
	end
	return userId ~= nil and ALLOWED_USER_IDS[userId] == true
end

return DevAccess
