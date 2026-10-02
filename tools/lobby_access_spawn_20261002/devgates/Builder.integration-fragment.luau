-- Root must merge these two insertions against its fresh authoritative Builder Source.
-- For the existing exact owned and Ready model branch, before `return existing`:
require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)

-- For a freshly built model, immediately after `model.Parent = workspace` and before `return model`:
require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(model)
