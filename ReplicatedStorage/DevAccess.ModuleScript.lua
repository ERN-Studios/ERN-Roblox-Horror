-- One shared whitelist for every client and server developer command.
local DevAccess = {}

local ALLOWED_NAMES = {
	mikkelczar = true,
	LaverSneglen = true,
	Detective_Costeau = true,
}

function DevAccess.IsAllowed(subject)
	local name = typeof(subject) == "Instance" and subject.Name or subject
	return type(name) == "string" and ALLOWED_NAMES[name] == true
end

return DevAccess
