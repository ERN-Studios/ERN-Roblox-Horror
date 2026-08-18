-- Reproducible geometry for the continuous U-shaped slide cradle asset
-- rbxassetid://132916619634128. Run Build() from a locally loaded Studio
-- plugin when a new asset version is needed.

local AssetService = game:GetService("AssetService")

local INNER_RADIUS = .985
local OUTER_RADIUS = 1.10
local CIRCLE_Y = .317559956
local START_ANGLE = math.rad(155)
local END_ANGLE = math.rad(385)
local SEGMENTS = 32

local function build()
	local mesh = AssetService:CreateEditableMesh()
	local rings = {
		innerFront = {},
		outerFront = {},
		innerBack = {},
		outerBack = {},
	}

	local function point(radius, angle, z)
		return Vector3.new(
			math.cos(angle) * radius,
			CIRCLE_Y + math.sin(angle) * radius,
			z)
	end

	for index = 0, SEGMENTS do
		local angle = START_ANGLE
			+ (END_ANGLE - START_ANGLE) * index / SEGMENTS
		rings.innerFront[index] = mesh:AddVertex(point(INNER_RADIUS, angle, -.5))
		rings.outerFront[index] = mesh:AddVertex(point(OUTER_RADIUS, angle, -.5))
		rings.innerBack[index] = mesh:AddVertex(point(INNER_RADIUS, angle, .5))
		rings.outerBack[index] = mesh:AddVertex(point(OUTER_RADIUS, angle, .5))
	end

	local function quad(a, b, c, d)
		mesh:AddTriangle(a, b, c)
		mesh:AddTriangle(a, c, d)
	end

	for index = 0, SEGMENTS - 1 do
		local nextIndex = index + 1
		quad(rings.outerFront[index], rings.outerBack[index],
			rings.outerBack[nextIndex], rings.outerFront[nextIndex])
		quad(rings.innerFront[nextIndex], rings.innerBack[nextIndex],
			rings.innerBack[index], rings.innerFront[index])
		quad(rings.innerFront[index], rings.outerFront[index],
			rings.outerFront[nextIndex], rings.innerFront[nextIndex])
		quad(rings.innerBack[nextIndex], rings.outerBack[nextIndex],
			rings.outerBack[index], rings.innerBack[index])
	end

	quad(rings.innerFront[0], rings.innerBack[0],
		rings.outerBack[0], rings.outerFront[0])
	quad(rings.outerFront[SEGMENTS], rings.outerBack[SEGMENTS],
		rings.innerBack[SEGMENTS], rings.innerFront[SEGMENTS])

	return mesh
end

return {
	Build = build,
	BaseRadius = 1,
	BaseLength = 1,
	CenterYOffset = CIRCLE_Y,
	InnerRadius = INNER_RADIUS,
	OuterRadius = OUTER_RADIUS,
}
