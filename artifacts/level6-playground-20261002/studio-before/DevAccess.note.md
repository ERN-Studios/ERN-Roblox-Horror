ReplicatedStorage.DevAccess, changed 2026-10-03: IsLevel6PreviewAllowed gained a Studio-only clause that admits
local test players (negative UserIds). Before the change the function body was:

    if DevAccess.IsAllowed(subject) then return true end
    if typeof(subject) == "Instance" and subject:IsA("Player") then
        return subject.UserId == 11374988579 -- ZenMeister02
    end
    return type(subject) == "number" and subject == 11374988579
