-- One shared whitelist for every client and server developer command.
-- UserIds are permanent; usernames can change and should never be an authority boundary.
local DevAccess = {}

local ALLOWED_USER_IDS = {
	[40920547] = true,   -- mikkelczar
	[9488575949] = true, -- LaverSneglen
}

-- Timeline seeking is intentionally narrower than the shared developer tools.
local LEVEL3_TIMELINE_OWNER_USER_ID = 9488575949 -- LaverSneglen

function DevAccess.IsAllowed(subject)
	local userId
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		userId = subject.UserId
	elseif type(subject) == "number" then
		userId = subject
	end
	return userId ~= nil and ALLOWED_USER_IDS[userId] == true
end

-- Preview access is narrower than the general developer commands.
function DevAccess.IsLevel6PreviewAllowed(subject)
	if DevAccess.IsAllowed(subject) then return true end
	-- Studio "Server & Clients" test players have negative UserIds (Player1 = -1, ...). They only exist in a
	-- local Studio test, never on a live server, so letting them in is what makes a multiplayer preview testable.
	if game:GetService("RunService"):IsStudio() then
		local id = if typeof(subject) == "Instance" and subject:IsA("Player") then subject.UserId else subject
		if type(id) == "number" and id < 0 then return true end
	end
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		return subject.UserId == 11374988579 -- ZenMeister02
	end
	return type(subject) == "number" and subject == 11374988579
end

-- Level 6 (Indoor Playground) is open to every player since 2026-10-03.
DevAccess.Level6Public = true
function DevAccess.IsLevel6Allowed(subject)
	return DevAccess.Level6Public == true or DevAccess.IsLevel6PreviewAllowed(subject)
end

-- Levels 4 and 5 are open to every player since 2026-10-04 (owner: "make sure all levels are accessible for
-- the public now"). The developer commands still go through the allowlist above.
DevAccess.Level4Public = true
DevAccess.Level5Public = true
function DevAccess.IsLevel4Allowed(subject)
	return DevAccess.Level4Public == true or DevAccess.IsAllowed(subject)
end
function DevAccess.IsLevel5Allowed(subject)
	return DevAccess.Level5Public == true or DevAccess.IsLevel6PreviewAllowed(subject)
end

function DevAccess.IsLevel3TimelineOwner(subject)
	local userId
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		userId = subject.UserId
	elseif type(subject) == "number" then
		userId = subject
	end
	return userId == LEVEL3_TIMELINE_OWNER_USER_ID
end

return DevAccess
