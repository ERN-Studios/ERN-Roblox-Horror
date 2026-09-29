-- Exact primitive test-kit helpers used for the isolated #1/#2/#5 draft renders.
-- This is a local QA helper, not a Studio script. It creates Instances only when
-- a caller creates a temporary root and invokes a builder. It does not reproduce
-- Level 5 Architecture's MaterialService variants, floor ownership, or round Lighting.
local TestKit = {}

function TestKit.facades(root)
	local K = {root = root, V = Vector3.new, CF = CFrame.new}
	function K.model(name, into)
		local x = Instance.new("Model")
		x.Name = name
		x.Parent = into or root
		return x
	end
	function K.part(into, name, size, cf, color, material, collide, className)
		local x = Instance.new(className or "Part")
		x.Name = name
		x.Size = size
		x.CFrame = cf -- Facades.Build* receives a world-space frame.
		x.Anchored = true
		x.Color = color or Color3.new(1, 1, 1)
		x.Material = material or Enum.Material.SmoothPlastic
		x.CanCollide = collide ~= false
		x.CanQuery = collide ~= false
		x.CanTouch = false
		x.Parent = into
		return x
	end
	return K
end

function TestKit.anomalies(root, origin)
	local O = origin or CFrame.new()
	local K = {
		root = root,
		V = Vector3.new,
		CF = CFrame.new,
		C = {green = Color3.fromRGB(48, 86, 67)},
	}
	function K.model(name, into)
		local x = Instance.new("Model")
		x.Name = name
		x.Parent = into or root
		return x
	end
	function K.part(into, name, size, cf, color, material, collide, className)
		local x = Instance.new(className or "Part")
		x.Name = name
		x.Size = size
		x.CFrame = O * cf -- Architecture's origin is applied by K.part.
		x.Anchored = true
		x.Color = color or Color3.new(1, 1, 1)
		x.Material = material or Enum.Material.SmoothPlastic
		x.CanCollide = collide ~= false
		x.CanQuery = collide ~= false
		x.CanTouch = false
		x.CastShadow = collide ~= false
		x.Parent = into
		return x
	end
	function K.floor(into, name, x, y, z, w, d, color, frame)
		local lawn = color == K.C.green
		return K.part(
			into, name, Vector3.new(w, 1.2, d),
			(frame or CFrame.new()) * CFrame.new(x, y - .6, z),
			color or Color3.fromRGB(162, 150, 125),
			lawn and Enum.Material.Grass or Enum.Material.Fabric, true
		)
	end
	function K.window(into, frame, w, h, lit, simple)
		local white = Color3.fromRGB(241, 238, 220)
		local g = K.part(into, "WindowGlass", Vector3.new(w, h, .14), frame,
			Color3.fromRGB(87, 102, 102), Enum.Material.Glass, true)
		g.Transparency = .2
		g:SetAttribute("Level5TintedWindow", true)
		for _, s in ipairs({-1, 1}) do
			K.part(into, "WindowJamb", Vector3.new(.25, h + .45, .34),
				frame * CFrame.new(s * (w / 2 + .08), 0, -.08), white)
			K.part(into, "WindowSill", Vector3.new(w + .65, .25, .4),
				frame * CFrame.new(0, s * (h / 2 + .08), -.12), white)
		end
		K.part(into, "WindowMullion", Vector3.new(.12, h, .23),
			frame * CFrame.new(0, 0, -.09), white)
		for _, s in ipairs(simple and {0} or {-.22, .22}) do
			K.part(into, "WindowCrossbar", Vector3.new(w, .12, .23),
				frame * CFrame.new(0, h * s, -.09), white)
		end
		return g
	end
	return K
end

return TestKit
