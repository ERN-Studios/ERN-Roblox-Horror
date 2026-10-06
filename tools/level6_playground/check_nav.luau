-- Walk every link of the Counter's graph against the real parts (Edit mode, or a play session's Server):
-- nothing solid across it at shin, chest and head height, floor under it, room over it.
--   python3 tools/level6_playground/run_luau.py tools/level6_playground/check_nav.luau
local model = workspace["Level 6 Indoor Playground"]
local origin = model:GetAttribute("Origin")
local folder = model.NavGraph
local pieces = {}
for i = 1, folder:GetAttribute("Parts") do pieces[i] = folder[string.format("Part_%02d", i)].Value end
local data = game:GetService("HttpService"):JSONDecode(table.concat(pieces))
local nodes = {}
for i = 1, #data.nodes, 3 do nodes[#nodes + 1] = origin + Vector3.new(data.nodes[i], data.nodes[i + 1], data.nodes[i + 2]) / 10 end
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = {model}
params.RespectCanCollide = true
local blocked, noFloor, lowRoof, where = {}, {}, {}, {}
local blockedCount, floorCount, roofCount, segments = 0, 0, 0, 0
local function owner(inst) return inst.Parent and inst.Parent.Name or "?" end
for index, e in ipairs(data.edges) do
	local pts = {nodes[e[1] + 1]}
	for i = 3, #e, 3 do pts[#pts + 1] = origin + Vector3.new(e[i], e[i + 1], e[i + 2]) / 10 end
	pts[#pts + 1] = nodes[e[2] + 1]
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local d = b - a
		if d.Magnitude > 0.05 then
			segments += 1
			local sloped = math.abs(d.Y) > 1
			for _, h in ipairs(sloped and {4.6, 7.6} or {1.2, 4.6, 7.6}) do
				local hit = workspace:Raycast(a + Vector3.new(0, h, 0), d, params)
				if hit then
					blockedCount += 1
					local key = owner(hit.Instance) .. "/" .. hit.Instance.Name
					blocked[key] = (blocked[key] or 0) + 1
					if #where < 10 then
						local rel = hit.Position - origin
						table.insert(where, string.format("[edge %d seg %d h%.1f %s (%.0f,%.0f,%.0f)]", index, i, h, key, rel.X, rel.Y, rel.Z))
					end
					break
				end
			end
			local steps = math.max(1, math.floor(d.Magnitude / 1.5))     -- close enough together to find a stairwell's hole
			for s = 0, steps do
				local at = a + d * (s / steps)
				if not workspace:Raycast(at + Vector3.new(0, 3, 0), Vector3.new(0, -7, 0), params) then
					floorCount += 1
					if floorCount <= 8 then
						local rel = at - origin
						table.insert(noFloor, string.format("edge %d (%.0f,%.0f,%.0f)", index, rel.X, rel.Y, rel.Z))
					end
				end
				local up = workspace:Raycast(at + Vector3.new(0, 1.2, 0), Vector3.new(0, 7.0, 0), params)
				if up and not sloped then
					roofCount += 1
					local key = owner(up.Instance) .. "/" .. up.Instance.Name
					lowRoof[key] = (lowRoof[key] or 0) + 1
				end
			end
		end
	end
end
local function dump(t)
	local s = {}
	for k, v in pairs(t) do s[#s + 1] = tostring(k) .. "=" .. tostring(v) end
	table.sort(s)
	return table.concat(s, "; ")
end
return string.format("%d edges, %d segments\nblocked %d: %s\n%s\nno floor %d: %s\nlow roof %d: %s", #data.edges, segments, blockedCount,
	dump(blocked), table.concat(where, " "), floorCount, table.concat(noFloor, "; "), roofCount, dump(lowRoof))
