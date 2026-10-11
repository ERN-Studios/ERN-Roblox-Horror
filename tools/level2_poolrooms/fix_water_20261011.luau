-- L2_WATER_FIX_20261011. Run ONCE in Studio, Edit mode (the Level 2 map's Terrain water lives in the place itself;
-- no round ever rewrites it). Owner: "I level 2 er der vand i loftet naar man gaar ned af trapperne til sektion 2"
-- and "Water is also clipping in some of the pits in sektion 2".
--
-- What was wrong. The map's water is two big slabs of Terrain water (model attribute L2NTerrainRegions): one under
-- the first hall (A1, y 224..232), one under the pit hall (A3, y 164..176). Each hall's floor hides its slab; only a
-- thin film stands over the floor.
--   1. The stair down to the pit hall (P1) runs in a closed concrete tunnel UNDER the first hall's floor. The slab was
--      never taken out of the tunnel, so its water hung across the tunnel's top for the first 50 studs of the stair.
--   2. Four of the five pit shafts (thin 0.7-stud walls) had the slab's water closer than 2.4 studs to their inner
--      faces, and Terrain water bulges that far: it showed inside the shafts.
--
-- What Terrain water does (measured in Play, 2026-10-11): a water cell is drawn as a sheet centred on the grid plane
-- under it, about 8 x occupancy thick; a full column hangs 4 studs below its lowest cell; a column bordering Air is
-- drawn low. So a film that must stay ABOVE a floor with nothing under it is a thin sheet in the row above
-- (occupancy 0.06 at row 232..236: 231.8..232.2), and it has to overlap the ordinary water around it by two cells
-- or its edge shows as a bright dry band.
local terrain = workspace.Terrain
local CHS = game:GetService("ChangeHistoryService")
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local marker = "L2WaterFix20261011"
if terrain:GetAttribute(marker) == true then return "already applied" end
CHS:SetWaypoint("Before " .. marker)

local function air(x0, x1, y0, y1, z0, z1)
	terrain:FillBlock(CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), Vector3.new(x1 - x0, y1 - y0, z1 - z0), Enum.Material.Air)
end
local function count(x0, x1, y0, y1, z0, z1)
	local region = Region3.new(Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)):ExpandToGrid(4)
	local mats, occ = terrain:ReadVoxels(region, 4)
	local n = 0
	for x = 1, mats.Size.X do for y = 1, mats.Size.Y do for z = 1, mats.Size.Z do
		if mats[x][y][z] == Enum.Material.Water and occ[x][y][z] > 0 then n += 1 end
	end end end
	return n
end

-- 1. the P1 stair tunnel: no water under the first hall's floor over the tunnel's upper end ...
local before = count(69264, 69324, 200, 232, 256, 288)
air(69264, 69324, 200, 232, 256, 288)
-- ... and the hall's film put back above the floor: from under the stair-top platform (it reaches x 69276) and two
-- cells past the cleared ground on the three open sides
do
	local region = Region3.new(Vector3.new(69272, 232, 248), Vector3.new(69332, 236, 296)):ExpandToGrid(4)
	local mats, occ = terrain:ReadVoxels(region, 4)
	for x = 1, mats.Size.X do for y = 1, mats.Size.Y do for z = 1, mats.Size.Z do
		mats[x][y][z] = Enum.Material.Water
		occ[x][y][z] = 0.06
	end end end
	terrain:WriteVoxels(region, 4, mats, occ)
end

-- 2. the pit shafts the slab reached into: the shaft plus 3 studs each way, which stays inside the 4.2-stud curb
local pits = {
	{69805.5, 69822.7, 300.0, 312.0, 3.0},
	{69597.9, 69618.5, 228.8, 246.0, 3.0},
	{69703.0, 69719.3, 332.2, 348.5, 3.0},
	{69772.9, 69786.6, 192.8, 213.4, 3.3},
}
local pitBefore = 0
for _, p in ipairs(pits) do
	pitBefore += count(p[1], p[2], 160, 176, p[3], p[4])
	air(p[1] - p[5], p[2] + p[5], 158, 180, p[3] - p[5], p[4] + p[5])
end
terrain:SetAttribute(marker, true)
CHS:SetWaypoint(marker)
return string.format("applied: %d water cells were in the tunnel's ground, now %d; %d were inside the four shafts' footprints, now %d",
	before, count(69264, 69324, 200, 232, 256, 288), pitBefore, (function() local n = 0 for _, p in ipairs(pits) do n += count(p[1], p[2], 160, 176, p[3], p[4]) end return n end)())
