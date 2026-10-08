-- Shared local presentation: the shop demo and the server-authorized scan use
-- the same model, face texture, colours and readout. No sensing or entitlement.
local Visual = {}
Visual.Texture = "rbxassetid://94042368093581"
Visual.Colors = {
 LOW = Color3.fromRGB(72, 174, 255),
 MEDIUM = Color3.fromRGB(255, 204, 65),
 HIGH = Color3.fromRGB(255, 69, 72),
}
Visual.Labels = {LOW="SAFE DISTANCE", MEDIUM="ENTITY NEARBY", HIGH="ENTITY VERY CLOSE"}
Visual.Explanations = {
 LOW="Blue: safe distance. The reading stays live for 30 seconds, so watch it as you move.",
 MEDIUM="Yellow: an entity is nearby. Slow down and listen before moving on.",
 HIGH="Red: warning! An entity is very close. React to its sound and behaviour.",
}
-- DETECTOR_BIG_SCREEN_20261008 (owner: "a much larger screen when used and demoed"). The generated face had a
-- screen opening of 61% x 29% of the housing, so the readout was about 110 x 80 pixels at its best. The device
-- now has a face of its own with a screen Width x Height of the housing, centred CentreY studs above the
-- housing's middle; Preview projects the readout onto exactly that glass. `ScreenBottom` is where the screen's
-- lower edge falls in a Preview frame (0 top, 1 bottom), for callers that place the device by its screen.
Visual.Screen = {Width=.86, Height=.64, CentreY=.2}
local HOUSING = Vector3.new(1.3,1.95,.36)
local GLASS_Z = HOUSING.Z/2+.052                 -- how far the glass stands in front of the housing's middle
local CAMERA = {FieldOfView=35, Height=.25, Distance=5}
local function viewHeight() return 2*math.tan(math.rad(CAMERA.FieldOfView/2))*(CAMERA.Distance-GLASS_Z) end
Visual.ScreenBottom = .5+(CAMERA.Height-(Visual.Screen.CentreY-HOUSING.Y*Visual.Screen.Height/2))/viewHeight()
local WHITE = Color3.fromRGB(228, 239, 242)
local DARK = Color3.fromRGB(9, 14, 19)
local function create(class, parent, properties)
 local object = Instance.new(class)
 for key,value in pairs(properties or {}) do object[key]=value end
 object.Parent=parent
 return object
end
local function label(parent, name, text, pos, size, fontSize)
 return create("TextLabel",parent,{Name=name,Text=text,Position=pos,Size=size,
  BackgroundTransparency=1,BorderSizePixel=0,Font=Enum.Font.Code,TextColor3=WHITE,
  TextSize=fontSize or 16,TextWrapped=true})
end
function Visual.Build(parent)
 local model=create("Model",nil,{Name="ZyntraLocalDetector"})
 local metal=Color3.fromRGB(40,43,43)
 local rubber=Color3.fromRGB(17,20,22)
 local brass=Color3.fromRGB(143,119,65)
 local function part(name,size,cf,color,material,shape)
  return create("Part",model,{Name=name,Size=size,CFrame=cf,Color=color,
   Material=material or Enum.Material.Metal,Shape=shape or Enum.PartType.Block,
   Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,CastShadow=false})
 end
 local body=part("ArmouredHousing",HOUSING,CFrame.new(),metal)
 model.PrimaryPart=body
 -- The face: a plate over the whole front, the screen in its bezel, and a control deck under it. (The generated
 -- face picture, Visual.Texture, had the small screen painted into it and is no longer applied.)
 local screen=Visual.Screen
 local sw,sh,sy=HOUSING.X*screen.Width,HOUSING.Y*screen.Height,screen.CentreY
 local front=-HOUSING.Z/2
 part("FrontPlate",Vector3.new(HOUSING.X-.04,HOUSING.Y-.04,.03),CFrame.new(0,0,front-.012),Color3.fromRGB(31,34,35))
 part("ScreenBezel",Vector3.new(sw+.1,sh+.1,.04),CFrame.new(0,sy,front-.03),rubber,Enum.Material.SmoothPlastic)
 local glass=part("ScreenGlass",Vector3.new(sw,sh,.012),CFrame.new(0,sy,-GLASS_Z+.006),Color3.fromRGB(5,9,12),Enum.Material.SmoothPlastic)
 glass.Reflectance=.08
 local deck=sy-sh/2-.05                            -- top of the strip under the bezel
 local low=-HOUSING.Y/2+.06
 local flat=CFrame.Angles(0,math.pi/2,0)           -- a cylinder lying with its round face to the front
 for i=-1,1 do
  part("DeckButton",Vector3.new(.05,.2,.2),CFrame.new(i*.34,deck-.13,front-.04)*flat,i==0 and brass or rubber,
   i==0 and Enum.Material.Metal or Enum.Material.SmoothPlastic,Enum.PartType.Cylinder)
 end
 for i=1,4 do
  part("SpeakerSlat",Vector3.new(.5,.018,.02),CFrame.new(0,low+.02+(i-1)*.032,front-.03),rubber,Enum.Material.SmoothPlastic)
 end
 part("StatusLamp",Vector3.new(.07,.07,.07),CFrame.new(HOUSING.X/2-.13,HOUSING.Y/2-.07,front-.03),Visual.Colors.LOW,Enum.Material.Neon,Enum.PartType.Ball)
 -- Raised rubber ribs and rounded antenna supply an actual silhouette/depth.
 part("RearCasing",Vector3.new(1.18,1.83,.11),CFrame.new(0,0,.215),rubber,Enum.Material.SmoothPlastic)
 for _,side in ipairs({-1,1}) do
  for i=1,7 do
   part("GripRib",Vector3.new(.1,.055,.39),CFrame.new(side*.67,.6-(i-1)*.2,0),rubber,Enum.Material.SmoothPlastic)
  end
 end
 local cyl=CFrame.Angles(0,0,math.pi/2)
 part("AntennaCollar",Vector3.new(.14,.23,.23),CFrame.new(.43,1.035,0)*cyl,brass,nil,Enum.PartType.Cylinder)
 part("RubberAntenna",Vector3.new(.43,.17,.17),CFrame.new(.43,1.305,0)*cyl,rubber,Enum.Material.SmoothPlastic,Enum.PartType.Cylinder)
 part("AntennaCap",Vector3.new(.17,.17,.17),CFrame.new(.43,1.52,0),rubber,Enum.Material.SmoothPlastic,Enum.PartType.Ball)
 for i=1,4 do
  part("CollarKnurl",Vector3.new(.018,.244,.244),CFrame.new(.43,.98+i*.026,0)*cyl,brass,nil,Enum.PartType.Cylinder)
 end
 model.Parent=parent
 return model
end

-- SurfaceGuis do not render in ViewportFrames. Project the real screen opening
-- into the preview and put its live readout there, with the same camera maths.
-- This isolated render layer also prevents the shop/HUD painting over the item.
function Visual.Preview(parent)
 local frame=create("Frame",parent,{Name="DetectorPreview",BackgroundTransparency=1,BorderSizePixel=0})
 local viewport=create("ViewportFrame",frame,{Name="Equipment",Size=UDim2.fromScale(1,1),
  BackgroundTransparency=1,Ambient=Color3.fromRGB(190,198,210),LightColor=Color3.fromRGB(255,244,222),
  LightDirection=Vector3.new(-.4,-.6,-1),ZIndex=1})
 local world=create("WorldModel",viewport)
 local model=Visual.Build(world)
 model:PivotTo(CFrame.Angles(0,math.pi,0))
 local camera=create("Camera",viewport,{FieldOfView=CAMERA.FieldOfView,CFrame=CFrame.new(0,CAMERA.Height,CAMERA.Distance)})
 viewport.CurrentCamera=camera
 local display=create("Frame",frame,{Name="DetectorScreen",BackgroundColor3=DARK,BorderSizePixel=0,ZIndex=2})
 create("UICorner",display,{CornerRadius=UDim.new(.04,0)})
 local edge=create("UIStroke",display,{Color=Visual.Colors.LOW,Thickness=2,Transparency=.25})
 local header=label(display,"Mode","LIVE READING",UDim2.fromScale(.06,.03),UDim2.fromScale(.88,.11),12)
 local bars={}
 for i,key in ipairs({"LOW","MEDIUM","HIGH"}) do
  bars[key]=create("Frame",display,{Name=key.."Bar",Position=UDim2.fromScale(.08,.17+(i-1)*.105),
   Size=UDim2.fromScale(.84,.075),BackgroundColor3=Visual.Colors[key],BackgroundTransparency=.84,BorderSizePixel=0,ZIndex=3})
  create("UICorner",bars[key],{CornerRadius=UDim.new(.35,0)})
 end
 local value=label(display,"Meaning","READY",UDim2.fromScale(.04,.5),UDim2.fromScale(.92,.32),16)
 local footer=label(display,"Readout","30 SECOND READING",UDim2.fromScale(.04,.85),UDim2.fromScale(.92,.11),10)
 header.ZIndex=3 value.ZIndex=3 footer.ZIndex=3
 local lamp=model:FindFirstChild("StatusLamp")
 local current="LOW"
 local compactScreen=false
 local function layout()
  local h=frame.AbsoluteSize.Y
  local pixels=h/viewHeight()
  -- The glass of the device's own face (Visual.Screen), a hair inside its bezel.
  local w,sh=HOUSING.X*Visual.Screen.Width*pixels*.97,HOUSING.Y*Visual.Screen.Height*pixels*.97
  display.Position=UDim2.fromOffset(frame.AbsoluteSize.X/2-w/2,h/2-(Visual.Screen.CentreY-CAMERA.Height)*pixels-sh/2)
  display.Size=UDim2.fromOffset(w,sh)
  edge.Thickness=math.max(1,math.floor(sh*.012))
  header.TextSize=math.clamp(math.floor(sh*.068),8,20)
  footer.TextSize=math.clamp(math.floor(sh*.072),7,20)
  compactScreen=sh<62
  header.Visible=not compactScreen footer.Visible=not compactScreen
  value.Position=UDim2.fromScale(.035,compactScreen and .52 or .5)
  value.Size=UDim2.fromScale(.93,compactScreen and .46 or .32)
  value.TextSize=compactScreen and math.max(8,math.floor(sh*.19)) or math.clamp(math.floor(sh*.125),10,36)
  value.Text=compactScreen and ({LOW="SAFE\nDISTANCE",MEDIUM="ENTITY\nNEARBY",HIGH="VERY\nCLOSE"})[current] or Visual.Labels[current]
 end
 local changed=frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
 local api={Root=frame,Model=model,Display=display}
 function api:SetReading(key,demo,seconds)
  if not Visual.Colors[key] then return end
  current=key
  frame:SetAttribute("Reading",key)
  for band,bar in pairs(bars) do bar.BackgroundTransparency=band==key and 0 or .87 end
  header.Text=demo and "SIMULATED DEMO" or "LIVE READING"
  edge.Color=Visual.Colors[key]
  if lamp then lamp.Color=Visual.Colors[key] end
  value.Text=compactScreen and ({LOW="SAFE\nDISTANCE",MEDIUM="ENTITY\nNEARBY",HIGH="VERY\nCLOSE"})[key] or Visual.Labels[key]
  value.TextColor3=Visual.Colors[key]
  footer.Text=demo and "NO REAL ENTITY" or string.format("%ds REMAINING",math.ceil(math.max(0,seconds or 0)))
 end
 function api:Destroy() changed:Disconnect() frame:Destroy() end
 layout()
 return api
end

-- A contained, dismissible demo: no purchases, ownership changes or live scan.
function Visual.Demo(playerGui,onClose)
 local UIS=game:GetService("UserInputService")
 local RunService=game:GetService("RunService")
 local UIDevice=require(script.Parent:WaitForChild("UIDevice"))
 local gui=create("ScreenGui",playerGui,{Name="ZyntraDetectorDemo",ResetOnSpawn=false,
  DisplayOrder=1200,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets})
 local shade=create("Frame",gui,{Name="Backdrop",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(),BackgroundTransparency=.16,BorderSizePixel=0,Active=true})
 local panel=create("Frame",shade,{Name="DemoPanel",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),BackgroundColor3=Color3.fromRGB(15,22,26),BorderSizePixel=0})
 create("UICorner",panel,{CornerRadius=UDim.new(0,12)})
 create("UIStroke",panel,{Color=Color3.fromRGB(68,119,123),Thickness=1})
 local title=label(panel,"Title","ZYNTRA / ENTITY DETECTOR",UDim2.fromOffset(16,10),UDim2.new(1,-80,0,28),19)
 title.TextXAlignment=Enum.TextXAlignment.Left
 local close=create("TextButton",panel,{Name="CloseDemo",Text="X",Font=Enum.Font.GothamBold,TextSize=22,
  Size=UDim2.fromOffset(44,44),AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-8,0,4),
  BackgroundColor3=Color3.fromRGB(31,46,51),TextColor3=WHITE,BorderSizePixel=0})
 create("UICorner",close,{CornerRadius=UDim.new(0,8)})
 local preview=Visual.Preview(panel)
 local info=create("Frame",panel,{Name="Explanation",BackgroundTransparency=1})
 local eyebrow=label(info,"Eyebrow","FREE SIMULATED DEMO",UDim2.fromOffset(0,0),UDim2.new(1,0,0,23),13)
 eyebrow.TextColor3=Color3.fromRGB(89,220,207) eyebrow.TextXAlignment=Enum.TextXAlignment.Left
 local meaning=label(info,"Meaning","",UDim2.fromOffset(0,27),UDim2.new(1,0,0,40),24)
 meaning.TextXAlignment=Enum.TextXAlignment.Left
 local explanation=label(info,"Explanation","",UDim2.fromOffset(0,71),UDim2.new(1,0,0,54),15)
 explanation.TextXAlignment=Enum.TextXAlignment.Left
 local buttons={}
 for i,key in ipairs({"LOW","MEDIUM","HIGH"}) do
  local b=create("TextButton",info,{Name="Show"..key,Text=({"BLUE / SAFE","YELLOW / NEARBY","RED / VERY CLOSE"})[i],
   Font=Enum.Font.GothamMedium,TextSize=13,TextColor3=WHITE,BackgroundColor3=Color3.fromRGB(25,37,44),BorderSizePixel=0,
   Size=UDim2.new(1,0,0,44),Position=UDim2.fromOffset(0,134+(i-1)*49)})
  create("UICorner",b,{CornerRadius=UDim.new(0,6)})
  create("Frame",b,{Name="Colour",Position=UDim2.fromOffset(0,0),Size=UDim2.new(0,5,1,0),BackgroundColor3=Visual.Colors[key],BorderSizePixel=0})
  buttons[key]=b
 end
 local note=label(panel,"UseInstructions","IN A RUN: Z / D-pad left / SCAN  •  live for 30 seconds  •  ready again 10 seconds later\nA reading, not a guarantee of safety. Demo never uses a real scan or buys anything.",UDim2.new(0,16,1,-54),UDim2.new(1,-32,0,46),12)
 local bandIndex=1 local began=os.clock() local manual=false local destroyed=false local conns={}
 local function setBand(index)
  bandIndex=index local key=({"LOW","MEDIUM","HIGH"})[index]
  preview:SetReading(key,true)
  meaning.Text=(key=="HIGH" and "WARNING! " or "")..Visual.Labels[key]
  meaning.TextColor3=Visual.Colors[key] explanation.Text=Visual.Explanations[key]
  gui:SetAttribute("Reading",key)
  for k,b in pairs(buttons) do b.BackgroundColor3=k==key and Color3.fromRGB(43,62,72) or Color3.fromRGB(25,37,44) end
 end
 for i,key in ipairs({"LOW","MEDIUM","HIGH"}) do
  table.insert(conns,buttons[key].Activated:Connect(function() manual=true setBand(i) end))
 end
 local function layout()
  local safe=UIDevice.Layout().Safe
  -- DETECTOR_BIG_SCREEN_20261008: the panel may grow with the display, and the device with it.
  local w=math.min(1040,math.max(280,safe.Width-24))
  local h=math.min(780,math.max(230,safe.Height-24))
  panel.Size=UDim2.fromOffset(w,h)
  panel.Position=UIDevice.LocalPosition(gui,(safe.Left+safe.Right)/2,(safe.Top+safe.Bottom)/2)
  local portrait=w<500 and h>450
  if portrait then
   preview.Root.Position=UDim2.fromOffset(8,43) preview.Root.Size=UDim2.fromOffset(w-16,h*.44)
   info.Position=UDim2.fromOffset(18,45+h*.44) info.Size=UDim2.fromOffset(w-36,h*.45-30)
   eyebrow.Visible=false
   meaning.Position=UDim2.fromOffset(0,0) meaning.Size=UDim2.new(1,0,0,30) meaning.TextSize=19
   explanation.Position=UDim2.fromOffset(0,31) explanation.Size=UDim2.new(1,0,0,42) explanation.TextSize=13
   for i,key in ipairs({"LOW","MEDIUM","HIGH"}) do
    local b=buttons[key] b.Position=UDim2.new((i-1)/3,2,0,79) b.Size=UDim2.new(1/3,-4,0,44)
    b.Text=({"BLUE","YELLOW","RED"})[i]
   end
  else
   local compact=h<420
   local previewWidth=math.floor(w*(compact and .39 or .47))
   preview.Root.Position=UDim2.fromOffset(8,42) preview.Root.Size=UDim2.fromOffset(previewWidth,h-94)
   info.Position=UDim2.fromOffset(previewWidth+16,compact and 43 or 65)
   info.Size=UDim2.fromOffset(w-previewWidth-34,h-112)
   eyebrow.Visible=not compact
   meaning.Position=UDim2.fromOffset(0,compact and 0 or 27) meaning.Size=UDim2.new(1,0,0,compact and 28 or 40) meaning.TextSize=compact and 17 or 24
   explanation.Position=UDim2.fromOffset(0,compact and 31 or 71) explanation.Size=UDim2.new(1,0,0,compact and 43 or 54) explanation.TextSize=compact and 12 or 15
   for i,key in ipairs({"LOW","MEDIUM","HIGH"}) do
    local b=buttons[key]
    b.Position=compact and UDim2.new((i-1)/3,2,0,84) or UDim2.fromOffset(0,134+(i-1)*49)
    b.Size=compact and UDim2.new(1/3,-4,0,44) or UDim2.new(1,0,0,44)
    b.Text=(compact and {"BLUE","YELLOW","RED"} or {"BLUE / SAFE","YELLOW / NEARBY","RED / VERY CLOSE"})[i]
   end
  end
  note.Position=UDim2.new(0,16,1,portrait and -76 or -54)
  note.Size=UDim2.new(1,-32,0,portrait and 68 or 46)
  note.Text=portrait and "Z / D-pad left / SCAN during a run\nLive for 30 seconds / ready again 10 seconds later\nSIMULATED DEMO / No purchase or live scan\nKeep listening: no guaranteed safety."
   or "IN A RUN: Z / D-pad left / SCAN  •  live for 30 seconds  •  ready again 10 seconds later\nA reading, not a guarantee of safety. Demo never uses a real scan or buys anything."
  title.TextSize=w<550 and 14 or 19
  note.TextSize=h<420 and 10 or 12
 end
 local api={Root=gui,Preview=preview}
 function api:Destroy()
  if destroyed then return end destroyed=true
  for _,c in ipairs(conns) do c:Disconnect() end
  preview:Destroy() gui:Destroy()
 end
 local function dismiss() api:Destroy() if onClose then onClose() end end
 table.insert(conns,close.Activated:Connect(dismiss))
 table.insert(conns,UIS.InputBegan:Connect(function(input,processed)
  if not processed and (input.KeyCode==Enum.KeyCode.ButtonB or input.KeyCode==Enum.KeyCode.Escape) then dismiss() end
 end))
 table.insert(conns,UIDevice.Changed:Connect(layout))
 table.insert(conns,gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
 table.insert(conns,RunService.Heartbeat:Connect(function()
  if not manual then
   local i=math.min(3,math.floor((os.clock()-began)/3)+1)
   if i~=bandIndex then setBand(i) end
  end
 end))
 setBand(1) layout()
 return api
end
return Visual
