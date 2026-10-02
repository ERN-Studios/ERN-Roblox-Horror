local rbx=require("@lune/roblox")
local db=rbx.getReflectionDatabase()
for _,name in {"BasePart","Instance","ObjectValue","Model","SurfaceAppearance"}do
 local class=db:GetClass(name)
 for key,property in class.Properties do if property.Datatype=="Ref"or key=="ColorMapContent"then
  print(name,key)
  for _,field in {"Serialization","Scriptability","Kind","Name","CanonicalName","IsSerialized","Serialized","AliasFor","DefaultValue"}do
   local ok,value=pcall(function()return property[field]end)
   if ok then print(field,typeof(value),value)end
  end
 end end
end
