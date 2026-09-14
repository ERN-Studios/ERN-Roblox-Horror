-- Disposable Studio test transport. REMOVE from Edit before finishing.
if not game:GetService("RunService"):IsStudio() then return end
local H = game:GetService("HttpService")
local remote = Instance.new("RemoteFunction")
remote.Name = "CodexMultiplayerProbe"
remote.Parent = game:GetService("ReplicatedStorage")
local base = "http://127.0.0.1:44559/"
local function post(data) H:PostAsync(base, H:JSONEncode(data), Enum.HttpContentType.ApplicationJson) end
pcall(post, {id="ready", place=game.PlaceId})
while task.wait(.25) do
 local ok, command = pcall(function() return H:JSONDecode(H:GetAsync(base, true)) end)
 if ok and command.code then
  local success, result = pcall(function()
   local fn, err = loadstring(command.code)
   assert(fn, err)
   return fn()
  end)
  local encoded, err = pcall(post, {id=command.id, ok=success, result=result})
  if not encoded then pcall(post, {id=command.id, ok=false, result=tostring(err)}) end
 end
end
