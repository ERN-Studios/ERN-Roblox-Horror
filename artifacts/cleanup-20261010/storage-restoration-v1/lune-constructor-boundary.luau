-- Diagnostic only: preserve every exact constructor difference; never normalize.
local fs=require("@lune/fs")
local serde=require("@lune/serde")
local roblox=require("@lune/roblox")
local process=require("@lune/process")
local value=serde.decode("json",fs.readFile(process.args[1]))
local rows={} local changed=0
for _,spec in value.rows do
 local actual={roblox.CFrame.new(table.unpack(spec.components)):GetComponents()}
 local differences={}
 for index,expected in spec.components do
  if expected~=actual[index] then
   differences[#differences+1]={component=index,expected=expected,actual=actual[index]}
   changed+=1
  end
 end
 rows[#rows+1]={path=spec.path,exact=#differences==0,differences=differences}
end
print(serde.encode("json",{schema="storage-lune-constructor-boundary-v1",exact=changed==0,
 nativeCalls=0,normalizationApplied=false,changedComponents=changed,rows=rows}))
