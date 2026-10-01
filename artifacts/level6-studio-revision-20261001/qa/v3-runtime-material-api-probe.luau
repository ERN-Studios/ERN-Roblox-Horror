-- Temporary server Script for a real Studio Play session. Never run via
-- execute_luau: that command uses a plugin context with different permissions.
-- Parent in ServerScriptService before Play, then remove after collecting Output.
local AssetService = game:GetService("AssetService")

local variant = Instance.new("MaterialVariant")
local variantOK, variantError = pcall(function()
	variant.ColorMapContent = Content.none
end)
print("L6_PBR_RUNTIME_VARIANT_WRITE", variantOK, tostring(variantError))
variant:Destroy()

local image = AssetService:CreateEditableImage({Size = Vector2.new(1, 1)})
assert(image, "No EditableImage server budget for 1x1 material API probe")
image:DrawRectangle(Vector2.zero, Vector2.one, Color3.new(1, 0, 0), 0, Enum.ImageCombineType.Overwrite)
local surfaceOK, surfaceOrError = pcall(function()
	return AssetService:CreateSurfaceAppearanceAsync({
		ColorMap = Content.fromObject(image),
	})
end)
print("L6_PBR_RUNTIME_SURFACE_FACTORY", surfaceOK, surfaceOK and surfaceOrError.ClassName or tostring(surfaceOrError))
if surfaceOK then surfaceOrError:Destroy() end
image:Destroy()
