-- Reproducible geometry for the hollow closed-slide end cap asset
-- rbxassetid://107409495820821. Run Build() from a locally loaded Studio
-- plugin when a new asset version is needed.

local AssetService = game:GetService("AssetService")

local SIDES = 24
local INNER_RADIUS = .885
local OUTER_RADIUS = 1.015
local HALF_DEPTH = .015

local function build()
	local mesh = AssetService:CreateEditableMesh()
	local rings = {
		innerFront = {}, outerFront = {},
		innerBack = {}, outerBack = {},
	}
	local outerNormals, innerNormals = {}, {}
	local frontNormal = mesh:AddNormal(Vector3.new(0, 0, -1))
	local backNormal = mesh:AddNormal(Vector3.new(0, 0, 1))

	for index = 0, SIDES - 1 do
		local angle = index * math.pi * 2 / SIDES
		local radial = Vector3.new(math.cos(angle), math.sin(angle), 0)
		rings.innerFront[index] = mesh:AddVertex(
			Vector3.new(radial.X * INNER_RADIUS, radial.Y * INNER_RADIUS, -HALF_DEPTH))
		rings.outerFront[index] = mesh:AddVertex(
			Vector3.new(radial.X * OUTER_RADIUS, radial.Y * OUTER_RADIUS, -HALF_DEPTH))
		rings.innerBack[index] = mesh:AddVertex(
			Vector3.new(radial.X * INNER_RADIUS, radial.Y * INNER_RADIUS, HALF_DEPTH))
		rings.outerBack[index] = mesh:AddVertex(
			Vector3.new(radial.X * OUTER_RADIUS, radial.Y * OUTER_RADIUS, HALF_DEPTH))
		outerNormals[index] = mesh:AddNormal(radial)
		innerNormals[index] = mesh:AddNormal(-radial)
	end

	local function triangle(a, b, c, normalA, normalB, normalC)
		local face = mesh:AddTriangle(a, b, c)
		mesh:SetFaceNormals(face, {normalA, normalB, normalC})
	end

	local function quad(a, b, c, d, normalA, normalB, normalC, normalD)
		triangle(a, b, c, normalA, normalB, normalC)
		triangle(a, c, d, normalA, normalC, normalD)
	end

	for index = 0, SIDES - 1 do
		local nextIndex = (index + 1) % SIDES
		quad(rings.innerFront[index], rings.innerFront[nextIndex],
			rings.outerFront[nextIndex], rings.outerFront[index],
			frontNormal, frontNormal, frontNormal, frontNormal)
		quad(rings.innerBack[index], rings.outerBack[index],
			rings.outerBack[nextIndex], rings.innerBack[nextIndex],
			backNormal, backNormal, backNormal, backNormal)
		quad(rings.outerFront[index], rings.outerFront[nextIndex],
			rings.outerBack[nextIndex], rings.outerBack[index],
			outerNormals[index], outerNormals[nextIndex],
			outerNormals[nextIndex], outerNormals[index])
		quad(rings.innerFront[index], rings.innerBack[index],
			rings.innerBack[nextIndex], rings.innerFront[nextIndex],
			innerNormals[index], innerNormals[index],
			innerNormals[nextIndex], innerNormals[nextIndex])
	end

	return mesh
end

return {
	Build = build,
	Sides = SIDES,
	BaseRadius = 1,
	InnerRadius = INNER_RADIUS,
	OuterRadius = OUTER_RADIUS,
	BaseDepth = HALF_DEPTH * 2,
}
