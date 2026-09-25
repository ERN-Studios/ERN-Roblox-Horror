-- Level 5: The Indoor Suburbs. Geometry only; deliberately independent of Level 4.
-- All authored coordinates are relative to origin. No Lighting, entity or quest mutation.
local Architecture = {}

function Architecture.Build(parent, origin, config)
	config = table.clone(config or {})
	config.ExitArrowTexture = config.ExitArrowTexture or "rbxassetid://136557095207787"
	config.ExitArrowLeftTexture = config.ExitArrowLeftTexture or "rbxassetid://119578216618152"
	config.FurnitureUpholsteryTexture = config.FurnitureUpholsteryTexture or "rbxassetid://132119936960491"
	config.FurnitureTVTexture = config.FurnitureTVTexture or "rbxassetid://129933596500815"
	local Furniture = require(script.Parent:WaitForChild("Level 5 Furniture"))
	local furnitureKit
	local furnishedHomes={
		LowEavesResidence_1_1=1,DetachedWaitingRoom_1=4,
		CourtCottage_01=1,CourtCottage_02=2,CourtCottage_03=3,
		CourtCottage_05=4,CourtCottage_07=5,CourtCottage_11=1,
		["TerraceHouse_-1_2"]=3,TerraceHouse_1_3=2,
		CutawayReadingRoom=5,
		GroundBlueStarterHouse=1,RosePorchHouse=3,
		SecretThroughHouse=4,HighTerraceCreamHouse=2,HighTerracePinkHouse=5,
	}
	origin = origin or Vector3.zero
	local root = Instance.new("Model")
	root.Name = "Level5_IndoorSuburbs"
	root:SetAttribute("ArchitectureVersion", "2026-09-25.1")
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
		p.CanCollide=collide~=false; p.CanQuery=collide~=false; p.CanTouch=false; p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
		p.CastShadow=collide~=false and math.min(size.X,size.Y,size.Z)>.4
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
		local glass=part(into,"WindowGlass",V(w,h,.14),frame,C.glass,Enum.Material.Glass)
		glass.Transparency=.2
		glass.Reflectance=0
		glass:SetAttribute("Level5TintedWindow",true)
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
	local function wallLamp(_into,_frame)
		-- Individual homes have no exterior/interior lamps or luminous fixtures.
		-- Shared room ceilings provide the architectural light.
	end
	local function house(into,name,frame,w,d,h,color,roofColor,options)
		options=options or {}; local m=model(name,into)
		floor(m,"InteriorCarpet",0,0,d/2,w,d,C.carpet,frame)
		if options.cutaway then
			-- A few upper rooms have exposed wall sections, as in the reference.
			-- These are fixed architectural cuts rather than destructible objects.
			if options.open then
				-- Walkable cutaway rooms retain broken wall edges around a clear entrance.
				local wing=(w-7)/2
				for _,sign in ipairs({-1,1}) do part(m,"CutawayWallApron",V(wing,2.4,.7),frame*CF(sign*(3.5+wing/2),1.2,0),color,Enum.Material.Plaster) end
			else
				part(m,"CutawayWallApron",V(w,2.4,.7),frame*CF(0,1.2,0),color,Enum.Material.Plaster)
			end
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
		m:SetAttribute("HouseLighting","None")
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
		local variant=furnishedHomes[name]
		if name=="CanyonDwelling_0" and (into.Name=="WestHouseStack2" or into.Name=="EastHouseStack3") then variant=into.Name=="WestHouseStack2" and 1 or 4 end
		if furnitureKit and variant and options.open~=false then
			Furniture.FurnishHome(furnitureKit,m,frame,w,d,h,{variant=variant,open=true,backOpening=options.backOpening,glitchedTable=name=="CourtCottage_03"})
			m:SetAttribute("FurnitureRoomFrame",offset*frame)
			m:SetAttribute("FurnitureRoomSize",V(w,h,d))
		end
		return m
	end
	local function ceiling(into,name,x,z,w,d,y,style)
		local m=model(name,into)
		local tint=style=="domestic" and C.pale or (style=="low" and Color3.fromRGB(177,172,145) or C.ceiling)
		part(m,"CeilingPlane",V(w,.6,d),CF(x,y,z),tint)
		local tile=style=="warehouse" and 24 or style=="domestic" and 9 or 15
		for xx=-w/2,w/2,tile do part(m,"CeilingGrid",V(.08,.08,d),CF(x+xx,y-.34,z),C.grid,nil,false) end
		for zz=-d/2,d/2,tile do part(m,"CeilingGrid",V(w,.08,.08),CF(x,y-.34,z+zz),C.grid,nil,false) end
		local sx,sz=style=="domestic" and 36 or 40,style=="domestic" and 32 or 40
		local ix=0
		for xx=-w/2+sx/2,w/2-8,sx do for zz=-d/2+sz/2,d/2-7,sz do
			ix+=1
			-- Static tube wear: different colour temperatures, weak ballast output
			-- and truly dead panels. No strobing or per-frame light loops.
			local pattern=ix+math.floor(z/40)
			local failed=pattern%7==0
			local dim=not failed and pattern%5==0
			local warmth=(pattern+math.floor(x/20))%3
			local fixtureColor=warmth==0 and Color3.fromRGB(223,208,167)
				or warmth==1 and Color3.fromRGB(185,211,219) or Color3.fromRGB(214,222,202)
			local lightColor=warmth==0 and Color3.fromRGB(250,223,178)
				or warmth==1 and Color3.fromRGB(212,231,245) or Color3.fromRGB(232,236,211)
			if style=="low" and warmth~=1 then fixtureColor=Color3.fromRGB(207,195,153) end
			if dim then fixtureColor=fixtureColor:Lerp(Color3.fromRGB(80,83,69),.48) end
			if failed then fixtureColor=Color3.fromRGB(67,65,56) end
			local p=part(m,"FluorescentPanel",V(style=="domestic" and 4 or 8,.13,2.6),CF(x+xx,y-.46,z+zz),fixtureColor,failed and Enum.Material.SmoothPlastic or Enum.Material.Neon,false)
			p:SetAttribute("FailedTube",failed)
			p:SetAttribute("TubeState",failed and "Off" or dim and "Dim" or "On")
			p:SetAttribute("ColourTemperature",warmth==0 and "Warm" or warmth==1 and "Cool" or "Neutral")
			part(m,"LightPanelFrame",V(p.Size.X+.4,.12,3),CF(x+xx,y-.34,z+zz),C.white,nil,false)
			if ix%4==1 and not failed then
				local light=Instance.new("SurfaceLight");light.Face=Enum.NormalId.Bottom;light.Color=lightColor
				light.Brightness=dim and .3 or warmth==1 and .72 or .95
				light.Range=math.min(y+8,60);light.Angle=160;light.Shadows=false;light.Parent=p;lightCount+=1
			end
		end end
		if style=="warehouse" then
			for zz=-d/2+10,d/2,36 do
				part(m,"ExposedCeilingBeam",V(w,.8,.6),CF(x,y-1.3,z+zz),C.white,nil,false)
				for xx=-w/2+25,w/2-5,50 do
					beam(m,"WarehouseTrussDiagonal",V(x+xx-18,y-1.6,z+zz),V(x+xx+18,y-5.7,z+zz),.22,C.pale)
				end
			end
		end
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

	local K={root=root,config=config,C=C,V=V,CF=CF,model=model,part=part,floor=floor,
		beam=beam,rail=rail,stairs=stairs,window=window,doorframe=doorframe,facade=facade,
		house=house,texture=texture,wallLamp=wallLamp,bay=bay,ceiling=ceiling}
	furnitureKit=K
	-- A: the first reveal is a multi-level residential atrium under a low office ceiling.
	local A=model("A_BalconyAtrium")
	floor(A,"AtriumCarpet",0,0,36,220,80)
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

	-- B: compress the player into a low, long residential arcade before the
	-- larger village reveal. Deep corners and offset islands break the sightline.
	local B=model("B_LowEavesArcade")
	floor(B,"WornOchreCarpet",0,0,136,220,120,Color3.fromRGB(148,137,99))
	floor(B,"ArcadeRunner",0,.025,136,15,118,Color3.fromRGB(102,94,72))
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({94,128,167}) do
			local f=CF(side*(i==2 and 72 or 82),0,z)*CFrame.Angles(0,side*math.pi/2,0)
			local m=house(B,"LowEavesResidence_"..side.."_"..i,f,24,19,12.3,i==2 and C.cream or C.yellow,nil,{open=true})
			part(m,"BroadFlatPorchCanopy",V(28,.7,7),f*CF(0,12.7,-3),C.pale)
			for _,sign in ipairs({-1,1}) do
				part(m,"PorchPost",V(.7,12.4,.7),f*CF(sign*12,6.2,-5.7),C.white)
				part(m,"WoodShutter",V(1.1,7.4,.28),f*CF(sign*10.65,6.5,-.45),Color3.fromRGB(115,125,100),Enum.Material.Wood)
			end
			floor(m,"DeepCarpetPorch",0,.05,-3,28,6,C.carpet,f)


		end
	end
	-- Two detached low room islands can be explored on either side and through.
	for i,item in ipairs({{x=-28,z=107,c=C.pale},{x=29,z=160,c=C.cream}}) do
		local f=CF(item.x,0,item.z)*CFrame.Angles(0,i==1 and math.rad(-8) or math.rad(7),0)
		local m=house(B,"DetachedWaitingRoom_"..i,f,28,22,11.8,item.c,nil,{open=true,backOpening=true})
		part(m,"LowCofferedRoof",V(31,.6,26),f*CF(0,12.35,11),C.cream)
		part(m,"SilentTelephoneShelf",V(5,.3,1.5),f*CF(-9,3,15),Color3.fromRGB(116,97,71),Enum.Material.Wood)
		for _,s in ipairs({-1,1}) do wallLamp(m,f*CF(s*12,8,-.6)) end
	end
	for _,x in ipairs({-51,51}) do
		for _,z in ipairs({82,116,151,189}) do
			part(B,"LowArcadeSquareColumn",V(1.4,18,1.4),CF(x,9,z),C.pale)
		end
		part(B,"DroppedLongSoffit",V(5,2.8,120),CF(x,16.6,136),C.cream)
	end
	for _,z in ipairs({83,137,188}) do floor(B,"LoopCrossing",0,.045,z,158,7,C.carpet) end

	local neighbourhood=require(script.Parent:WaitForChild("Level 5 Neighbourhood Districts"))
	local landmarks=require(script.Parent:WaitForChild("Level 5 Landmark Districts"))
	local N=neighbourhood.Build(K)
	local L=landmarks.Build(K)
	local domestic=root:FindFirstChild("E_DomesticLabyrinth")
	for _,room in ipairs({{name="WestLoungeFurniture",x=-35,z=696,w=26,d=24,v=2},{name="EastReadingFurniture",x=65,z=696,w=32,d=22,v=4}}) do
		local m=model(room.name,domestic)
		local f=CF(room.x,0,room.z)
		Furniture.FurnishHome(K,m,f,room.w,room.d,14.8,{variant=room.v,open=true,backOpening=true})
		m:SetAttribute("FurnitureRoomFrame",offset*f);m:SetAttribute("FurnitureRoomSize",V(room.w,14.8,room.d))
	end

	-- Separate room envelopes, each with its own ceiling and deliberately narrow
	-- threshold. No sightline can mistake this for one giant shared warehouse.
	local zones={
		{id="A",name="Balcony Atrium",model="A_BalconyAtrium",width=220,z0=-4,z1=76,height=44,style="office",wall=C.cream},
		{id="B",name="Low Eaves Arcade",model="B_LowEavesArcade",width=220,z0=76,z1=196,height=18,style="low",wall=C.yellow},
		{id="C",name="Pastel Village",model="C_PastelVillage",width=360,z0=196,z1=436,height=48,style="office",wall=C.pale},
		{id="D",name="Floral Terraces",model="D_FloralTerraces",width=180,z0=436,z1=636,height=32,minY=-14,style="low",wall=C.yellow},
		{id="E",name="Domestic Labyrinth",model="E_DomesticLabyrinth",width=200,z0=636,z1=796,height=15,style="domestic",wall=C.pale},
		{id="F",name="Bay Window Canyon",model="F_BayWindowCanyon",width=300,z0=796,z1=1016,height=108,style="warehouse",wall=C.cream},
		{id="G",name="Tilted Subdivision",model="G_TiltedSubdivision",width=320,z0=1016,z1=1196,height=66,style="warehouse",wall=C.pale},
		{id="H",name="Last House",model="H_LastHouse",width=120,z0=1196,z1=1276,height=26,style="domestic",wall=C.cream},
	}
	local totalFootprint=0
	for index,z in ipairs(zones) do
		local m=root:FindFirstChild(z.model) or model(z.model)
		m:SetAttribute("BiomeName",z.name);m:SetAttribute("CeilingY",z.height)
		m:SetAttribute("GroundEnvelopeArea",z.width*(z.z1-z.z0))
		local enclosure=model("Enclosure",m)
		local bottom=z.minY or 0
		for _,s in ipairs({-1,1}) do
			part(enclosure,"DistrictSideWall",V(1.2,z.height-bottom,z.z1-z.z0),CF(s*z.width/2,(z.height+bottom)/2,(z.z0+z.z1)/2),z.wall)
			part(enclosure,"ContinuousBaseboard",V(.45,.8,z.z1-z.z0),CF(s*(z.width/2-.65),.4,(z.z0+z.z1)/2),C.white,nil,false)
		end
		for _,isBack in ipairs({false,true}) do
			local edge=isBack and (z.z1-.04) or (z.z0+.04)
			local isEntrance=index==1 and not isBack
			local isChute=index==#zones and isBack
			local opening=isChute and 9.3 or 22
			local openingHeight=isChute and 11 or 14
			local wallBottom=isChute and -35 or bottom
			if isEntrance then
				part(enclosure,"ArrivalBackWall",V(z.width,z.height,1.3),CF(0,z.height/2,edge),z.wall)
			else
				local wing=(z.width-opening)/2
				for _,s in ipairs({-1,1}) do
					part(enclosure,"ThresholdSideWall",V(wing,z.height-wallBottom,1.1),CF(s*(opening/2+wing/2),(z.height+wallBottom)/2,edge),z.wall)
				end
				part(enclosure,"ThresholdHighClosure",V(opening,z.height-openingHeight,1.1),CF(0,(z.height+openingHeight)/2,edge),z.wall)
				if not isChute then
					for _,s in ipairs({-1,1}) do part(enclosure,"WideThresholdJamb",V(.55,14,.9),CF(s*11,7,edge-.7),C.white) end
					part(enclosure,"WideThresholdTrim",V(22.5,.5,.9),CF(0,14.15,edge-.7),C.white)
				end
			end
		end
		ceiling(enclosure,z.name.."Ceiling",0,(z.z0+z.z1)/2,z.width,z.z1-z.z0,z.height,z.style)

		totalFootprint+=z.width*(z.z1-z.z0)
	end
	-- Dark fungal colonies grow from different damp seams; no pictorial wall art.
	local growth=model("MyceliumWallGrowth")
	local moldAssets={
		rising="rbxassetid://111130507669211",
		corner="rbxassetid://84997095468417",
		seam="rbxassetid://119550867817499",
	}
	local function wallMold(name,position,look,width,height,variant,growthOrigin)
		local surface=part(growth,name,V(width,height,.015),CFrame.lookAt(position,look),C.pale,Enum.Material.SmoothPlastic,false)
		surface.Transparency=1;surface.CastShadow=false;surface.CanQuery=false;surface.CanTouch=false
		surface:SetAttribute("Level5WallMold",true);surface:SetAttribute("AlphaBackground",true)
		surface:SetAttribute("MoldVariant",variant);surface:SetAttribute("GrowthOrigin",growthOrigin)
		local decal=Instance.new("Decal");decal.Name="DarkMyceliumOnPlaster";decal.Texture=moldAssets[variant];decal.Face=Enum.NormalId.Front
		decal.Color3=Color3.fromRGB(168,164,150);decal.Transparency=.04;decal.Parent=surface
	end
	-- Bottom edges meet the floor or the raised terrace. Upper colonies originate
	-- at wall joints; none of the carriers crosses the central threshold opening.
	wallMold("VillageFloorSpread",V(-179.32,22.05,319),V(0,22.05,319),58.67,44,"corner","Floor corner")
	wallMold("CanyonRearRising",V(55,48.05,1015.31),V(55,48.05,900),72,96,"rising","Floor seam")
	wallMold("CanyonWestRising",V(-149.32,45.05,902),V(0,45.05,902),67.5,90,"rising","Floor seam")
	wallMold("SubdivisionTerraceSpread",V(159.32,39.05,1092),V(0,39.05,1092),61.33,46,"corner","Raised terrace floor")
	wallMold("CanyonUpperSeam",V(149.32,75,866),V(0,75,866),52,52,"seam","Upper wall seam")
	wallMold("SubdivisionUpperSeam",V(-159.32,46,1148),V(0,46,1148),36,36,"seam","Upper wall seam")
	wallMold("ArcadeDampCorner",V(-65,8.05,195.31),V(-65,8.05,150),21.33,16,"corner","Low wall corner")
	wallMold("DomesticCeilingSeam",V(-63,7.25,795.31),V(-63,7.25,740),13.5,13.5,"seam","Ceiling seam")
	root:SetAttribute("TallWallDrawingCount",0)
	root:SetAttribute("WallMoldCount",8)
	root:SetAttribute("WallMoldVariantCount",3)
	local cameras={
		{name="Atrium",position=V(-34,12,7),lookAt=V(52,18,49)},
		{name="LowEaves",position=V(9,6,80),lookAt=V(-44,8,132)},
		{name="LowEavesLoop",position=V(-49,5,146),lookAt=V(26,7,174)},
	}
	local waypoints={V(0,3,5),V(0,3,68),V(0,3,83),V(0,3,137),V(0,3,190)}
	local function append(t,src) for _,v in ipairs(src or {}) do t[#t+1]=v end end
	append(cameras,N.PreviewCameras);append(cameras,L.PreviewCameras)
	append(waypoints,N.Waypoints);append(waypoints,L.Waypoints)
	for _,camera in ipairs(cameras) do camera.position+=origin;camera.lookAt+=origin end
	for i,p in ipairs(waypoints) do waypoints[i]=origin+p end
	local actualParts,actualLights,windowCount=0,0,0
	for _,object in ipairs(root:GetDescendants()) do
		if object:IsA("BasePart") then actualParts+=1 end
		if object:IsA("Light") then actualLights+=1 end
		if object:GetAttribute("Level5TintedWindow")==true then windowCount+=1 end
	end
	root:SetAttribute("PartCount",actualParts);root:SetAttribute("LightCount",actualLights)
	root:SetAttribute("TintedWindowCount",windowCount)
	root:SetAttribute("BiomeCount",#zones);root:SetAttribute("GroundEnvelopeArea",totalFootprint)
	root:SetAttribute("PreviousGroundEnvelopeArea",65396)
	root:SetAttribute("GroundEnvelopeExpansionFactor",totalFootprint/65396)
	root:SetAttribute("WindowStandard","Glass RGB(87,102,102), transparency 0.2; no luminous panes")
	root:SetAttribute("Design","Unknown-origin Backrooms; visitors are researchers. No organisation created this place.")
	return {
		Model=root,SpawnCFrame=CFrame.lookAt(origin+V(0,3,5),origin+V(0,3,38)),
		PreviewCameras=cameras,Waypoints=waypoints,Zones=zones,
		FinalHouse=L.FinalHouse,ChuteStart=CFrame.new(origin+L.ChuteStart),ChuteEnd=CFrame.new(origin+L.ChuteEnd),
		Bounds={Min=origin+V(-181,-36,-5),Max=origin+V(181,110,1324)},
		GroundEnvelopeArea=totalFootprint,PreviousGroundEnvelopeArea=65396,
	}
end

return Architecture
