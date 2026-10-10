
local prime=0x01000193
local function multiply(x)
 local low=bit32.band(x,0xFFFF)*prime
 local high=bit32.band(bit32.rshift(x,16)*prime,0xFFFF)*65536
 return bit32.band(low+high,0xFFFFFFFF)
end
local function hash(source)
 local fnv,djb=0x811C9DC5,5381
 for at=1,#source,4096 do
  local bytes={string.byte(source,at,math.min(at+4095,#source))}
  for _,b in ipairs(bytes) do fnv=multiply(bit32.bxor(fnv,b));djb=bit32.band(djb*33+b,0xFFFFFFFF) end
 end
 return string.format("%d:%08x:%08x",#source,fnv,djb)
end
local SES=game:GetService("ScriptEditorService")
local rows={}
for _,inst in ipairs(game:GetDescendants()) do
 if inst:IsA("LuaSourceContainer") then
  assert(inst.Source==SES:GetEditorSource(inst),"source/editor mismatch "..inst:GetFullName())
  table.insert(rows,inst:GetFullName().."\t"..inst.ClassName.."\t"..hash(inst.Source))
  if #rows%25==0 then task.wait() end
 end
end
table.sort(rows)
return table.concat(rows,"\n")
