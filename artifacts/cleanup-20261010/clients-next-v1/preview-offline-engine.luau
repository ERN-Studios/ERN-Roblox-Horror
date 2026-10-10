-- Offline boundary only; native staged runner uses actual Roblox Instances.
local method={}
local function signal()
 local listeners={}
 return {Connect=function(_,fn)
  local connection={Connected=true}
  function connection:Disconnect()self.Connected=false end
  listeners[#listeners+1]={connection=connection,fn=fn};return connection
 end,Fire=function(_,...)
  for _,record in listeners do if record.connection.Connected then record.fn(...) end end
 end}
end
local function instance(class)
 local data={ClassName=class,Name=class,Parent=nil,Enabled=(class=="ProximityPrompt"),Children={},Attributes={},Signals={},DescendantAdded=signal(),Destroyed=false}
 local n
 n=setmetatable({}, {__index=function(_,key)return method[key] or data[key]end,__newindex=function(_,key,value)
  local previous=data[key];data[key]=value
  if key=="Parent" and previous~=value then
   if previous then local i=table.find(previous.Children,n);if i then table.remove(previous.Children,i)end end
   if value then value.Children[#value.Children+1]=n;local parent=value
    while parent do parent.DescendantAdded:Fire(n);parent=parent.Parent end
   end
  end
  if previous~=value and data.Signals[key] then data.Signals[key]:Fire() end
 end})
 return n
end
function method:IsA(class)return self.ClassName==class or class=="Instance"end
function method:GetDescendants()
 local out={} local function visit(n)for _,child in n.Children do out[#out+1]=child;visit(child)end end
 visit(self);return out
end
function method:IsDescendantOf(root)local n=self.Parent;while n do if n==root then return true end;n=n.Parent end;return false end
function method:GetPropertyChangedSignal(key)if not self.Signals[key]then self.Signals[key]=signal()end;return self.Signals[key]end
function method:SetAttribute(key,value)self.Attributes[key]=value end
function method:GetAttribute(key)return self.Attributes[key]end
function method:Destroy()
 for index=#self.Children,1,-1 do self.Children[index]:Destroy()end
 self.Parent=nil;self.Destroyed=true
end
local Instance={new=instance}
local task={wait=function()end}
