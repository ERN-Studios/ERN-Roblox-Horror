local HS=game:GetService("HttpService")
local RS=game:GetService("RunService")
assert(not RS:IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407 and game.CreatorId==1039373905,"Wrong target/state")
local expected=HS:JSONDecode([==[{"maps":{"L6R_Wallpaper":{"normal":"rbxassetid://107064693112194","source":"7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f","tile":18,"rough":"rbxassetid://134574001368311","color":"rbxassetid://94610099985829","base":"SmoothPlastic","metal":""},"L6R_Diamondplate":{"normal":"rbxassetid://119057460725717","source":"7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f","tile":8,"rough":"rbxassetid://81766063150603","color":"rbxassetid://123284965632869","base":"SmoothPlastic","metal":"rbxassetid://111359091414160"},"L6R_CarpetRed":{"normal":"rbxassetid://82242543701773","source":"7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f","tile":30,"rough":"rbxassetid://80380970345074","color":"rbxassetid://108774727227729","base":"SmoothPlastic","metal":""},"L6R_OrangeWall":{"normal":"rbxassetid://83563690907279","source":"7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f","tile":22,"rough":"rbxassetid://117293783404334","color":"rbxassetid://119876675052986","base":"SmoothPlastic","metal":""},"L6R_CarpetCity":{"normal":"rbxassetid://80660148568960","source":"7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f","tile":52,"rough":"rbxassetid://73502694711467","color":"rbxassetid://132790982247033","base":"SmoothPlastic","metal":""},"L6R_CarpetDefault":{"normal":"rbxassetid://124245216980517","source":"7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f","tile":28,"rough":"rbxassetid://124549688722616","color":"rbxassetid://91741108024348","base":"SmoothPlastic","metal":""},"L6R_CarpetNeon":{"normal":"rbxassetid://77197908678900","source":"7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f","tile":22,"rough":"rbxassetid://134246452400559","color":"rbxassetid://75705552619347","base":"SmoothPlastic","metal":""},"L6R_RedWall":{"normal":"rbxassetid://83563690907279","source":"7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f","tile":22,"rough":"rbxassetid://117293783404334","color":"rbxassetid://116262571153797","base":"SmoothPlastic","metal":""},"L6R_KitchenTile":{"normal":"rbxassetid://132898202245381","source":"7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f","tile":8,"rough":"rbxassetid://104848653256953","color":"rbxassetid://118192063553860","base":"SmoothPlastic","metal":""}},"value":"{\n  \"schema\": \"level6-blender-materials/1\",\n  \"sourceMaterialManifestSha256\": \"7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f\",\n  \"propsAtlasAssetId\": 119366040096776,\n  \"variants\": {\n    \"carpet_city\": {\n      \"name\": \"L6R_CarpetCity\",\n      \"baseMaterial\": \"SmoothPlastic\",\n      \"studsPerTile\": 52,\n      \"mapAssetIds\": {\n        \"color\": 132790982247033,\n        \"normalOpenGL\": 80660148568960,\n        \"roughness\": 73502694711467\n      }\n    },\n    \"carpet_default\": {\n      \"name\": \"L6R_CarpetDefault\",\n      \"baseMaterial\": \"SmoothPlastic\",\n      \"studsPerTile\": 28,\n      \"mapAssetIds\": {\n        \"color\": 91741108024348,\n        \"normalOpenGL\": 124245216980517,\n        \"roughness\": 124549688722616\n      }\n    },\n    \"carpet_neon\": {\n      \"name\": \"L6R_CarpetNeon\",\n      \"baseMaterial\": \"SmoothPlastic\",\n      \"studsPerTile\": 22,\n      \"mapAssetIds\": {\n        \"color\": 75705552619347,\n        \"normalOpenGL\": 77197908678900,\n        \"roughness\": 134246452400559\n      }\n    },\n    \"carpet_red\": {\n      \"name\": \"L6R_CarpetRed\",\n      \"baseMaterial\": \"SmoothPlastic\",\n      \"studsPerTile\": 30,\n      \"mapAssetIds\": {\n        \"color\": 108774727227729,\n        \"normalOpenGL\": 82242543701773,\n        \"roughness\": 80380970345074\n      }\n    },\n    \"diamondplate\": {\n      \"name\": \"L6R_Diamondplate\",\n      \"baseMaterial\": \"SmoothPlastic\",\n      \"studsPerTile\": 8,\n      \"mapAssetIds\": {\n        \"color\": 123284965632869,\n        \"normalOpenGL\": 119057460725717,\n        \"roughness\": 81766063150603,\n        \"metalness\": 111359091414160\n      }\n    },\n    \"kitchen_tile\": {\n      \"name\": \"L6R_KitchenTile\",\n      \"baseMaterial\": \"SmoothPlastic\",\n      \"studsPerTile\": 8,\n      \"mapAssetIds\": {\n        \"color\": 118192063553860,\n        \"normalOpenGL\": 132898202245381,\n        \"roughness\": 104848653256953\n      }\n    },\n    \"orange_wall\": {\n      \"name\": \"L6R_OrangeWall\",\n      \"baseMaterial\": \"SmoothPlastic\",\n      \"studsPerTile\": 22,\n      \"mapAssetIds\": {\n        \"color\": 119876675052986,\n        \"normalOpenGL\": 83563690907279,\n        \"roughness\": 117293783404334\n      }\n    },\n    \"red_wall\": {\n      \"name\": \"L6R_RedWall\",\n      \"baseMaterial\": \"SmoothPlastic\",\n      \"studsPerTile\": 22,\n      \"mapAssetIds\": {\n        \"color\": 116262571153797,\n        \"normalOpenGL\": 83563690907279,\n        \"roughness\": 117293783404334\n      }\n    },\n    \"wallpaper\": {\n      \"name\": \"L6R_Wallpaper\",\n      \"baseMaterial\": \"SmoothPlastic\",\n      \"studsPerTile\": 18,\n      \"mapAssetIds\": {\n        \"color\": 94610099985829,\n        \"normalOpenGL\": 107064693112194,\n        \"roughness\": 134574001368311\n      }\n    }\n  }\n}\n"}]==])
local nextText=[==[{
  "schema": "level6-blender-materials/1",
  "sourceMaterialManifestSha256": "7515152956ec7b84dddcf87865d5375c11e42965f9ca88a906ff52bbe372392f",
  "propsAtlasAssetId": 131879734824108,
  "variants": {
    "carpet_city": {
      "name": "L6R_CarpetCity",
      "baseMaterial": "SmoothPlastic",
      "studsPerTile": 52,
      "mapAssetIds": {
        "color": 98621799303808,
        "normalOpenGL": 116328137445668,
        "roughness": 139484007192880
      }
    },
    "carpet_default": {
      "name": "L6R_CarpetDefault",
      "baseMaterial": "SmoothPlastic",
      "studsPerTile": 28,
      "mapAssetIds": {
        "color": 121093973500899,
        "normalOpenGL": 88452853835386,
        "roughness": 89198380667728
      }
    },
    "carpet_neon": {
      "name": "L6R_CarpetNeon",
      "baseMaterial": "SmoothPlastic",
      "studsPerTile": 22,
      "mapAssetIds": {
        "color": 82722133850652,
        "normalOpenGL": 136787342451954,
        "roughness": 126571057020383
      }
    },
    "carpet_red": {
      "name": "L6R_CarpetRed",
      "baseMaterial": "SmoothPlastic",
      "studsPerTile": 30,
      "mapAssetIds": {
        "color": 109876058879522,
        "normalOpenGL": 90745928741030,
        "roughness": 89535429729385
      }
    },
    "diamondplate": {
      "name": "L6R_Diamondplate",
      "baseMaterial": "SmoothPlastic",
      "studsPerTile": 8,
      "mapAssetIds": {
        "color": 90077623524283,
        "normalOpenGL": 120950641893693,
        "roughness": 131427650798902,
        "metalness": 93496645006098
      }
    },
    "kitchen_tile": {
      "name": "L6R_KitchenTile",
      "baseMaterial": "SmoothPlastic",
      "studsPerTile": 8,
      "mapAssetIds": {
        "color": 98462196883058,
        "normalOpenGL": 125119207906835,
        "roughness": 132364237361992
      }
    },
    "orange_wall": {
      "name": "L6R_OrangeWall",
      "baseMaterial": "SmoothPlastic",
      "studsPerTile": 22,
      "mapAssetIds": {
        "color": 132985994016596,
        "normalOpenGL": 88928822227258,
        "roughness": 93438818761889
      }
    },
    "red_wall": {
      "name": "L6R_RedWall",
      "baseMaterial": "SmoothPlastic",
      "studsPerTile": 22,
      "mapAssetIds": {
        "color": 126159886412197,
        "normalOpenGL": 88928822227258,
        "roughness": 93438818761889
      }
    },
    "wallpaper": {
      "name": "L6R_Wallpaper",
      "baseMaterial": "SmoothPlastic",
      "studsPerTile": 18,
      "mapAssetIds": {
        "color": 132668244812004,
        "normalOpenGL": 78155391373634,
        "roughness": 86046024871236
      }
    }
  }
}
]==]
local wanted=HS:JSONDecode(nextText)
local f=assert(game.ServerStorage:FindFirstChild("Level6BlenderSourceRevision20261001"))
local data=assert(f:FindFirstChild("MaterialsJSON"))
assert(f:GetAttribute("Level6Owned")==true and data:IsA("StringValue") and data.Value==expected.value,"Materials baseline changed")
local ms=game:GetService("MaterialService")
for name,d in expected.maps do
 local v=assert(ms:FindFirstChild(name))
 assert(v:IsA("MaterialVariant")and v.ColorMap==d.color and v.NormalMap==d.normal and v.RoughnessMap==d.rough and v.MetalnessMap==d.metal and v.BaseMaterial.Name==d.base and v.StudsPerTile==d.tile and v:GetAttribute("Level6MaterialSourceSHA256")==d.source,"Variant baseline changed: "..name)
end
local function uri(n) return n and ("rbxassetid://"..tostring(n))or "" end
local report={}
-- No yield between this full baseline recheck and the scoped property writes.
assert(data.Value==expected.value,"Materials changed before write")
for _,d in wanted.variants do
 local v=assert(ms:FindFirstChild(d.name));local a=d.mapAssetIds
 v.ColorMap=uri(a.color);v.NormalMap=uri(a.normalOpenGL);v.RoughnessMap=uri(a.roughness);v.MetalnessMap=uri(a.metalness)
 table.insert(report,{name=v.Name,color=v.ColorMap,normal=v.NormalMap,rough=v.RoughnessMap,metal=v.MetalnessMap})
end
data.Value=nextText
assert(data.Value==nextText,"Materials after mismatch")
return {ok=true,updated=#report,propsAtlas=wanted.propsAtlasAssetId,variants=report}
