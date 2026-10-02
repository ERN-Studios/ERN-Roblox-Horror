-- Bounded exact-source compilation and ceiling aperture math; not a Level1 Play claim.
local fs, luau, serde = require("@lune/fs"), require("@lune/luau"), require("@lune/serde")
local r = require("@lune/roblox")
local ROOT = "artifacts/lobby-access-spawn-20261002/devgate-audit/"
local mazeSource = fs.readFile(ROOT .. "MazeGenerator.concurrent-after.luau")
local rendererSource = fs.readFile(ROOT .. "BlenderRoomRenderer.concurrent-after.luau")
assert(pcall(luau.compile, mazeSource) and pcall(luau.compile, rendererSource))
local fragment = assert(rendererSource:match("(function Renderer.CeilingPieces%(size, tile%).-)%s*function Renderer.SkinCarriedFuse"))
local renderer = luau.load("local Renderer={}\n" .. fragment .. "\nreturn Renderer\n", {environment = {Vector3 = r.Vector3}})()
local checked = 0
for _, cell in ipairs({12, 24, 36, 48}) do
	local tile = 4 * cell / 24
	local pieces = renderer.CeilingPieces(r.Vector3.new(cell, .36, cell), tile)
	local area, boxes = 0, {}
	for _, piece in ipairs(pieces) do
		local p, s = piece[1], piece[2]
		assert(s.X > 0 and s.Y > 0 and s.Z > 0)
		local box = {xmin = p.X - s.X / 2, xmax = p.X + s.X / 2, zmin = p.Z - s.Z / 2, zmax = p.Z + s.Z / 2}
		assert(box.xmin >= -cell / 2 and box.xmax <= cell / 2 and box.zmin >= -cell / 2 and box.zmax <= cell / 2)
		assert(math.min(box.xmax, tile) - math.max(box.xmin, 0) <= 1e-5
			or math.min(box.zmax, tile) - math.max(box.zmin, 0) <= 1e-5)
		for _, other in ipairs(boxes) do
			assert(math.min(box.xmax, other.xmax) - math.max(box.xmin, other.xmin) <= 1e-5
				or math.min(box.zmax, other.zmax) - math.max(box.zmin, other.zmin) <= 1e-5)
		end
		table.insert(boxes, box); area += s.X * s.Z
	end
	assert(math.abs(area - (cell * cell - tile * tile)) < 1e-4)
	checked += 1
end
local kit = serde.decode("json", fs.readFile(ROOT .. "concurrent-ceiling-kit-readonly.json"))
assert(kit.found and kit.ready and #kit.rooms == 42)
for _, room in ipairs(kit.rooms) do assert(#room.slabs == 1 and room.slabs[1].size[1] == 24 and room.slabs[1].size[3] == 24) end
local frames = serde.decode("json", fs.readFile(ROOT .. "concurrent-ceiling-relative-frames.json"))
assert(#frames == 42)
for _, item in ipairs(frames) do
	local c = item.relativeCFrame
	for i = 4, 12 do assert(math.abs(c[i] - (if i == 4 or i == 8 or i == 12 then 1 else 0)) < 1e-5) end
end
local receipt = {passed = true, scope = "Exact changed-source compile; CeilingPieces dimensions/coverage/nonoverlap at four cell scales; read-only current native42 prefabs all satisfy unique slab/dimension/orientation assertions. Not Level1 runtime gameplay or performance proof.",
	mazeSHA256 = serde.hash("sha256", mazeSource), rendererSHA256 = serde.hash("sha256", rendererSource), scalesChecked = checked, roomPrefabsChecked = #kit.rooms}
fs.writeFile(ROOT .. "concurrent-source-review-checks.json", serde.encode("json", receipt, true) .. "\n")
print(serde.encode("json", receipt, true))
