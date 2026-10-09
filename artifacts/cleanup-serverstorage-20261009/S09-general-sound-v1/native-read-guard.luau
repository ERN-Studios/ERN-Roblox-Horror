local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local function mode()
 assert(not game:GetService("RunService"):IsRunning(),"S09 requires Edit; never switch modes")
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Unexpected place/universe")
end
local function sha(text)
 local digest=ENC:ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(digest)-1 do out[#out+1]=string.format("%02x",buffer.readu8(digest,i)) end
 return table.concat(out)
end
local function stable(v)
 if type(v)~="table" then return H:JSONEncode(v) end
 local keys={} for key in v do keys[#keys+1]=key end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={} for _,key in keys do out[#out+1]=H:JSONEncode(key)..":"..stable(v[key]) end
 return "{"..table.concat(out,",").."}"
end
local function resolve()
 local node=game
 for _,name in {"StarterPlayer","StarterPlayerScripts","SoundController"} do
  local found=nil for _,child in node:GetChildren() do
   if child.Name==name then assert(found==nil,"Ambiguous S09 path");found=child end
  end
  node=assert(found,"Missing S09 path")
 end
 assert(node.ClassName=="LocalScript" and node:GetFullName()=="StarterPlayer.StarterPlayerScripts.SoundController","Unexpected S09 instance")
 return node
end
local function read(pin)
 mode()
 local node=resolve()
 local source=node.Source local editor=SES:GetEditorSource(node)
 assert(source==editor,"Native/editor conflict; leave both unchanged")
 local attrs=node:GetAttributes()
 for name,value in attrs do
  local kind=typeof(value)
  assert(kind=="string" or kind=="boolean" or kind=="number","Unsupported S09 attribute type; do not lose typed data: "..name)
 end
 local tags=node:GetTags() table.sort(tags)
 local meta={path=node:GetFullName(),className=node.ClassName,instanceId=node:GetDebugId(16),
  parentId=node.Parent:GetDebugId(16),parentPath=node.Parent:GetFullName(),parentClass=node.Parent.ClassName,
  rawBytes=#source,rawSourceSHA256=sha(source),editorMatches=true,
  properties={Enabled=node.Enabled,Disabled=node.Disabled,RunContext=tostring(node.RunContext),LinkedSource=node.LinkedSource,Archivable=node.Archivable},
  attributes=attrs,tags=tags}
 if pin then assert(stable(meta)==stable(pin),"S09 exact Source/editor/identity/properties/attrs/tags changed") end
 assert(node.Source==source and SES:GetEditorSource(node)==source,"S09 Source/editor changed within read")
 mode()
 return source,meta
end
