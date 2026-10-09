-- ROOT-OPERATED probe only. No authoritative object is moved or destroyed.
-- Stage in a fresh empty ModuleScript; verify all original Source/editor pairs.
-- Uses individual non-script Part clones and fresh proxies in test-owned WorldModels.
return function(plan, geometry)
	geometry.AssertPlan(plan)
	local SS, RS = game:GetService("ServerStorage"), game:GetService("RunService")
	local root = Instance.new("Folder")
	root.Name = "OptimizationCollisionProbe_" .. game:GetService("HttpService"):GenerateGUID(false)
	root.Parent = SS
	local results = {groups = 0, rays = 0, overlaps = 0, maxHitPositionDifference = 0,
		maxHitDistanceDifference = 0, authoritativeOriginalsUnchanged = false,
		queryPositionToleranceStuds = .01, queryDistanceToleranceStuds = .01,
		exactNativeProxyBounds = true, gameplayVerified = false, performanceVerified = false}
	local function vector(a) return Vector3.new(a[1], a[2], a[3]) end
	local ok, problem = xpcall(function()
		for index, row in ipairs(plan.Merges) do
			assert(not RS:IsRunning(), "Owner entered Play; abort and clean probe objects")
			local before, after = Instance.new("WorldModel"), Instance.new("WorldModel")
			before.Name, after.Name = "Before " .. index, "After " .. index
			before.Parent, after.Parent = root, root
			for _, original in ipairs(row.Before) do
				local part = original.Instance
				assert(part:IsA("Part") and #part:GetChildren() == 0, "Only childless non-script Parts may be cloned")
				local copy = part:Clone()
				assert(copy and copy:IsA("Part") and #copy:GetChildren() == 0)
				copy.Parent = before
			end
			-- Use exactly the fresh-Part factory used by Apply, including its complete
			-- native property/attribute readback comparison.
			local proxy = geometry.CreateProxy(row)
			proxy.Parent = after
			-- Native property setters must read back the exact eligible float values.
			local c, expected = {proxy.CFrame:GetComponents()}, {row.CFrame:GetComponents()}
			for i = 1, 12 do assert(c[i] == expected[i], "Native proxy CFrame readback differs") end
			assert(proxy.Size == row.Size, "Native proxy Size readback differs")
			local raysA, raysB = RaycastParams.new(), RaycastParams.new()
			raysA.FilterType, raysB.FilterType = Enum.RaycastFilterType.Include, Enum.RaycastFilterType.Include
			raysA.FilterDescendantsInstances, raysB.FilterDescendantsInstances = {before}, {after}
			raysA.IgnoreWater, raysB.IgnoreWater = true, true
			raysA.RespectCanCollide, raysB.RespectCanCollide = true, true
			local center, extent = row.Bounds.Center, row.Bounds.Extent
			for axis = 1, 3 do
				local others = {}; for a = 1, 3 do if a ~= axis then table.insert(others, a) end end
				for _, side in ipairs({-1, 1}) do
					for _, u in ipairs({-.25, 0, .25}) do for _, v in ipairs({-.25, 0, .25}) do
						local origin, direction = table.clone(center), {0, 0, 0}
						origin[axis] += side*(extent[axis]/2 + 2)
						origin[others[1]] += extent[others[1]]*u
						origin[others[2]] += extent[others[2]]*v
						direction[axis] = -side*(extent[axis] + 4)
						local a = before:Raycast(vector(origin), vector(direction), raysA)
						local b = after:Raycast(vector(origin), vector(direction), raysB)
						assert(a and b, "Actual collider WorldModel ray missed: group " .. index)
						local positionError, distanceError = (a.Position - b.Position).Magnitude, math.abs(a.Distance - b.Distance)
						results.maxHitPositionDifference = math.max(results.maxHitPositionDifference, positionError)
						results.maxHitDistanceDifference = math.max(results.maxHitDistanceDifference, distanceError)
						assert(positionError <= .01 and distanceError <= .01 and (a.Normal - b.Normal).Magnitude <= .00001,
							"Native actual collider ray differs: group " .. index)
						assert(a.Instance.Name == b.Instance.Name and a.Instance:GetAttribute("Area") == b.Instance:GetAttribute("Area"),
							"Native query semantic Name/Area changed")
						results.rays += 1
					end end
				end
			end
			local overlapA, overlapB = OverlapParams.new(), OverlapParams.new()
			overlapA.FilterType, overlapB.FilterType = Enum.RaycastFilterType.Include, Enum.RaycastFilterType.Include
			overlapA.FilterDescendantsInstances, overlapB.FilterDescendantsInstances = {before}, {after}
			overlapA.MaxParts, overlapB.MaxParts = 1, 1
			overlapA.RespectCanCollide, overlapB.RespectCanCollide = true, true
			for axis = 1, 3 do
				for _, t in ipairs({-.6, -.25, 0, .25, .6}) do
					local point = table.clone(center); point[axis] += extent[axis]*t
					local cf = CFrame.new(vector(point))
					local size = Vector3.new(.02, .02, .02)
					local a = #before:GetPartBoundsInBox(cf, size, overlapA) > 0
					local b = #after:GetPartBoundsInBox(cf, size, overlapB) > 0
					assert(a == b, "Native actual collider overlap differs: group " .. index)
					results.overlaps += 1
				end
			end
			results.groups += 1
			before:Destroy(); after:Destroy() -- test-owned non-script clones/proxies only
			if index % 10 == 0 then task.wait() end
		end
		geometry.AssertPlan(plan)
		results.authoritativeOriginalsUnchanged = true
	end, debug.traceback)
	root:Destroy() -- complete cleanup even if a ray/overlap/assertion throws
	if not ok then error(problem) end
	results.testObjectsCleaned = true
	return results
end
