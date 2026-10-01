-- Generated from verified Level 6 Blender PNG hashes. Studio Edit plugin context only.
-- No global material override, existing object replacement, or gameplay source edit.
local HS = game:GetService("HttpService")
local MS = game:GetService("MaterialService")
local RS = game:GetService("RunService")
assert(not RS:IsRunning(), "Run only in Studio Edit mode")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407 and game.CreatorId == 1039373905, "Wrong target")
local expectedSource = "7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f"
local definitions = {
  {key="carpet_city", name="L6R_CarpetCity", base=Enum.Material.SmoothPlastic, tile=52, color="rbxassetid://98621799303808", normal="rbxassetid://116328137445668", roughness="rbxassetid://139484007192880", metalness=""},
  {key="carpet_default", name="L6R_CarpetDefault", base=Enum.Material.SmoothPlastic, tile=28, color="rbxassetid://121093973500899", normal="rbxassetid://88452853835386", roughness="rbxassetid://89198380667728", metalness=""},
  {key="carpet_neon", name="L6R_CarpetNeon", base=Enum.Material.SmoothPlastic, tile=22, color="rbxassetid://82722133850652", normal="rbxassetid://136787342451954", roughness="rbxassetid://126571057020383", metalness=""},
  {key="carpet_red", name="L6R_CarpetRed", base=Enum.Material.SmoothPlastic, tile=30, color="rbxassetid://109876058879522", normal="rbxassetid://90745928741030", roughness="rbxassetid://89535429729385", metalness=""},
  {key="diamondplate", name="L6R_Diamondplate", base=Enum.Material.SmoothPlastic, tile=8, color="rbxassetid://90077623524283", normal="rbxassetid://120950641893693", roughness="rbxassetid://131427650798902", metalness="rbxassetid://93496645006098"},
  {key="kitchen_tile", name="L6R_KitchenTile", base=Enum.Material.SmoothPlastic, tile=8, color="rbxassetid://98462196883058", normal="rbxassetid://125119207906835", roughness="rbxassetid://132364237361992", metalness=""},
  {key="orange_wall", name="L6R_OrangeWall", base=Enum.Material.SmoothPlastic, tile=22, color="rbxassetid://132985994016596", normal="rbxassetid://88928822227258", roughness="rbxassetid://93438818761889", metalness=""},
  {key="red_wall", name="L6R_RedWall", base=Enum.Material.SmoothPlastic, tile=22, color="rbxassetid://126159886412197", normal="rbxassetid://88928822227258", roughness="rbxassetid://93438818761889", metalness=""},
  {key="wallpaper", name="L6R_Wallpaper", base=Enum.Material.SmoothPlastic, tile=18, color="rbxassetid://132668244812004", normal="rbxassetid://78155391373634", roughness="rbxassetid://86046024871236", metalness=""},
}
local function matches(v, d)
  return v:IsA("MaterialVariant") and v.BaseMaterial == d.base and v.StudsPerTile == d.tile
    and v.ColorMap == d.color and v.NormalMap == d.normal and v.RoughnessMap == d.roughness
    and v.MetalnessMap == d.metalness and v:GetAttribute("Level6MaterialSourceSHA256") == expectedSource
end
local created = {}
for _, d in ipairs(definitions) do
  local old = MS:FindFirstChild(d.name)
  assert(old == nil or matches(old, d), "Existing MaterialVariant conflicts: " .. d.name)
end
local ok, err = pcall(function()
  for _, d in ipairs(definitions) do
    if not MS:FindFirstChild(d.name) then
      local v = Instance.new("MaterialVariant")
      v.Name = d.name; v.BaseMaterial = d.base; v.StudsPerTile = d.tile
      v.ColorMap = d.color; v.NormalMap = d.normal; v.RoughnessMap = d.roughness; v.MetalnessMap = d.metalness
      v:SetAttribute("Level6MaterialSourceSHA256", expectedSource)
      assert(MS:FindFirstChild(d.name) == nil, "MaterialVariant changed before write: " .. d.name)
      v.Parent = MS; table.insert(created, v)
    end
  end
end)
if not ok then for _, v in ipairs(created) do v:Destroy() end; error(err) end
local report = {}
for _, d in ipairs(definitions) do
  local v = assert(MS:FindFirstChild(d.name)); assert(matches(v, d), "Post-install mismatch: " .. d.name)
  table.insert(report, {name=d.name, base=tostring(v.BaseMaterial), tile=v.StudsPerTile,
    color=v.ColorMap, normal=v.NormalMap, roughness=v.RoughnessMap, metalness=v.MetalnessMap})
end
return HS:JSONEncode({ok=true, created=#created, variants=report, sourceMaterialManifestSHA256=expectedSource})
