local rbx,fs=require("@lune/roblox"),require("@lune/fs")
local roots=rbx.deserializeModel(fs.readFile("/private/tmp/lobby-polish-native-scope-selftest-20261002/exact_scope/all-service-children.rbxm"))
for _,root in roots do for _,node in root:GetDescendants()do if node.ClassName=="SurfaceAppearance"then
 for _,property in {"ColorMap","ColorMapContent","NormalMap","MetalnessMap","EmissiveStrength","Color"}do
  local ok,value=pcall(function()return node[property]end)
  print(property,ok,typeof(value),value)
  if typeof(value)=="table"then for k,v in value do print("field",k,typeof(v),v)end end
 end
 break
end end end
