-- Root must stage this only in a fresh empty ModuleScript; never clone a LuaSourceContainer.
-- Supply the freshly staged budget module return value. Synthetic objects only.
return function(Budget)
	local checks = 0
	local function check(condition, message) checks += 1; assert(condition, message) end
	local world = Instance.new("Model")
	world.Name = "_SceneEffectBudgetContractProbe"
	local budget
	local createdMounts = {}
	local function lightAt(position, wanted)
		local part = Instance.new("Part")
		table.insert(createdMounts, part)
		part.Name = "ProbeMount"; part.Anchored = true; part.Size = Vector3.one
		part.Position = position; part.Parent = world
		local light = Instance.new("PointLight")
		light.Name = "ProbeLight"; light.Range = 20; light.Brightness = 0.5
		light.Enabled = wanted; light:SetAttribute("SceneBudgetWantedEnabled", wanted)
		light.Parent = part
		return light, part
	end
	local ok, problem = xpcall(function()
		local light, mount = lightAt(Vector3.zero, true)
		local originallyDisabled = lightAt(Vector3.zero, false)
		local ignored = Instance.new("PointLight"); ignored.Parent = mount; ignored.Enabled = true
		budget = Budget.new(world, {ActiveDistance = 128, Hysteresis = 32, CellSize = 128,
			MaxInfluence = 120, PendingLimit = 8})
		budget:Step({Vector3.zero})
		check(light.Enabled and not originallyDisabled.Enabled and ignored.Enabled, "Initial/untagged states")
		budget:Step({Vector3.new(179, 0, 0)}); check(light.Enabled, "Exit hysteresis")
		budget:Step({Vector3.new(181, 0, 0)}); check(not light.Enabled, "Distant suppression")
		light.Enabled = true; task.wait()
		check(not light.Enabled, "Repeated server Enabled=true is locally repaired")
		budget:Step({Vector3.new(160, 0, 0)}); check(not light.Enabled, "Entry hysteresis")
		-- Enabled=false already: only the independent authoritative attribute exposes the blackout.
		light.Enabled = false; light:SetAttribute("SceneBudgetWantedEnabled", false)
		task.wait()
		budget:Step({Vector3.zero}); check(not light.Enabled, "Same-value blackout")
		light:SetAttribute("SceneBudgetWantedEnabled", true); task.wait()
		budget:Step({Vector3.zero}); check(light.Enabled, "Authoritative power-up")
		light.Brightness = 0; light.Color = Color3.fromRGB(255, 40, 28)
		budget:Step({Vector3.new(1000, 0, 0)}); budget:Step({Vector3.zero})
		check(light.Brightness == 0 and light.Color == Color3.fromRGB(255, 40, 28), "Flicker/finale preserved")
		local streamed, holder = lightAt(Vector3.new(1000, 0, 0), true)
		task.wait(); budget:Step({Vector3.zero}); check(not streamed.Enabled, "Late stream-in")
		holder.Parent = nil
		task.wait(); check(streamed.Enabled, "Stream-out releases suppression")
		holder.Parent = world
		task.wait(); budget:Step({Vector3.new(1000, 0, 0)}); check(streamed.Enabled, "Re-entry")
		mount.Position = Vector3.new(2000, 0, 0)
		task.wait(); budget:Step({Vector3.zero}); check(not light.Enabled, "Moving mount reindexed")
		light:SetAttribute("SceneBudgetWantedEnabled", false); task.wait()
		budget:Destroy()
		check(not light.Enabled and streamed.Enabled and not originallyDisabled.Enabled and ignored.Enabled,
			"Cleanup follows current authority, without re-enabling darkness")
		check(budget:Stats().Tracked == 0 and budget:Stats().Sectors == 0, "Indices emptied")
	end, debug.traceback)
	-- Always clean up even after an assertion/callback error.
	if budget then pcall(function() budget:Destroy() end) end
	for _, mount in ipairs(createdMounts) do pcall(function() mount:Destroy() end) end
	world:Destroy()
	if not ok then error(problem, 0) end
	return {Passed = true, Checks = checks, Type = "Synthetic native effect contract"}
end
