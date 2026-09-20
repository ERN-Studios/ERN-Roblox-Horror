local CS=game:GetService("CollectionService")
local Sensing={}
function Sensing.IsLiving(model)
 if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace)
  or model:GetAttribute("ZyntraDetectorActive")==false or model:GetAttribute("Dead")==true
  or model:GetAttribute("Level2_PoolSlideActive")==false then return false end
 local hum=model:FindFirstChildOfClass("Humanoid")
 return not hum or hum.Health>0
end
function Sensing.Band(distance,config)
 if distance<=config.HighRange then return "HIGH" end
 if distance<=config.Range then return "MEDIUM" end
 return "LOW"
end
function Sensing.Read(position,level,config)
 local candidates,seen={},{}
 local function add(model)
  if model and not seen[model] then seen[model]=true table.insert(candidates,model) end
 end
 if level==1 then add(workspace:FindFirstChild("Entity")) end
 if level==2 then for _,model in ipairs(CS:GetTagged("Level2HostileEntity")) do add(model) end end
 if level==3 and workspace:GetAttribute("Level3MallManagerActive")==true then
  local world=workspace:FindFirstChild("Level 3 Generated World")
  add(world and world:FindFirstChild("Mall Manager",true))
 end
 -- Extension point for future entities (including Level 4): tag a live Model,
 -- with PrimaryPart, and set ZyntraDetectorLevel; no UI changes are needed.
 for _,model in ipairs(CS:GetTagged("ZyntraDetectableEntity")) do
  if model:GetAttribute("ZyntraDetectorLevel")==level then add(model) end
 end
 local nearest=math.huge
 for _,model in ipairs(candidates) do
  if Sensing.IsLiving(model) then
   local root=model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
   if root and root:IsA("BasePart") then nearest=math.min(nearest,(root.Position-position).Magnitude) end
  end
 end
 return Sensing.Band(nearest,config)
end
return table.freeze(Sensing)
