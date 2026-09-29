assert(game.PlaceId==121672571539226 and not game:GetService("RunService"):IsRunning())
local Http=game:GetService("HttpService")
local function value(v)
 local t=typeof(v)
 if t=="Vector3" then return {v.X,v.Y,v.Z}
 elseif t=="Color3" then return {v.R,v.G,v.B}
 elseif t=="CFrame" then return {v:GetComponents()}
 elseif t=="EnumItem" or t=="Content" then return tostring(v)
 elseif t=="Instance" then return v:GetFullName()
 elseif t=="table" then local out={} for k,x in pairs(v) do out[k]=value(x) end return out
 else return v end
end
local function properties(obj,names)
 local result={} for _,name in ipairs(names) do local ok,v=pcall(function()return obj[name]end);if ok then result[name]=value(v) end end return result
end
local out={placeId=game.PlaceId,universeId=game.GameId,placeVersion=game.PlaceVersion,gravity=workspace.Gravity,instances={},scripts={},sourceEditorConflicts={},archive="ServerStorage.AeroReplacementArchive.Vesper Cathedral",archiveDescendants=#game.ServerStorage.AeroReplacementArchive["Vesper Cathedral"]:GetDescendants(),scope="Exact house instances plus relevant experience settings. Full native place is AeroHouse_Playable.rbxl."}
local house=workspace["Aero House"]
local list={house};for _,v in ipairs(house:GetDescendants())do list[#list+1]=v end
for _,v in ipairs(list)do
 local x={path=v:GetFullName(),class=v.ClassName,attributes=value(v:GetAttributes()),properties={}}
 if v:IsA("Model") then x.properties.Pivot=value(v:GetPivot());x.properties.PrimaryPart=value(v.PrimaryPart) end
 if v:IsA("BasePart") then x.properties=properties(v,{"CFrame","Size","Color","Material","MaterialVariant","Transparency","Reflectance","Anchored","CanCollide","CanTouch","CanQuery","CastShadow","CollisionGroup","CustomPhysicalProperties"})end
 if v:IsA("MeshPart") then for k,z in pairs(properties(v,{"MeshId","TextureID","RenderFidelity","CollisionFidelity","DoubleSided"}))do x.properties[k]=z end end
 if v:IsA("SurfaceAppearance") then x.properties=properties(v,{"ColorMap","MetalnessMap","RoughnessMap","NormalMap","AlphaMode","Color"}) end
 if v:IsA("Light")then x.properties=properties(v,{"Enabled","Brightness","Color","Range","Shadows"})end
 if v:IsA("SpawnLocation")then for k,z in pairs(properties(v,{"Enabled","Neutral","Duration","TeamColor"}))do x.properties[k]=z end end
 out.instances[#out.instances+1]=x
end
table.sort(out.instances,function(a,b)return a.path<b.path end)
for _,v in ipairs(game:GetDescendants())do if v:IsA("LuaSourceContainer")then
 local source=v.Source;local editor=game:GetService("ScriptEditorService"):GetEditorSource(v)
 out.scripts[#out.scripts+1]={path=v:GetFullName(),class=v.ClassName,source=source,editorSource=editor}
 if source~=editor then out.sourceEditorConflicts[#out.sourceEditorConflicts+1]=v:GetFullName()end
end end
out.lighting=properties(game.Lighting,{"Brightness","ClockTime","Ambient","OutdoorAmbient","GlobalShadows","ExposureCompensation","EnvironmentDiffuseScale","EnvironmentSpecularScale"})
out.baseplate=properties(workspace.Baseplate,{"CFrame","Size","Anchored","CanCollide","Color","Material"})
return Http:JSONEncode(out)
