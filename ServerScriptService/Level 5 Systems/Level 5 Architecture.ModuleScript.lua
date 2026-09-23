-- Level 5: The Indoor Suburbs. Geometry only; deliberately independent of Level 4.
-- All authored coordinates are relative to origin. No Lighting, entity or quest mutation.
local Architecture = {}

function Architecture.Build(parent, origin, config)
	config = config or {}
	origin = origin or Vector3.zero
	local root = Instance.new("Model")
	root.Name = "Level5_IndoorSuburbs"
	root:SetAttribute("ArchitectureVersion", "2026-09-23.2")
	root:SetAttribute("GeometryOnly", true)
	root.Parent = parent
	local offset = CFrame.new(origin)
	local V, CF = Vector3.new, CFrame.new
	local C = {
		cream=Color3.fromRGB(214,205,174), pale=Color3.fromRGB(232,225,205), white=Color3.fromRGB(241,238,220),
		carpet=Color3.fromRGB(162,150,125), green=Color3.fromRGB(48,86,67), pink=Color3.fromRGB(211,165,163),
		yellow=Color3.fromRGB(216,184,99), rose=Color3.fromRGB(205,154,159), blue=Color3.fromRGB(144,166,182),
		lavender=Color3.fromRGB(173,155,179), glass=Color3.fromRGB(87,102,102), dark=Color3.fromRGB(24,30,29),
		ceiling=Color3.fromRGB(181,179,157), grid=Color3.fromRGB(136,138,126), red=Color3.fromRGB(133,38,32),
	}
	local partCount, lightCount = 0, 0
	local function model(name, into)
		local m=Instance.new("Model"); m.Name=name; m.Parent=into or root; return m
	end
	local function part(into, name, size, cf, color, material, collide, className)
		local p=Instance.new(className or "Part")
		p.Name=name; p.Size=size; p.CFrame=offset*cf; p.Anchored=true
		p.Color=color or C.cream; p.Material=material or Enum.Material.SmoothPlastic
		p.CanCollide=collide~=false; p.CanTouch=false; p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
		p.Parent=into; partCount+=1; return p
	end
	local function texture(p, asset, face, tile)
		if not asset or asset=="" then return end
		local t=Instance.new("Texture"); t.Name="MaterialDetail"; t.Texture=tostring(asset)
		t.Face=face or Enum.NormalId.Top; t.StudsPerTileU=tile or 8; t.StudsPerTileV=tile or 8
		t.Transparency=.12; t.Parent=p; return t
	end
	local function floor(into, name, x,y,z,w,d,color,frame)
		local p=part(into,name,V(w,1.2,d),(frame or CF())*CF(x,y-.6,z),color or C.carpet,Enum.Material.Fabric)
		local surface=texture(p,config.CarpetTexture,Enum.NormalId.Top,8)
		-- Texture colour is independent of the underlying Part colour. Preserve
		-- the green "lawn" carpet and pink/yellow street palette under the bitmap.
		if surface and color and color~=C.carpet then
			surface.Color3=color==C.green and Color3.fromRGB(86,132,98) or color
		end
		return p
	end
	local function beam(into,name,a,b,width,color)
		local mid=(a+b)/2
		return part(into,name,V(width,width,(b-a).Magnitude),CFrame.lookAt(mid,b),color or C.white,Enum.Material.SmoothPlastic)
	end
	local function rail(into,frame,width)
		part(into,"RailingTop",V(width,.24,.24),frame*CF(0,3.35,0),C.white)
		part(into,"RailingBottom",V(width,.16,.18),frame*CF(0,.45,0),C.white)
		local n=math.max(1,math.ceil(width/2.15))
		for i=0,n do part(into,"RailingSpindle",V(.13,3,.13),frame*CF(-width/2+width*i/n,1.88,0),C.white) end
	end
	local function stairs(into,name,frame,width,rise,run,steps,color,withRails)
		local m=model(name,into)
		local dh,dd=rise/steps,run/steps
		for i=1,steps do
			local top=dh*i
			-- Each tread is a shallow slab: descending flights never create inverted/negative blocks.
			part(m,"CarpetTread",V(width,.65,dd+.035),frame*CF(0,top-.325,dd*(i-.5)),color or C.carpet,Enum.Material.Fabric)
			part(m,"Riser",V(width,math.abs(dh)+.15,.14),frame*CF(0,top-dh/2-.08,dd*(i-1)),color or C.carpet,Enum.Material.Fabric)
		end
		if withRails then
			for _,s in ipairs({-1,1}) do
				local a=frame:PointToWorldSpace(V(s*(width/2-.18),3,0))
				local b=frame:PointToWorldSpace(V(s*(width/2-.18),rise+3,run))
				beam(m,"StairHandrail",a,b,.24,C.white)
				for i=0,steps,3 do part(m,"StairSpindle",V(.15,3,.15),frame*CF(s*(width/2-.18),rise*i/steps+1.5,run*i/steps),C.white) end
			end
		end
		return m
	end
	local function window(into,frame,w,h,lit)
		local glass=part(into,"WindowGlass",V(w,h,.14),frame,lit and Color3.fromRGB(222,218,189) or C.glass,lit and Enum.Material.Neon or Enum.Material.Glass)
		glass.Transparency=lit and .14 or .2
		for _,s in ipairs({-1,1}) do
			part(into,"WindowJamb",V(.25,h+.45,.34),frame*CF(s*(w/2+.08),0,-.08),C.white)
			part(into,"WindowSill",V(w+.65,.25,.4),frame*CF(0,s*(h/2+.08),-.12),C.white)
		end
		part(into,"WindowMullion",V(.12,h,.23),frame*CF(0,0,-.09),C.white)
		for _,s in ipairs({-.22,.22}) do part(into,"WindowCrossbar",V(w,.12,.23),frame*CF(0,h*s,-.09),C.white) end
	end
	local function doorframe(into,frame,width,height)
		for _,s in ipairs({-1,1}) do part(into,"DoorJamb",V(.4,height+.3,.55),frame*CF(s*(width/2+.2),height/2,-.13),C.white) end
		part(into,"DoorHeader",V(width+.8,.45,.55),frame*CF(0,height+.15,-.13),C.white)
	end
	local function facade(into,frame,w,h,color,openDoor,lit)
		local dw,dh=5.4,10.3
		local sw=(w-dw)/2
		part(into,"FacadeLintel",V(w,h-dh,.65),frame*CF(0,dh+(h-dh)/2,0),color)
		for _,s in ipairs({-1,1}) do
			local x=s*(dw/2+sw/2)
			part(into,"WindowApron",V(sw,2.8,.65),frame*CF(x,1.4,0),color)
			for _,j in ipairs({-1,1}) do part(into,"FacadePier",V(1.15,dh,.65),frame*CF(x+j*(sw/2-.575),dh/2,0),color) end
			window(into,frame*CF(x,6.55,-.18),sw-2.3,7.2,lit)
		end
		doorframe(into,frame,dw,dh)
		if not openDoor then
			part(into,"ClosedPanelDoor",V(dw,dh,.32),frame*CF(0,dh/2,.05),C.white,Enum.Material.Wood)
			for _,y in ipairs({2.4,6.6,8.7}) do for _,x in ipairs({-1.25,1.25}) do part(into,"DoorRaisedPanel",V(1.85,y==6.6 and 2.8 or 1.25,.13),frame*CF(x,y,-.18),C.pale,Enum.Material.Wood) end end
			local knob=part(into,"BrassDoorKnob",V(.27,.27,.4),frame*CF(2,4.6,-.4),Color3.fromRGB(137,119,65),Enum.Material.Metal); knob.Shape=Enum.PartType.Ball
		end
		part(into,"FacadeSkirting",V(w,.42,.8),frame*CF(0,.25,.08),C.white)
		-- Split the skirting at an open doorway so there is no trip-sized threshold.
		if openDoor then
			local last=into:FindFirstChild("FacadeSkirting")
			if last then last:Destroy(); partCount-=1 end
			for _,sign in ipairs({-1,1}) do part(into,"SplitSkirting",V(sw,.35,.8),frame*CF(sign*(dw/2+sw/2),.18,.08),C.white) end
		end
	end
	local function wallLamp(into,frame)
		part(into,"WallSconceBack",V(.6,1.4,.25),frame,C.white,Enum.Material.Metal)
		part(into,"WallSconceGlow",V(.65,.7,.45),frame*CF(0,0,-.25),Color3.fromRGB(255,236,189),Enum.Material.Neon,false)
	end
	local function house(into,name,frame,w,d,h,color,roofColor,options)
		options=options or {}; local m=model(name,into)
		floor(m,"InteriorCarpet",0,0,d/2,w,d,C.carpet,frame)
		if options.cutaway then
			-- A few upper rooms have exposed wall sections, as in the reference.
			-- These are fixed architectural cuts rather than destructible objects.
			part(m,"CutawayWallApron",V(w,2.4,.7),frame*CF(0,1.2,0),color,Enum.Material.Plaster)
			part(m,"CutawayHeader",V(w,1,.7),frame*CF(0,h-.5,0),color,Enum.Material.Plaster)
			part(m,"CutawayTallPier",V(1.3,h,.9),frame*CF(-w/2+.65,h/2,0),color,Enum.Material.Plaster)
			part(m,"CutawayShortPier",V(1.3,5.3,.9),frame*CF(w/2-.65,2.65,0),color,Enum.Material.Plaster)
			for i=0,3 do
				part(m,"ExposedPlasterEdge",V(.38,1.15,.95),frame*CF(-w/2+1.35,3.5+i*2.3,-.05)*CFrame.Angles(0,0,math.rad(i%2==0 and 12 or -9)),C.white,Enum.Material.Plaster)
			end
		else facade(m,frame,w,h,color,options.open~=false,options.lit) end
		for _,s in ipairs({-1,1}) do
			part(m,"SideWall",V(.65,h,d),frame*CF(s*w/2,h/2,d/2),color)
			part(m,"InteriorBaseboard",V(.18,.5,d),frame*CF(s*(w/2-.4),.25,d/2),C.white)
		end
		if options.backOpening then
			local wing=(w-7)/2
			for _,s in ipairs({-1,1}) do part(m,"BackWallWing",V(wing,h,.65),frame*CF(s*(3.5+wing/2),h/2,d),color) end
			part(m,"BackWallHeader",V(7,h-10,.65),frame*CF(0,10+(h-10)/2,d),color)
			doorframe(m,frame*CF(0,0,d),7,10)
		else part(m,"BackWall",V(w,h,.65),frame*CF(0,h/2,d),color) end
		part(m,"InteriorCeiling",V(w,.45,d),frame*CF(0,h,d/2),C.ceiling)
		part(m,"InteriorLight",V(w*.35,.1,2.7),frame*CF(0,h-.3,d/2),Color3.fromRGB(241,240,214),Enum.Material.Neon,false)
		part(m,"CrownMoulding",V(w+.6,.5,.85),frame*CF(0,h-.15,-.08),C.white)
		for _,s in ipairs({-1,1}) do wallLamp(m,frame*CF(s*(w/2-1.2),10.8,-.55)) end
		if roofColor then
			local pitch=math.rad(32); local half=w/2+1.1; local slant=half/math.cos(pitch)
			local gableRise=(w/2)*math.tan(pitch)
			local gableBase=.5+1.1*math.tan(pitch)
			part(m,"GableBaseBand",V(w,gableBase,.6),frame*CF(0,h+gableBase/2,-.03),color)
			for _,s in ipairs({-1,1}) do
				local roofFrame=frame*CF(s*half/2,h+half*math.tan(pitch)/2+.5,d/2)*CFrame.Angles(0,0,-s*pitch)
				part(m,"PitchedRoof",V(slant,.48,d+2),roofFrame,roofColor,Enum.Material.Slate)
				part(m,"RoofCladdingSeam",V(.08,.065,d+1.9),roofFrame*CF(0,.27,0),Color3.fromRGB(112,117,129),Enum.Material.Slate,false)
				part(m,"WhiteGableTrim",V(slant,.3,.45),frame*CF(s*half/2,h+half*math.tan(pitch)/2+.6,-1.1)*CFrame.Angles(0,0,-s*pitch),C.white)
				part(m,"ClosedGableTriangle",V(.6,gableRise,w/2),frame*CF(s*w/4,h+gableBase+gableRise/2,-.03)*CFrame.Angles(0,-s*math.pi/2,0),color,Enum.Material.SmoothPlastic,true,"WedgePart")
			end
			part(m,"RoofRidge",V(.35,.35,d+2.4),frame*CF(0,h+half*math.tan(pitch)+.5,d/2),roofColor)
		end
		return m
	end
	local function ceiling(into,name,x,z,w,d,y,style)
		local m=model(name,into)
		part(m,"CeilingPlane",V(w,.5,d),CF(x,y,z),C.ceiling)
		local tile=style=="warehouse" and 20 or 12
		for xx=-w/2,w/2,tile do part(m,"CeilingGrid",V(.09,.1,d),CF(x+xx,y-.29,z),C.grid) end
		for zz=-d/2,d/2,tile do part(m,"CeilingGrid",V(w,.1,.09),CF(x,y-.29,z+zz),C.grid) end
		local ix=0
		for xx=-w/2+14,w/2-8,28 do
			for zz=-d/2+11,d/2-7,24 do
				ix+=1
				local p=part(m,"FluorescentPanel",V(8,.13,3.5),CF(x+xx,y-.36,z+zz),Color3.fromRGB(234,240,220),Enum.Material.Neon,false)
				part(m,"LightPanelFrame",V(8.4,.1,3.9),CF(x+xx,y-.27,z+zz),C.white)
				if ix%3==1 then
					local light=Instance.new("SurfaceLight"); light.Face=Enum.NormalId.Bottom; light.Color=Color3.fromRGB(249,240,207)
					light.Brightness=1.25; light.Range=60; light.Angle=150; light.Shadows=false; light.Parent=p; lightCount+=1
				end
			end
		end
		if style=="warehouse" then for zz=-d/2+10,d/2,25 do part(m,"ExposedCeilingBeam",V(w,1,.5),CF(x,y-1.3,z+zz),C.white) end end
	end
	local function boundary(into,x,z,w,d,height)
		for _,s in ipairs({-1,1}) do part(into,"EnclosureWall",V(1.2,height,d),CF(x+s*w/2,height/2,z),C.cream) end
	end
	local function bay(into,frame,w,h,lit)
		local center=w*.52; local side=w*.31
		part(into,"BayBase",V(w,2.6,4.4),frame*CF(0,1.3,-1.8),C.pale)
		window(into,frame*CF(0,2.6+h/2,-4),center,h,lit)
		for _,s in ipairs({-1,1}) do
			window(into,frame*CF(s*(center/2+side*.32),2.6+h/2,-2.5)*CFrame.Angles(0,s*math.rad(42),0),side,h,lit)
		end
		part(into,"BayCornice",V(w+.8,.55,4.9),frame*CF(0,h+2.95,-1.8),C.white)
	end

	-- A: the first reveal is a multi-level residential atrium under a low office ceiling.
	local A=model("A_BalconyAtrium")
	floor(A,"AtriumCarpet",0,0,36,220,80)
	boundary(A,0,36,220,80,44)
	part(A,"EntranceBackWall",V(220,44,1),CF(0,22,-4),C.cream)
	for _,s in ipairs({-1,1}) do
		for i,z in ipairs({13,38,63}) do
			local yaw=s==1 and math.rad(90) or math.rad(-90)
			for level=0,2 do
				house(A,"AtriumHouse_"..s.."_"..i.."_"..level,CF(s*80,level*14,z)*CFrame.Angles(0,yaw,0),23,20,13.8,(i+level)%2==0 and C.cream or C.pale,nil,{open=level<2,lit=level==2 and i%2==0,cutaway=level==2 and i==2})
			end
		end
		for _,height in ipairs({14,28}) do
			if s==-1 and height==28 then
				floor(A,"UpperBalconyBeforeStairwell",-69,28,18,22,42)
				floor(A,"UpperBalconyAfterStairwell",-69,28,71,22,8)
				floor(A,"UpperStairwellOuterWalk",-77,28,53.5,6,29)
				floor(A,"UpperStairwellInnerWalk",-60,28,53.5,4,29)
				rail(A,CF(-75,28,53.5)*CFrame.Angles(0,math.rad(90),0),27)
				rail(A,CF(-63,28,53.5)*CFrame.Angles(0,math.rad(90),0),27)
			else floor(A,"BalconyCarpet",s*69,height,36,22,78) end
			if height==14 then
				rail(A,CF(s*58,height,22)*CFrame.Angles(0,math.rad(90),0),22)
				rail(A,CF(s*58,height,60)*CFrame.Angles(0,math.rad(90),0),26)
			else rail(A,CF(s*58,height,42)*CFrame.Angles(0,math.rad(90),0),62) end
		end
		for _,z in ipairs({8,70}) do part(A,"SquareAtriumColumn",V(2,42,2),CF(s*57,21,z),C.pale) end
	end
	floor(A,"AtriumBridge",0,14,40,117,11)
	-- Open only the two stair approaches; do not put a cross-bridge rail across
	-- either staircase's top tread.
	rail(A,CF(-55,14,34.5),6); rail(A,CF(10,14,34.5),96)
	rail(A,CF(-10,14,45.5),96); rail(A,CF(55,14,45.5),6)
	stairs(A,"FirstBalconyStair",CF(-45,0,6),11,14,28,28,C.carpet,true)
	floor(A,"FirstStairLanding",-51.5,14,36,23,5)
	stairs(A,"ReturnBalconyStair",CF(45,0,74)*CFrame.Angles(0,math.pi,0),11,14,28,28,C.carpet,true)
	floor(A,"ReturnStairLanding",51.5,14,44,23,5)
	stairs(A,"UpperBalconyStair",CF(-69,14,40),10,14,27,28,C.carpet,true)
	floor(A,"UpperLanding",-69,28,69,22,7)
	ceiling(A,"OfficeCeiling",0,36,220,80,44)

	-- B: a compact pastel suburb. The apparent lawns are fibrous indoor green carpet.
	local B=model("B_PastelCarpetCourt")
	floor(B,"GreenCarpetCourt",0,0,111,220,72,C.green)
	boundary(B,0,111,220,72,44)
	for _,s in ipairs({-1,1}) do part(B,"CourtToStreetWingWall",V(58.5,44,1),CF(s*80.75,22,147),C.cream) end
	part(B,"CourtToStreetCeilingStepCap",V(103,7,1.2),CF(0,40.5,147),C.cream)
	for _,s in ipairs({-1,1}) do
		for i,z in ipairs({94,128}) do
			local hue=({C.rose,C.blue,C.lavender,C.yellow})[(s==1 and 2 or 0)+i]
			house(B,"PastelHouse_"..s.."_"..i,CF(s*68,0,z)*CFrame.Angles(0,s*math.rad(90),0),27,21,13.5,hue,i==1 and C.lavender or C.blue,{open=true})
			floor(B,"Doorstep",s*60,0,z,10,9,C.carpet)
		end
	end
	for _,s in ipairs({-1,1}) do house(B,"DistantGabledHouse_"..s,CF(s*33,0,135),23,12,12.5,s==1 and C.pale or C.rose,C.blue,{open=false,lit=true}) end
	-- Carpet inset paths lead naturally between the open house interiors.
	floor(B,"CourtWalkway",0,.035,110,15,68,C.carpet)
	floor(B,"CrossCourtWalkway",0,.045,106,131,8,C.carpet)
	for _,s in ipairs({-1,1}) do
		part(B,"LongCourtSkirting",V(.7,1.2,70),CF(s*99,.6,111),C.pale)
		for _,z in ipairs({88,119}) do
			part(B,"CarpetPlanterRim",V(8,.45,3),CF(s*48,.23,z),C.white)
			for k=1,3 do local p=part(B,"ArtificialShrub",V(1.8,2.2,1.7),CF(s*48-3+k*1.5,1.35,z),Color3.fromRGB(64,90,58),Enum.Material.Grass,false); p.Shape=Enum.PartType.Ball end
		end
	end
	ceiling(B,"PastelCourtCeiling",0,111,220,72,44)

	-- C: pink carpet stairs descend through a yellow miniature-house street.
	local S=model("C_SunkenPorchStreet")
	floor(S,"LowerGreenCarpet",0,-12,184,102,78,C.green)
	boundary(S,0,184,110,78,37)
	-- The generic enclosure begins at y=0. These retaining walls contain the
	-- deliberately sunken floor, including underneath the raised side porches.
	for _,s in ipairs({-1,1}) do
		part(S,"SunkenStreetRetainingSide",V(1.2,13,78),CF(s*51,-6.5,184),C.yellow)
		part(S,"SunkenStreetRetainingEnd",V(102,13,1.2),CF(0,-6.5,184+s*39),C.yellow)
	end
	for _,s in ipairs({-1,1}) do
		floor(S,"RaisedPorchWalk",s*36,0,183,25,76,C.yellow)
		for i,z in ipairs({158,181,205}) do
			local f=CF(s*42,0,z)*CFrame.Angles(0,s*math.rad(90),0)
			house(S,"PorchHouse_"..s.."_"..i,f,19,11,11.8,i%2==0 and C.yellow or C.rose,i%2==0 and C.blue or C.lavender,{open=i~=2})
			-- Broad domestic wallpaper panels are explicit replaceable texture surfaces.
			local wp=part(S,"FloralWallpaperPanel",V(.16,12,15),CF(s*54,17,z),Color3.fromRGB(210,196,146),Enum.Material.SmoothPlastic,false)
			texture(wp,config.FloralTexture,s==1 and Enum.NormalId.Left or Enum.NormalId.Right,12)
			if not config.FloralTexture then
				for row=0,2 do for col=0,2 do
					local xf=s*53.88; local yy=12.5+row*3.6; local zz=z-5+col*4.7
					local petal=part(S,"WallpaperRose",V(.055,.7,.85),CF(xf,yy,zz)*CFrame.Angles(math.rad(45),0,0),C.rose,Enum.Material.SmoothPlastic,false)
					part(S,"WallpaperLeaf",V(.055,.35,1.05),CF(xf-s*.01,yy-.65,zz+.35)*CFrame.Angles(math.rad(-28),0,0),Color3.fromRGB(102,128,84),Enum.Material.SmoothPlastic,false)
				end end
			end
		end
		rail(S,CF(s*23.5,0,157)*CFrame.Angles(0,math.rad(90),0),22)
		rail(S,CF(s*23.5,0,207)*CFrame.Angles(0,math.rad(90),0),27)
	end
	stairs(S,"LongPinkDescent",CF(0,0,148),14,-12,28,28,C.pink,true)
	floor(S,"SunkenStreetLanding",0,-12,184,14,22,C.pink)
	stairs(S,"PinkStreetAscent",CF(0,-12,194),14,12,28,28,C.pink,true)
	stairs(S,"RightPorchSteps",CF(12,-12,184)*CFrame.Angles(0,math.rad(90),0),8,12,22,24,C.pink,true)
	stairs(S,"LeftPorchSteps",CF(-12,-12,184)*CFrame.Angles(0,math.rad(-90),0),8,12,22,24,C.pink,true)
	-- Large level landings connect the elevated optional route at both ends.
	floor(S,"StreetEntryLanding",0,0,147,103,2,C.carpet)
	floor(S,"StreetExitLanding",0,0,222,103,5,C.carpet)
	ceiling(S,"WallpaperStreetCeiling",0,184,110,78,37)

	-- D: the large reveal is a bounded courtyard, with six scenic storeys and three playable ones.
	local D=model("D_ImpossibleHouseStacks")
	floor(D,"StackCourtCarpet",0,0,262,220,82,C.green)
	boundary(D,0,262,220,82,89)
	for _,s in ipairs({-1,1}) do
		part(D,"StreetToCourtWingWall",V(55,39,1),CF(s*82.5,19.5,221.5),C.cream)
		part(D,"CourtToFinalWingWall",V(52,44,1),CF(s*84,22,302.5),C.cream)
	end
	-- Stepped ceiling heights must be physically enclosed above the openings.
	-- The previous full-height view through these risers exposed the skybox.
	part(D,"StreetToHighCourtCeilingStepCap",V(220,52,1.2),CF(0,63,221.5),C.cream)
	part(D,"HighCourtToFinalCeilingStepCap",V(220,55,1.2),CF(0,61.5,302.5),C.cream)
	for _,s in ipairs({-1,1}) do
		local tower=model("BayWindowTower_"..s,D)
		for level=0,5 do
			local h=level*13.5
			local f=CF(s*70,h,262)*CFrame.Angles(0,s*math.rad(90),0)
			house(tower,"StackedResidence_"..level,f,32,25,13.3,level%2==0 and C.pale or C.cream,nil,{open=level<3,lit=level%3==1,cutaway=level==4 and s==-1})
			for _,q in ipairs({-1,1}) do bay(tower,f*CF(q*10,0,-.5),8,7.2,(level+q)%3==0) end
			floor(tower,"StackBalcony",0,0,-6,36,10,C.carpet,f)
			rail(tower,f*CF(-11,0,-11),12)
			rail(tower,f*CF(11,0,-11),12)
			for _,q in ipairs({-1,1}) do rail(tower,f*CF(q*17.5,0,-6)*CFrame.Angles(0,math.rad(90),0),10) end
			part(tower,"LayerCornice",V(33,.4,26),f*CF(0,13.2,12.5),C.white)
		end
		-- Real stairs connect lower landings; upper repetitions remain visual architecture.
		stairs(D,"StackLowerStair_"..s,CF(s*48,0,227),10,13.5,27,27,C.carpet,true)
		floor(D,"StackFirstLanding",s*48,13.5,256,14,7)
		floor(D,"StackFirstConnector",s*54,13.5,260,20,8)
		stairs(D,"StackUpperStair_"..s,CF(s*47,13.5,260),10,13.5,27,27,C.carpet,true)
		floor(D,"StackSecondLanding",s*54,27,291,25,8)
		floor(D,"StackUpperConnection",s*60,27,275,12,28)
	end
	floor(D,"SkyBridge",0,13.5,259,121,8)
	rail(D,CF(0,13.5,255),85); rail(D,CF(0,13.5,263),83)
	for _,s in ipairs({-1,1}) do
		rail(D,CF(s*57.25,13.5,255),6.5)
		rail(D,CF(s*56.5,13.5,263),8)
	end
	floor(D,"UpperSkyBridge",0,27,291,121,8)
	rail(D,CF(0,27,287),83); rail(D,CF(0,27,295),121)
	for _,s in ipairs({-1,1}) do rail(D,CF(s*56.5,27,287),8) end
	for _,x in ipairs({-36,-12,12,36}) do
		local p=part(D,"BridgeUndersideFluorescent",V(5,.14,2),CF(x,12.17,259),Color3.fromRGB(244,239,209),Enum.Material.Neon,false)
		local l=Instance.new("SurfaceLight"); l.Face=Enum.NormalId.Bottom; l.Color=Color3.fromRGB(249,241,216)
		l.Range=55; l.Brightness=1.4; l.Angle=160; l.Shadows=false; l.Parent=p; lightCount+=1
	end
	local tilted=house(D,"ImpossibleTiltedHouse",CF(0,42,270)*CFrame.Angles(0,0,math.rad(-24)),31,22,14,C.rose,C.blue,{open=false,lit=true})
	tilted:SetAttribute("ScenicOnly",true)
	-- Its slab meets the house floor, and offset cutaway volumes embed it into
	-- the towers. The silhouette reads as fused domestic architecture, not a
	-- lone hovering asset. All added masses remain above playable headroom.
	floor(D,"TiltedCarpetSlab",0,0,11,39,28,C.green,CF(0,42,270)*CFrame.Angles(0,0,math.rad(-24)))
	local function embeddedRoom(name,frame)
		local m=model(name,D); m:SetAttribute("ScenicOnly",true)
		floor(m,"EmbeddedRoomFloor",0,0,9,54,18,C.carpet,frame)
		part(m,"EmbeddedRoomCeiling",V(54,.65,18),frame*CF(0,12,9),C.pale)
		part(m,"EmbeddedRoomBackWall",V(54,12,.65),frame*CF(0,6,18),C.cream)
		part(m,"ExposedRoomApron",V(54,2.4,.65),frame*CF(0,1.2,0),C.pale)
		part(m,"ExposedRoomLintel",V(54,1,.65),frame*CF(0,11.5,0),C.pale)
		for _,s in ipairs({-1,1}) do
			part(m,"EmbeddedRoomSideWall",V(.65,12,18),frame*CF(s*27,6,9),C.cream)
			part(m,"ExposedWhiteWallEdge",V(.35,12,.85),frame*CF(s*26.6,6,-.12),C.white)
		end
		part(m,"ExposedFloorMoulding",V(54,.35,.95),frame*CF(0,.15,-.15),C.white)
		part(m,"ExposedCeilingMoulding",V(54,.45,.95),frame*CF(0,11.85,-.15),C.white)
	end
	embeddedRoom("LeftEmbeddedHouseVolume",CF(-39,52,272)*CFrame.Angles(0,0,math.rad(-18)))
	embeddedRoom("RightEmbeddedHouseVolume",CF(39,39,273)*CFrame.Angles(0,0,math.rad(7)))
	for _,s in ipairs({-1,1}) do
		part(D,"CourtyardColumn",V(2.2,84,2.2),CF(s*104,42,250),C.pale)
		floor(D,"CourtEdgePath",s*25,.04,260,10,72,C.carpet)
	end
	floor(D,"FinalApproach",0,.05,294,61,10,C.carpet)
	ceiling(D,"HighIndoorRoof",0,262,220,82,89,"warehouse")

	-- E: a real final house interior. Its rear passage is accessible for this map-only preview.
	local E=model("E_FinalPuzzleHouseAndChute")
	floor(E,"FinalHouseCourt",0,0,318,116,35,C.carpet)
	boundary(E,0,324,116,46,34)
	for _,s in ipairs({-1,1}) do
		floor(E,"FinalSideCourt",s*39.5,0,341.5,37,13,C.carpet)
		part(E,"FinalEnclosureBackWall",V(54,34,1),CF(s*31,17,347),C.cream)
	end
	part(E,"FinalEnclosureBackHeader",V(8,24,1),CF(0,22,347),C.cream)
	local finalHouse=house(E,"FinalHouse",CF(0,0,317),42,27,14,C.pale,C.blue,{open=true,backOpening=true})
	finalHouse:SetAttribute("PuzzleReady",true)
	finalHouse:SetAttribute("FutureDoorPlaneZ",344)
	for _,s in ipairs({-1,1}) do
		part(finalHouse,"InteriorRoomDivider",V(.55,14,8),CF(s*12,7,322),C.cream)
		part(finalHouse,"EmptyPictureFrame",V(4.5,3.7,.24),CF(s*13,7,343.5),C.white,Enum.Material.Wood)
		part(finalHouse,"EmptyPictureInset",V(3.8,3,.25),CF(s*13,7,343.32),C.cream)
	end
	part(finalHouse,"PuzzleReadySideboard",V(12,3,2),CF(0,1.5,331),Color3.fromRGB(135,111,82),Enum.Material.Wood)
	for _,x in ipairs({-4,0,4}) do
		part(finalHouse,"UnwiredLampBase",V(.9,.2,.9),CF(x,3.1,331),C.white,Enum.Material.Metal)
		part(finalHouse,"UnwiredLampStem",V(.15,1.2,.15),CF(x,3.75,331),C.white,Enum.Material.Metal)
		part(finalHouse,"UnwiredLampShade",V(1.4,.8,1.4),CF(x,4.7,331),C.pale,Enum.Material.Fabric)
	end
	for _,s in ipairs({-1,1}) do
		local arrow=part(finalHouse,"ExitArrowArtSurface",V(4.7,4.7,.04),CF(s*7.5,6,343.58),C.pale,Enum.Material.SmoothPlastic,false)
		if config.ArrowTexture then local decal=Instance.new("Decal"); decal.Name="PaintedExitArrow"; decal.Texture=tostring(config.ArrowTexture); decal.Face=Enum.NormalId.Front; decal.Parent=arrow
		else
			part(finalHouse,"PaintedArrowShaft",V(3,.18,.05),CF(s*7.5,6,343.53),C.red,Enum.Material.SmoothPlastic,false)
			for _,v in ipairs({-1,1}) do part(finalHouse,"PaintedArrowHead",V(1.4,.18,.055),CF(s*6.5,6+v*.43,343.51)*CFrame.Angles(0,0,s*v*math.rad(40)),C.red,Enum.Material.SmoothPlastic,false) end
		end
	end
	ceiling(E,"FinalHouseEnclosureCeiling",0,324,116,46,34)
	local chute=model("NarrowDescent",E)
	local chuteStart=V(0,0,344)
	local bend=V(0,-11,371)
	local chuteEnd=V(0,-28,386)
	local function chuteSegment(a,b,dark)
		local length=(b-a).Magnitude
		local f=CFrame.lookAt((a+b)/2,b)
		part(chute,"SmoothSlopingFloor",V(7.2,.85,length+.6),f*CF(0,-.43,0),dark and C.dark or C.carpet,Enum.Material.SmoothPlastic)
		for _,s in ipairs({-1,1}) do part(chute,"CloseChuteWall",V(.7,8.7,length+.6),f*CF(s*3.95,4.3,0),dark and Color3.fromRGB(5,6,6) or C.cream) end
		part(chute,"LowChuteCeiling",V(8.6,.65,length+.6),f*CF(0,8.7,0),dark and Color3.fromRGB(5,6,6) or C.ceiling)
		if not dark then
			part(chute,"LastFluorescent",V(3,.12,1.7),f*CF(0,8.3,length*.25),Color3.fromRGB(185,191,154),Enum.Material.Neon,false)
		end
	end
	chuteSegment(chuteStart,bend,false)
	chuteSegment(bend,chuteEnd,true)
	-- A contained black landing avoids dropping preview visitors into the void.
	floor(chute,"DarkArrivalFloor",0,-28,390,8,9,Color3.fromRGB(3,4,4))
	part(chute,"DarkArrivalCeiling",V(8,.7,9),CF(0,-19.3,390),Color3.fromRGB(3,4,4))
	for _,s in ipairs({-1,1}) do part(chute,"DarkArrivalSide",V(.7,9,9),CF(s*4,-23.5,390),Color3.fromRGB(3,4,4)) end
	part(chute,"DarkArrivalEnd",V(8,9,.7),CF(0,-23.5,394.5),Color3.fromRGB(3,4,4))
	chute:SetAttribute("GeometryOnly_NoSlideOrCompletion",true)
	chute:SetAttribute("SuggestedSlideStartFraction",.7)
	root:SetAttribute("PartCount",partCount); root:SetAttribute("LightCount",lightCount)
	root:SetAttribute("Design", "Unknown-origin Backrooms; visitors are researchers. No organisation created this place.")
	local function world(v) return origin+v end
	return {
		Model=root,
		SpawnCFrame=CFrame.lookAt(world(V(0,3,5)),world(V(0,3,38))),
		PreviewCameras={
			{name="Atrium",position=world(V(-34,12,7)),lookAt=world(V(52,18,49))},
			{name="PastelCourt",position=world(V(-21,7,80)),lookAt=world(V(45,9,127))},
			{name="PorchStreet",position=world(V(0,8,146)),lookAt=world(V(8,-2,199))},
			{name="HouseStacks",position=world(V(-22,9,224)),lookAt=world(V(18,42,271))},
			{name="FinalHouse",position=world(V(-11,7,306)),lookAt=world(V(0,7,334))},
			{name="Chute",position=world(V(0,5,342)),lookAt=world(V(0,-12,375))},
		},
		Waypoints={world(V(0,3,5)),world(V(0,3,68)),world(V(0,3,110)),world(V(0,3,145)),world(V(0,-9,180)),world(V(0,3,224)),world(V(0,3,282)),world(V(0,3,315)),world(V(0,3,339))},
		FinalHouse=finalHouse,
		ChuteStart=CFrame.new(world(chuteStart)),
		ChuteEnd=CFrame.new(world(chuteEnd)),
		Bounds={Min=world(V(-111,-30,-5)),Max=world(V(111,90,395))},
	}
end

return Architecture
