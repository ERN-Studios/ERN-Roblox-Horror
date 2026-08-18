-- Reproducible source for the three straight-grout column flare mesh assets.
-- Run UploadAll() from a locally loaded Studio plugin when a new version is
-- required. Runtime generation intentionally uses the uploaded static assets,
-- so the experience does not need EditableMesh security enabled.

local AssetService = game:GetService("AssetService")

local RADIAL_SIDES = 40
local PROFILE_STEPS = 11
local TILE_STUDS = 9

local PUBLISHED_MESHES = {
	[4.5] = "rbxassetid://90304501186271",
	[5.5] = "rbxassetid://118916035196716",
	[9] = "rbxassetid://111134467625970",
}

local function build(diameter)
	local flareLength = math.clamp(diameter * 1.35, 7.2, 10.2)
	local radialScale = diameter * 2.22 / 2.2
	-- Lock circumferential U to the shaft neck. Using each row's widening
	-- radius shears constant-U grout lines around the trumpet, making the tile
	-- grid visibly spiral. A fixed neck radius keeps every longitude straight
	-- and preserves the shaft's exact nine-stud scale at the visible join.
	local neckRadius = .5 * radialScale
	local mesh = AssetService:CreateEditableMesh()
	local vertices = {}
	local cumulativeMeridian = 0
	local previousY, previousRadius

	for row = 0, PROFILE_STEPS do
		local profileAngle = row / PROFILE_STEPS * math.pi * .5
		local y = math.sin(profileAngle) * flareLength
		local radius = (.5 + .6 * (1 - math.cos(profileAngle))) * radialScale
		if previousY then
			cumulativeMeridian += math.sqrt(
				(y - previousY) ^ 2 + (radius - previousRadius) ^ 2)
		end
		previousY, previousRadius = y, radius
		vertices[row] = {}

		for side = 0, RADIAL_SIDES do
			local azimuth = side / RADIAL_SIDES * math.pi * 2
			local cosAzimuth, sinAzimuth = math.cos(azimuth), math.sin(azimuth)
			local vertex = mesh:AddVertex(Vector3.new(
				cosAzimuth * radius, y, sinAzimuth * radius))
			local yDerivative = flareLength * math.cos(profileAngle)
			local radiusDerivative = radialScale * .6 * math.sin(profileAngle)
			vertices[row][side] = {
				Vertex = vertex,
				UV = Vector2.new(
					azimuth * neckRadius / TILE_STUDS,
					cumulativeMeridian / TILE_STUDS),
				Normal = Vector3.new(
					yDerivative * cosAzimuth,
					-radiusDerivative,
					yDerivative * sinAzimuth).Unit,
			}
		end
	end

	local function triangle(a, b, c)
		local face = mesh:AddTriangle(a.Vertex, b.Vertex, c.Vertex)
		local faceUVs = mesh:GetFaceUVs(face)
		local faceNormals = mesh:GetFaceNormals(face)
		for index, corner in ipairs({a, b, c}) do
			mesh:SetUV(faceUVs[index], corner.UV)
			mesh:SetNormal(faceNormals[index], corner.Normal)
		end
	end

	for row = 0, PROFILE_STEPS - 1 do
		for side = 0, RADIAL_SIDES - 1 do
			triangle(vertices[row][side], vertices[row + 1][side],
				vertices[row + 1][side + 1])
			triangle(vertices[row][side], vertices[row + 1][side + 1],
				vertices[row][side + 1])
		end
	end

	return mesh
end

local function uploadAll()
	local created = {}
	for _, diameter in ipairs({4.5, 5.5, 9}) do
		local mesh = build(diameter)
		local result, assetId = AssetService:CreateAssetAsync(mesh, Enum.AssetType.Mesh, {
			Name = string.format("Level 2 Column Flare Straight Grout D%.1f", diameter),
			Description = "Poolrooms Level 2 smooth concrete column flare with straight grout and 9-stud neck-scale tile UVs.",
		})
		mesh:Destroy()
		assert(result == Enum.CreateAssetResult.Success, tostring(result))
		created[diameter] = "rbxassetid://" .. tostring(assetId)
	end
	return created
end

return {
	Build = build,
	UploadAll = uploadAll,
	PublishedMeshes = PUBLISHED_MESHES,
	TileStuds = TILE_STUDS,
}
