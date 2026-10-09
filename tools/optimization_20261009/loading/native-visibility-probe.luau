-- Fresh, unparented, test-owned non-script fixtures. No asset fetches or world edits.
local BOOT_ASSET_RADIUS = 128
local LOBBY_BACKGROUND_SECONDS = 20
local lobbyLoadedIds = nil

local function withinBootRadius(part, origin)
	if not origin then return true end -- recovery must not silently omit the scene
	local point = part.CFrame:PointToObjectSpace(origin)
	local half = part.Size * 0.5
	local outside = Vector3.new(
		math.max(0, math.abs(point.X) - half.X),
		math.max(0, math.abs(point.Y) - half.Y),
		math.max(0, math.abs(point.Z) - half.Z))
	return outside.Magnitude <= BOOT_ASSET_RADIUS
end

local function bootAssetVisible(instance, origin)
	local host, screen = nil, false
	local ancestor = instance
	while ancestor do
		if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
		if ancestor:IsA("LayerCollector") then
			if not ancestor.Enabled then return false end
			if ancestor:IsA("ScreenGui") then
				screen = true
			elseif ancestor:IsA("SurfaceGui") or ancestor:IsA("BillboardGui") then
				local adornee = ancestor.Adornee
				if adornee and adornee:IsA("BasePart") then
					host = adornee
				elseif adornee and adornee:IsA("Attachment") then
					host = adornee:FindFirstAncestorWhichIsA("BasePart")
				end
			end
		end
		if not host and ancestor:IsA("BasePart") then host = ancestor end
		ancestor = ancestor.Parent
	end
	if screen and not host then return true end
	return host ~= nil and withinBootRadius(host, origin)
end


return function()
 local root=Instance.new("Folder")
 root.Name="OptimizationVisibilityProbe"
 local checks=0
 local function check(value,message) assert(value,message); checks+=1 end
 local function make(class,parent)
  local inst=Instance.new(class); inst.Parent=parent; return inst
 end
 local ok,result=xpcall(function()
  local part=make("Part",root); part.Size=Vector3.new(4,4,4); part.CFrame=CFrame.new(64,0,0)
  local decal=make("Decal",part)
  local origin=Vector3.zero
  check(bootAssetVisible(decal,origin),"near hosted decal")
  part.CFrame=CFrame.new(200,0,0)
  check(not bootAssetVisible(decal,origin),"far hosted decal")
  part.Size=Vector3.new(160,4,4)
  check(bootAssetVisible(decal,origin),"large OBB surface within radius")
  part.CFrame=CFrame.new(200,0,0)*CFrame.Angles(0,math.pi/2,0)
  check(not bootAssetVisible(decal,origin),"rotated OBB outside radius")
  part.Size=Vector3.new(4,4,4); part.CFrame=CFrame.new(130,0,0)
  check(bootAssetVisible(decal,origin),"exact radius")
  part.CFrame=CFrame.new(130.01,0,0)
  check(not bootAssetVisible(decal,origin),"past radius")
  check(bootAssetVisible(decal,nil),"origin recovery conservative")
  local screen=make("ScreenGui",root)
  local frame=make("Frame",screen)
  local image=make("ImageLabel",frame)
  check(bootAssetVisible(image,origin),"visible screen image")
  frame.Visible=false
  check(not bootAssetVisible(image,origin),"hidden ancestor excludes image")
  frame.Visible=true; screen.Enabled=false
  check(not bootAssetVisible(image,origin),"disabled screen excludes image")
  local billboard=make("BillboardGui",root)
  local badge=make("ImageLabel",billboard)
  billboard.Adornee=part
  check(not bootAssetVisible(badge,origin),"world image actual adornee radius")
  part.CFrame=CFrame.new(30,0,0)
  check(bootAssetVisible(badge,origin),"near world image")
  local attachment=make("Attachment",part)
  billboard.Adornee=attachment
  check(bootAssetVisible(badge,origin),"attachment adornee resolves BasePart")
  billboard.Enabled=false
  check(not bootAssetVisible(badge,origin),"disabled billboard excluded")
  return {kind="native-visibility-contract",checks=checks,assetsFetched=false,gameplay=false}
 end,debug.traceback)
 root:Destroy()
 if not ok then error(result) end
 return result
end
