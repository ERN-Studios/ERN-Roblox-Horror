-- Local presentation only. Shared by the honest shop demo and live scan.
local Visual={}
Visual.Colors={LOW=Color3.fromRGB(73,245,204),MEDIUM=Color3.fromRGB(255,193,60),HIGH=Color3.fromRGB(245,77,66)}
function Visual.Build(parent)
 local model=Instance.new("Model") model.Name="ZyntraLocalDetector"
 local function part(name,size,cf,color,material)
  local p=Instance.new("Part") p.Name=name p.Size=size p.CFrame=cf
  p.Anchored=true p.CanCollide=false p.CanTouch=false p.CanQuery=false
  p.Color=color p.Material=material or Enum.Material.Metal p.Parent=model return p
 end
 local body=part("Body",Vector3.new(.85,1.25,.25),CFrame.new(),Color3.fromRGB(24,30,29))
 model.PrimaryPart=body
 part("Antenna",Vector3.new(.1,.42,.1),CFrame.new(-.28,.8,0),Color3.fromRGB(49,52,49))
 local screen=part("Display",Vector3.new(.65,.5,.035),CFrame.new(0,.2,-.15),Color3.fromRGB(4,17,14),Enum.Material.SmoothPlastic)
 part("ScanButton",Vector3.new(.26,.24,.06),CFrame.new(0,-.35,-.15),Color3.fromRGB(155,138,72))
 local face=Instance.new("SurfaceGui") face.Face=Enum.NormalId.Front face.CanvasSize=Vector2.new(320,220) face.Parent=screen
 local text=Instance.new("TextLabel") text.Size=UDim2.fromScale(1,1) text.BackgroundTransparency=1 text.TextScaled=true
 text.Font=Enum.Font.Code text.TextColor3=Visual.Colors.LOW text.Text="ZYNTRA\nREADY" text.Parent=face
 model.Parent=parent
 return model,text
end
return Visual
