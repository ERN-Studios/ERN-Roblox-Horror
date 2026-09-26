-- Level 5: The Indoor Suburbs. Geometry only; deliberately independent of Level 4.
-- All authored coordinates are relative to origin. No Lighting, entity or quest mutation.
local Architecture = {}
local DEFAULT_TEXTURES={Plaster="rbxassetid://108985650994325",Wallpaper="rbxassetid://102299936573476",Siding="rbxassetid://115748401620318",Grass="rbxassetid://126776492995543",Wood="rbxassetid://118880038763227",Roof="rbxassetid://118077370167392",Carpet="rbxassetid://113909496202267"}
local DEFAULT_VARIANTS={Plaster="Level5AgedPlaster",Wallpaper="Level5FloralWallpaper",Siding="Level5PaintedSiding",Grass="Level5LawnGrass",Wood="Level5VeneerWood",Roof="Level5RoofShingles",Carpet="Level5LoopCarpet"}

function Architecture.Build(parent, origin, config)
	config = table.clone(config or {})
	config.ExitArrowTexture = config.ExitArrowTexture or "rbxassetid://136557095207787"
	config.ExitArrowLeftTexture = config.ExitArrowLeftTexture or "rbxassetid://119578216618152"
	config.FurnitureUpholsteryTexture = config.FurnitureUpholsteryTexture or "rbxassetid://132119936960491"
	config.FurnitureTVTexture = config.FurnitureTVTexture or "rbxassetid://129933596500815"
	config.TexturePalette = setmetatable(table.clone(config.TexturePalette or {}),{__index=DEFAULT_TEXTURES})
	config.MaterialVariants = setmetatable(table.clone(config.MaterialVariants or {}),{__index=DEFAULT_VARIANTS})
	local Furniture = require(script.Parent:WaitForChild("Level 5 Furniture"))
	local furnitureKit
	origin = origin or Vector3.zero
	local root = Instance.new("Model")
	root.Name = "Level5_IndoorSuburbs"
	root:SetAttribute("ArchitectureVersion", "2026-09-26.residential-atrium.1")
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
	local materials=game:GetService("MaterialService")
	local bases={Plaster=Enum.Material.Plaster,Wallpaper=Enum.Material.Plaster,Siding=Enum.Material.WoodPlanks,Grass=Enum.Material.Grass,Wood=Enum.Material.Wood,Roof=Enum.Material.Slate,Carpet=Enum.Material.Fabric}
	local function material(p,key,tint)
		local base=bases[key];if not base then return p end
		p.Material=base
		local variantName=config.MaterialVariants[key]
		local variant=variantName and materials:FindFirstChild(variantName)
		if variant and variant:IsA("MaterialVariant") then
			p.MaterialVariant=variantName;p.Color=tint or Color3.new(1,1,1)
		else p.MaterialVariant="";if tint then p.Color=tint end end
		p:SetAttribute("Level5SurfaceMaterial",key)
		return p
	end
	local function model(name, into)
		local m=Instance.new("Model"); m.Name=name; m.Parent=into or root; return m
	end
	local function part(into, name, size, cf, color, material, collide, className)
		local p=Instance.new(className or "Part")
		p.Name=name; p.Size=size; p.CFrame=offset*cf; p.Anchored=true
		p.Color=color or C.cream; p.Material=material or Enum.Material.SmoothPlastic
		p.CanCollide=collide~=false; p.CanQuery=collide~=false; p.CanTouch=false; p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
		p.CastShadow=collide~=false and math.min(size.X,size.Y,size.Z)>.4
		p.Parent=into; partCount+=1
		if material==Enum.Material.Plaster then p.MaterialVariant=config.MaterialVariants.Plaster or ""
		elseif material==Enum.Material.WoodPlanks then p.MaterialVariant=config.MaterialVariants.Siding or ""
		elseif material==Enum.Material.Slate and materials:FindFirstChild(config.MaterialVariants.Roof) then p.MaterialVariant=config.MaterialVariants.Roof;p.Color=Color3.new(1,1,1)
		elseif material==Enum.Material.Fabric and materials:FindFirstChild(config.MaterialVariants.Carpet) then
			p.MaterialVariant=config.MaterialVariants.Carpet;p.Color=color and Color3.new(1,1,1):Lerp(color,.3) or Color3.new(1,1,1)
		end
		return p
	end
	local function texture(p, asset, face, tile)
		if not asset or asset=="" then return end
		local t=Instance.new("Texture"); t.Name="MaterialDetail"; t.Texture=tostring(asset)
		t.Face=face or Enum.NormalId.Top; t.StudsPerTileU=tile or 8; t.StudsPerTileV=tile or 8
		t.Transparency=.12; t.Parent=p; return t
	end
	local function floor(into, name, x,y,z,w,d,color,frame)
		local lawn=color==C.green
		local p=part(into,name,V(w,1.2,d),(frame or CF())*CF(x,y-.6,z),color or C.carpet,lawn and Enum.Material.Grass or Enum.Material.Fabric)
		if lawn then
			material(p,"Grass");p:SetAttribute("LawnSurface",true)
		elseif materials:FindFirstChild(config.MaterialVariants.Carpet) then
			material(p,"Carpet",color and color~=C.carpet and Color3.new(1,1,1):Lerp(color,.32) or nil)
		else
			local surface=texture(p,config.CarpetTexture,Enum.NormalId.Top,8)
			if surface and color and color~=C.carpet then surface.Color3=color end
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
	local function window(into,frame,w,h,lit,simple)
		local glass=part(into,"WindowGlass",V(w,h,.14),frame,C.glass,Enum.Material.Glass)
		glass.Transparency=.2
		glass.Reflectance=0
		glass:SetAttribute("Level5TintedWindow",true)
		for _,s in ipairs({-1,1}) do
			part(into,"WindowJamb",V(.25,h+.45,.34),frame*CF(s*(w/2+.08),0,-.08),C.white)
			part(into,"WindowSill",V(w+.65,.25,.4),frame*CF(0,s*(h/2+.08),-.12),C.white)
		end
		part(into,"WindowMullion",V(.12,h,.23),frame*CF(0,0,-.09),C.white)
		for _,s in ipairs(simple and {0} or {-.22,.22}) do part(into,"WindowCrossbar",V(w,.12,.23),frame*CF(0,h*s,-.09),C.white) end
		return glass
	end
	local function doorframe(into,frame,width,height)
		for _,s in ipairs({-1,1}) do part(into,"DoorJamb",V(.4,height+.3,.55),frame*CF(s*(width/2+.2),height/2,-.13),C.white) end
		part(into,"DoorHeader",V(width+.8,.45,.55),frame*CF(0,height+.15,-.13),C.white)
	end
	local function facade(into,frame,w,h,color,openDoor,lit,simple)
		local dw,dh=5.4,10.3
		local sw=(w-dw)/2
		part(into,"FacadeLintel",V(w,h-dh,.65),frame*CF(0,dh+(h-dh)/2,0),color)
		for _,s in ipairs({-1,1}) do
			local x=s*(dw/2+sw/2)
			part(into,"WindowApron",V(sw,2.8,.65),frame*CF(x,1.4,0),color)
			for _,j in ipairs({-1,1}) do part(into,"FacadePier",V(1.15,dh,.65),frame*CF(x+j*(sw/2-.575),dh/2,0),color) end
			-- Broad houses retain domestic window proportions rather than one
			-- shopfront-length ribbon. Narrow curated Watcher homes stay exact.
			local clearWidth=sw-2.3
			local count=sw>16 and math.clamp(math.ceil(clearWidth/11),2,3) or 1
			local pier=.85
			local paneWidth=(clearWidth-(count-1)*pier)/count
			for i=1,count do
				local px=x-clearWidth/2+paneWidth/2+(i-1)*(paneWidth+pier)
				window(into,frame*CF(px,6.55,-.18),paneWidth,7.2,lit,simple)
				if i<count then part(into,"FacadePier",V(pier,dh,.65),frame*CF(px+paneWidth/2+pier/2,dh/2,0),color) end
			end
		end
		doorframe(into,frame,dw,dh)
		if not openDoor then
			part(into,"ClosedPanelDoor",V(dw,dh,.32),frame*CF(0,dh/2,.05),C.white,Enum.Material.Wood)
			if simple then
				part(into,"ScenicDoorInset",V(dw-.9,dh-1.3,.13),frame*CF(0,dh/2,-.18),C.pale,Enum.Material.Wood)
			else
				for _,y in ipairs({2.4,6.6,8.7}) do for _,x in ipairs({-1.25,1.25}) do part(into,"DoorRaisedPanel",V(1.85,y==6.6 and 2.8 or 1.25,.13),frame*CF(x,y,-.18),C.pale,Enum.Material.Wood) end end
				local knob=part(into,"BrassDoorKnob",V(.27,.27,.4),frame*CF(2,4.6,-.4),Color3.fromRGB(137,119,65),Enum.Material.Metal); knob.Shape=Enum.PartType.Ball
			end
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
		m:SetAttribute("Enterable",options.open~=false)
		m:SetAttribute("HouseFloorFrame",offset*frame)
		m:SetAttribute("HouseRoomSize",V(w,h,d))
		m:SetAttribute("HouseWindowFloorY",(offset*frame).Position.Y)
		-- Unreachable upper houses retain the full silhouette, glass, floor and
		-- enclosure; only tiny or invisible details use a cheaper static variant.
		local scenic=options.open==false and frame.Position.Y>=13
		m:SetAttribute("ScenicUpperDetail",scenic)
		if scenic then part(m,"InteriorCarpet",V(w,1.2,d),frame*CF(0,-.6,d/2),C.carpet,Enum.Material.Fabric)
		else floor(m,"InteriorCarpet",0,0,d/2,w,d,C.carpet,frame) end
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
		else facade(m,frame,w,h,color,options.open~=false,options.lit,scenic) end
		for _,s in ipairs({-1,1}) do
			part(m,"SideWall",V(.65,h,d),frame*CF(s*w/2,h/2,d/2),color)
			if not scenic then part(m,"InteriorBaseboard",V(.18,.5,d),frame*CF(s*(w/2-.4),.25,d/2),C.white) end
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
		-- Selected houses have a genuine central hall and two separate side rooms.
		-- The hall and rear clue wall stay clear; room furniture lives beside the
		-- exterior walls. All internal doorways are full human height.
		if options.completeHome and options.open~=false and w>=30 and d>=22 then
			m:SetAttribute("CompleteHome",true);m:SetAttribute("RoomCount",3)
			for _,side in ipairs({-1,1}) do
				material(part(m,"InteriorPlasterLining",V(.025,h-.2,d-.65),frame*CF(side*(w/2-.345),h/2,d/2),C.pale,Enum.Material.Plaster),"Plaster")
			end
			if not options.backOpening then material(part(m,"InteriorBackPlasterLining",V(w-.7,h-.2,.025),frame*CF(0,h/2,d-.345),C.pale,Enum.Material.Plaster),"Plaster") end
			local doorZ=d*.48;local opening=6.5;local front=3;local rear=d-.65
			for _,side in ipairs({-1,1}) do
				for _,span in ipairs({{front,doorZ-opening/2},{doorZ+opening/2,rear}}) do
					if span[2]>span[1] then
						local p=part(m,"WallpaperRoomPartition",V(.4,h,span[2]-span[1]),frame*CF(side*5.5,h/2,(span[1]+span[2])/2),C.pale,Enum.Material.Plaster)
						material(p,"Wallpaper")
					end
				end
				material(part(m,"RoomDoorLintel",V(.4,h-10,opening),frame*CF(side*5.5,10+(h-10)/2,doorZ),C.pale,Enum.Material.Plaster),"Wallpaper")
				doorframe(m,frame*CF(side*5.5,0,doorZ)*CFrame.Angles(0,math.pi/2,0),opening,10)
			end
		end
		if options.open~=false and math.abs(frame.Position.Y)<.1 and not options.backOpening then
			m:SetAttribute("HousePuzzleCandidate",true)
			local hint=part(m,"PuzzleHintSurface",V(6,5,.03),frame*CF(0,6,d-.38),C.white,nil,false)
			hint.Transparency=1;hint.CastShadow=false;hint:SetAttribute("ReservedBlankClueArea",true)
		end
		local colorful=color==C.rose or color==C.pink or color==C.blue or color==C.lavender or color==C.yellow
		local pastel=Color3.new(1,1,1):Lerp(color or C.cream,colorful and .55 or .3)
		for _,surface in ipairs(m:GetChildren()) do
			if surface:IsA("BasePart") then
				local n=surface.Name
				if n=="SideWall" or n=="BackWall" or n=="BackWallWing" or n=="BackWallHeader" or n=="FacadeLintel" or n=="WindowApron" or n=="FacadePier" or n=="GableBaseBand" or n=="ClosedGableTriangle" then material(surface,"Siding",pastel)
				elseif n=="InteriorCeiling" then material(surface,"Plaster") end
			end
		end
		local variant=options.furniture
		if furnitureKit and variant and options.open~=false then
			Furniture.FurnishHome(furnitureKit,m,frame,w,d,h,{variant=variant,open=true,backOpening=options.backOpening,glitchedTable=options.glitchedTable==true})
			m:SetAttribute("FurnitureRoomFrame",offset*frame)
			m:SetAttribute("FurnitureRoomSize",V(w,h,d))
		end
		return m
	end
	local function ceiling(into,name,x,z,w,d,y,style)
		local m=model(name,into)
		local tint=style=="domestic" and C.pale or (style=="low" and Color3.fromRGB(177,172,145) or C.ceiling)
		material(part(m,"CeilingPlane",V(w+12,8,d+12),CF(x,y+3.7,z),tint,Enum.Material.Plaster),"Plaster")
		local tile=y>70 and 24 or style=="domestic" and 12 or 18
		for xx=-w/2,w/2,tile do part(m,"CeilingGrid",V(.08,.08,d),CF(x+xx,y-.34,z),C.grid,nil,false) end
		for zz=-d/2,d/2,tile do part(m,"CeilingGrid",V(w,.08,.08),CF(x,y-.34,z+zz),C.grid,nil,false) end
		local sx,sz=y>70 and 56 or 40,y>70 and 56 or 40
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
			if y<=60 and ix%4==1 and not failed then
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
		house=house,texture=texture,wallLamp=wallLamp,bay=bay,ceiling=ceiling,material=material}
	furnitureKit=K

	-- Curated panes use real supporting rooms. The origin remains private to this
	-- module; exposed floor frames are world-space for puzzle/Watcher consumers.
	local anchors=Instance.new("Folder");anchors.Name="WindowWatcherAnchors";anchors.Parent=parent
	local function registerWatcher(home,name,district,index)
		local panes={}
		for _,v in ipairs(home:GetDescendants()) do
			-- Vector3 dimensions round through float32: authored 7.2 becomes 7.1999998.
			if v:IsA("BasePart") and v:GetAttribute("Level5TintedWindow")==true and v.Size.X>=6.79 and v.Size.Y>=7.19 then table.insert(panes,v) end
		end
		local pane=panes[index or 1]
		assert(pane,"Watcher home requires a full-height standard pane: "..home.Name)
		local a=Instance.new("Part");a.Name=name;a.Size=V(.2,.2,.2);a.CFrame=pane.CFrame
		a.Anchored=true;a.Transparency=1;a.CanCollide=false;a.CanQuery=false;a.CanTouch=false;a.CastShadow=false
		a:SetAttribute("District",district);a:SetAttribute("FloorCFrame",pane.CFrame*CF(0,-6.55,0))
		a:SetAttribute("PawnDepth",1.90);a:SetAttribute("InteriorClearanceDepth",home:GetAttribute("HouseRoomSize").Z)
		a:SetAttribute("Level5WindowWatcherAnchor",true);a.Parent=anchors
		local v=Instance.new("ObjectValue");v.Name="WindowGlass";v.Value=pane;v.Parent=a
		local h=Instance.new("ObjectValue");h.Name="SupportingHouse";h.Value=home;h.Parent=a
		return a
	end
	local function edgeRail(into,x,y,z0,z1,gaps)
		local cursor=z0
		for _,gap in ipairs(gaps or {}) do
			if gap[1]>cursor then rail(into,CF(x,y,(cursor+gap[1])/2)*CFrame.Angles(0,math.pi/2,0),gap[1]-cursor) end
			cursor=math.max(cursor,gap[2])
		end
		if cursor<z1 then rail(into,CF(x,y,(cursor+z1)/2)*CFrame.Angles(0,math.pi/2,0),z1-cursor) end
	end
	K.registerWatcher=registerWatcher;K.edgeRail=edgeRail
	local yaw=function(a) return CFrame.Angles(0,math.rad(a),0) end
	local A=model("A_BalconyAtrium")
	floor(A,"AtriumCarpet",0,0,96,320,200)
	local clueIndex=0
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({42,99,156}) do
			local stack=model("ResidentialAtriumStack_"..side.."_"..i,A)
			local storeys=(side<0 and {5,7,4} or {6,4,7})[i]
			stack:SetAttribute("StoreyCount",storeys)
			for level=0,storeys-1 do
				local x=side*(110+(level>=3 and (i%2)*3 or 0))
				local f=CF(x,level*14,z)*yaw(side*90)
				local home=house(stack,"AtriumHome_"..level,f,30,24,13.8,(level+i)%3==0 and C.pale or C.cream,level==storeys-1 and C.blue or nil,{open=level<=2,furniture=level==0 and i==2 and (side<0 and 2 or 4) or nil})
				if level==0 and i~=2 then
					clueIndex+=1;home.Name="ClueHouse_"..clueIndex;home:SetAttribute("PuzzleClueIndex",clueIndex)
					local clue=part(home,"PuzzleClueSurface",V(4,5,.03),f*CF(0,6,23.62),C.white,nil,false)
					clue.Transparency=1;clue:SetAttribute("ClueIndex",clueIndex)
				end
				if level==0 and i==1 then registerWatcher(home,"AtriumWindow_"..side,A.Name) end
			end
		end
		for _,y in ipairs({14,28}) do
			floor(A,"ContinuousBalcony",side*96,y,99,28,168)
			local gaps=y==14 and (side<0 and {{48,59},{92,106}} or {{92,108}}) or {{136,150},{155,169}}
			edgeRail(A,side*82,y,15,183,gaps)
			rail(A,CF(side*96,y,15),28);rail(A,CF(side*96,y,183),28)
		end
		for _,z in ipairs({20,178}) do part(A,"StackSupportColumn",V(2.5,42,2.5),CF(side*82,21,z),C.pale) end
	end
	floor(A,"FirstCrossBridge",0,14,99,194,14)
	rail(A,CF(0,14,92),164)
	-- The upper-flight entrance crosses the rear edge at X65. Retain the
	-- protective rail except for its sixteen-stud stair approach opening.
	rail(A,CF(-12.5,14,106),139) -- -82..57
	rail(A,CF(77.5,14,106),9) -- 73..82
	floor(A,"UpperCrossBridge",0,28,162,194,14)
	for _,z in ipairs({155,169}) do rail(A,CF(0,28,z),164) end
	stairs(A,"GroundToFirstBalcony",CF(-65,0,18),12,14,30,28,C.carpet,true)
	floor(A,"FirstBalconyLanding",-80.5,14,53,43,10)
	stairs(A,"FirstToUpperBalcony",CF(65,14,108),12,14,30,28,C.carpet,true)
	floor(A,"UpperFlightBase",80.5,14,103,43,10)
	floor(A,"UpperFlightLanding",80.5,28,143,43,10)
	for _,s in ipairs({-1,1}) do
		house(A,"GroundWaitingCottage_"..s,CF(s*42,0,128),26,24,13.8,s<0 and C.rose or C.cream,C.lavender,{open=true})
	end

	-- Infill forms real short streets around the existing atrium stairs, rather
	-- than stretching a central aisle between distant scenic facades.
	for level=0,2 do
		house(A,"CentralHallResidence_"..level,CF(0,level*14,60),52,32,13.8,C.pale,level==2 and C.blue or nil,{open=level==0,completeHome=level==0,furniture=level==0 and 6 or nil})
	end
	for _,side in ipairs({-1,1}) do
		for level=0,2 do house(A,"AtriumInnerStack_"..side.."_"..level,CF(side*44,level*14,76)*yaw(side*90),28,24,13.8,C.cream,level==2 and C.lavender or nil,{open=level==0}) end
		house(A,"AtriumRearCottage_"..side,CF(side*26,0,163),26,22,13.8,side<0 and C.rose or C.pale,C.blue,{open=true})
	end

	-- B trades the tall atrium for deep covered porches and low passage rooms.
	local B=model("B_LowEavesArcade")
	floor(B,"OchreArcadeCarpet",0,0,326,280,260,Color3.fromRGB(147,137,101))
	floor(B,"LongWornRunner",0,.025,326,18,258,Color3.fromRGB(107,99,77))
	for _,s in ipairs({-1,1}) do
		for i,z in ipairs({232,286,348,418}) do
			local frame=CF(s*96,0,z)*yaw(s*90)
			for level=0,2 do
				local home=house(B,"ArcadeResidence_"..s.."_"..i.."_"..level,frame*CF(0,level*14,0),28,28,13.8,(i+level)%2==0 and C.pale or C.yellow,nil,{open=level==0,backOpening=level==0 and i%2==0,furniture=level==0 and i==2 and (s<0 and 1 or 3) or nil})
				if level==0 and i==1 then registerWatcher(home,"ArcadeWindow_"..s,B.Name) end
			end
			floor(B,"CoveredPorch",s*86,0,z,20,31,C.pink)
			part(B,"LowPorchCanopy",V(24,.55,34),CF(s*86,12.6,z),C.pale)
			for _,dz in ipairs({-15,15}) do part(B,"PorchPost",V(.6,12.3,.6),CF(s*76,6.15,z+dz),C.white) end
		end
	end
	for i,info in ipairs({{-31,239},{32,302},{-31,365},{32,420}}) do
		house(B,"DetachedThroughRoom_"..i,CF(info[1],0,info[2]),30,21,12.8,i%2==0 and C.cream or C.pale,nil,{open=true,backOpening=true})
	end
	for _,z in ipairs({267,332,397}) do
		part(B,"SharedDroppedCeiling",V(130,.55,20),CF(0,17,z),C.ceiling)
		for _,x in ipairs({-60,60}) do part(B,"ArcadeDomesticColumn",V(.8,17,.8),CF(x,8.5,z),C.white) end
	end

	for i,z in ipairs({272,338}) do
		for level=0,1 do house(B,"ArcadeCrossLaneHome_"..i.."_"..level,CF(0,level*14,z),50,22,13.8,i==1 and C.pale or C.yellow,nil,{open=level==0,completeHome=level==0,furniture=level==0 and (i==1 and 7 or 8) or nil}) end
	end

	local N=require(script.Parent:WaitForChild("Level 5 Neighbourhood Districts")).Build(K)
	local L=require(script.Parent:WaitForChild("Level 5 Landmark Districts")).Build(K)
	local zones={
		{Name="A_BalconyAtrium",Title="Stacked Balcony Atrium",Width=320,Z0=-4,Z1=196,CeilingHeight=120,Style="office"},
		{Name="B_LowEavesArcade",Title="Low Eaves Arcade",Width=280,Z0=196,Z1=456,CeilingHeight=50,Style="low"},
		{Name="C_PastelVillage",Title="Pastel Carpet Villages",Width=560,Z0=456,Z1=936,CeilingHeight=100,Style="office"},
		{Name="D_FloralTerraces",Title="Sunken Floral Terraces",Width=320,Z0=936,Z1=1296,CeilingHeight=88,Style="office",Bottom=-14},
		{Name="E_DomesticLabyrinth",Title="Domestic Room Labyrinth",Width=320,Z0=1296,Z1=1596,CeilingHeight=44,Style="domestic"},
		{Name="F_BayWindowCanyon",Title="Deep Residential Atrium",Width=500,Z0=1596,Z1=2076,CeilingHeight=84,Style="office",Bottom=-42},
		{Name="G_TiltedSubdivision",Title="Impossible Tilted Subdivision",Width=480,Z0=2076,Z1=2456,CeilingHeight=180,Style="warehouse"},
		{Name="H_LastHouse",Title="Last House",Width=220,Z0=2456,Z1=2636,CeilingHeight=70,Style="domestic"},
	}
	local gateLocal={V(0,0,196),V(88,0,456),V(-120,0,936),V(120,0,1296),V(-120,0,1596),V(178,0,2076),V(-65,0,2456)}
	local sectionGates={}
	for i,p in ipairs(gateLocal) do sectionGates[i]={Frame=offset*CF(p),Approach=origin+p+V(0,3,-12),Departure=origin+p+V(0,3,12),WallThickness=8} end
	local totalFootprint=0
	for index,z in ipairs(zones) do
		local m=root:FindFirstChild(z.Name);assert(m,"Missing district "..z.Name)
		z.Model=m;z.Min=V(-z.Width/2,z.Bottom or 0,z.Z0);z.Max=V(z.Width/2,z.CeilingHeight,z.Z1)
		-- Retain lower-case metadata for older diagnostics; runtime contracts use
		-- Name/Model/Min/Max/CeilingHeight and never derive geometry by scaling.
		z.model=z.Name;z.name=z.Title;z.width=z.Width;z.z0=z.Z0;z.z1=z.Z1;z.height=z.CeilingHeight
		m:SetAttribute("BiomeName",z.Title);m:SetAttribute("CeilingY",z.CeilingHeight)
		m:SetAttribute("DistrictMin",z.Min);m:SetAttribute("DistrictMax",z.Max)
		m:SetAttribute("ZoneMin",z.Min);m:SetAttribute("ZoneMax",z.Max);m:SetAttribute("CeilingHeight",z.CeilingHeight)
		local enclosure=model("Enclosure",m)
		local bottom=z.Bottom or 0
		-- A physically opaque shell: the interior faces stay on the existing
		-- envelope, while thick outward walls overlap the roof and corner caps.
		local top=z.CeilingHeight+6;local deep=bottom-6
		for _,side in ipairs({-1,1}) do
			material(part(enclosure,"DistrictSideWall",V(6,top-deep,z.Z1-z.Z0+12),CF(side*(z.Width/2+2.4),(top+deep)/2,(z.Z0+z.Z1)/2),C.cream,Enum.Material.Plaster),"Plaster")
			part(enclosure,"ContinuousBaseboard",V(.45,.8,z.Z1-z.Z0),CF(side*(z.Width/2-.65),.4,(z.Z0+z.Z1)/2),C.white,nil,false)
			for _,edge in ipairs({z.Z0,z.Z1}) do material(part(enclosure,"OverlappingCornerColumn",V(4,top-deep,4),CF(side*(z.Width/2+1), (top+deep)/2,edge),C.cream,Enum.Material.Plaster),"Plaster") end
		end
		for _,isBack in ipairs({false,true}) do
			local edge=isBack and z.Z1 or z.Z0
			local entrance=index==1 and not isBack
			local chute=index==8 and isBack
			local opening=chute and 9.3 or 22;local openingHeight=chute and 11 or 14
			local wallBottom=chute and -35 or deep
			local gate=not entrance and not chute and gateLocal[isBack and index or index-1] or nil
			local gx=gate and gate.X or 0
			if entrance then
				material(part(enclosure,"ArrivalBackWall",V(z.Width+12,top-deep,8),CF(0,(top+deep)/2,edge-3.3),C.cream,Enum.Material.Plaster),"Plaster")
			else
				for _,span in ipairs({{-z.Width/2-6,gx-opening/2},{gx+opening/2,z.Width/2+6}}) do
					material(part(enclosure,"ThresholdSideWall",V(span[2]-span[1],top-wallBottom,8),CF((span[1]+span[2])/2,(top+wallBottom)/2,edge),C.cream,Enum.Material.Plaster),"Plaster")
				end
				material(part(enclosure,"ThresholdHighClosure",V(opening,top-openingHeight,8),CF(gx,(top+openingHeight)/2,edge),C.cream,Enum.Material.Plaster),"Plaster")
				if bottom<0 and not chute then material(part(enclosure,"ThresholdFoundation",V(opening,-deep,8),CF(gx,deep/2,edge),C.cream,Enum.Material.Plaster),"Plaster") end
			end
		end
		ceiling(enclosure,z.Title.."Ceiling",0,(z.Z0+z.Z1)/2,z.Width,z.Z1-z.Z0,z.CeilingHeight,z.Style)
		-- A limited shared suspended-light grid keeps human-height paths legible
		-- beneath tall rooms. These are room fixtures, never house-mounted lights.
		if z.CeilingHeight>60 then
			for i,zz in ipairs({z.Z0+35,(z.Z0+z.Z1)/2,z.Z1-35}) do
				for _,xx in ipairs({-34,34}) do
						local y=index==6 and 82 or (index==8 and 24 or 37)
					local p=part(enclosure,"SuspendedSharedFluorescent",V(7,.18,3),CF(xx,y,zz),i==2 and C.ceiling or Color3.fromRGB(221,218,187),i==2 and Enum.Material.SmoothPlastic or Enum.Material.Neon,false)
					p:SetAttribute("TubeState",i==2 and "Off" or "On")
					for _,dx in ipairs({-2.6,2.6}) do part(enclosure,"CeilingSuspension",V(.055,z.CeilingHeight-y,.055),CF(xx+dx,(z.CeilingHeight+y)/2,zz),C.grid,nil,false) end
						if i~=2 then local l=Instance.new("SurfaceLight");l.Face=Enum.NormalId.Bottom;l.Range=index==6 and 60 or 52;l.Angle=160;l.Brightness=.85;l.Shadows=false;l.Color=Color3.fromRGB(244,233,204);l.Parent=p end
				end
			end
		end
		totalFootprint+=z.Width*(z.Z1-z.Z0)
	end

	local growth=model("MyceliumWallGrowth")
	local moldAssets={"rbxassetid://111130507669211","rbxassetid://84997095468417","rbxassetid://119550867817499"}
	for i,z in ipairs(zones) do
		local side=i%2==0 and 1 or -1
		local pos=V(side*(z.Width/2-.68),i==4 and 16 or 20,(z.Z0+z.Z1)/2)
		local surface=part(growth,"WallColony_"..i,V(38,32,.015),CFrame.lookAt(pos,pos+V(-side,0,0)),C.white,nil,false)
		surface.Transparency=1;surface.CastShadow=false;surface:SetAttribute("Level5WallMold",true);surface:SetAttribute("AlphaBackground",true)
		surface:SetAttribute("MoldVariant",({"rising","corner","seam"})[(i-1)%3+1]);surface:SetAttribute("GrowthOrigin","Outer structural wall")
		local decal=Instance.new("Decal");decal.Name="DarkMyceliumOnPlaster";decal.Texture=moldAssets[(i-1)%3+1];decal.Face=Enum.NormalId.Front;decal.Color3=Color3.fromRGB(168,164,150);decal.Transparency=.04;decal.Parent=surface
	end
	root:SetAttribute("TallWallDrawingCount",0);root:SetAttribute("WallMoldCount",8);root:SetAttribute("WallMoldVariantCount",3)
	local cameras={
		{name="ExpandedAtriumArrival",position=V(-25,7,7),lookAt=V(110,39,99)},
		{name="ExpandedAtriumBalconies",position=V(-91,33,165),lookAt=V(95,45,55)},
		{name="ExpandedArcade",position=V(9,6,204),lookAt=V(-78,10,284)},
		{name="ExpandedArcadeSideLoop",position=V(127,6,309),lookAt=V(90,9,390)},
	}
	local waypoints={V(0,3,5),V(0,3,45),V(35,3,50),V(35,3,104),V(0,3,108),V(0,3,184),V(0,3,208),V(0,3,263),V(58,3,264),V(58,3,329),V(-55,3,329),V(-55,3,397),V(60,3,400),V(60,3,444),V(88,3,444),V(88,3,468),V(110,3,468),V(110,3,513),V(145,3,513),V(145,3,565),V(90,3,592),V(25,3,592),V(25,3,650),V(-25,3,700),V(-25,3,740),V(-25,3,778),V(-90,3,778),V(-145,3,800),V(-145,3,865),V(-100,3,875),V(-100,3,924),V(-120,3,924),V(-120,3,948),V(-120,3,965),V(-101,3,965),V(-101,3,1087),V(-101,3,1109),V(-86,3,1109),V(-86,3,1094),V(-86,3,1089),V(-86,-3,1073),V(-86,-9,1057),V(-86,-9,1024),V(15,-9,1024),V(15,-9,1106),V(30,-9,1122),V(30,-9,1195),V(0,-9,1228),V(0,-3,1246),V(0,3,1265),V(120,3,1278),V(120,3,1284),V(120,3,1308),V(90,3,1310),V(90,3,1373),V(60,3,1373),V(60,3,1406),V(-90,3,1406),V(-90,3,1458),V(-60,3,1458),V(-60,3,1495),V(-90,3,1495),V(-90,3,1550),V(-120,3,1584),V(-120,3,1608),V(-125,3,1689),V(-80,3,1690),V(-80,3,1755),V(15,3,1755),V(75,3,1790),V(75,3,1840),V(75,3,1910),V(40,3,1955),V(0,3,1955),V(0,3,2028),V(80,3,2028),V(178,3,2048),V(178,3,2064),V(178,3,2088),V(135,3,2100),V(95,3,2140),V(0,3,2140),V(-54,3,2173),V(-54,7,2188),V(-54,11,2204),V(-90,11,2208),V(-90,11,2270),V(-60,11,2270),V(-10,11,2270),V(6,11,2270),V(18,15,2270),V(30,19,2270),V(36,19,2270),V(92,19,2270),V(92,19,2332),V(54,19,2332),V(54,19,2340),V(54,11,2360),V(54,3,2380),V(54,3,2383),V(0,3,2400),V(0,3,2444),V(-65,3,2444),V(-65,3,2468),V(-65,3,2538),V(-30,3,2548),V(0,3,2555),V(0,3,2578),V(0,3,2588),V(0,3,2597.5),V(9,3,2597.5),V(9,3,2610.9),V(0,3,2610.9),V(0,3,2613),V(0,3,2615),V(0,-2.5,2631),V(0,-8,2647),V(0,-17,2658.5),V(0,-26,2670),V(0,-26,2676)}
	-- Replace only the F traversal: the domestic atrium now crosses a deep
	-- void at several heights while retaining both authored gate thresholds.
	local atriumRoute=assert(L.FRouteWaypoints,"Missing residential atrium route")
	local revisedRoute={};local inserted=false
	for _,point in ipairs(waypoints) do
		if point.Z>1596 and point.Z<2076 then
			if not inserted then
				for _,p in ipairs(atriumRoute) do table.insert(revisedRoute,p) end
				inserted=true
			end
		else table.insert(revisedRoute,point) end
	end
	assert(inserted,"Missing F route replacement span");waypoints=revisedRoute
	local function worldRoute(localPoints)
		local points={};for _,p in ipairs(localPoints or {}) do table.insert(points,origin+p) end;return points
	end
	for _,r in ipairs({N,L}) do for _,v in ipairs(r.PreviewCameras or {}) do table.insert(cameras,v) end end
	for _,v in ipairs(cameras) do v.position+=origin;v.lookAt+=origin end
	for i,v in ipairs(waypoints) do waypoints[i]=origin+v end
	local actualParts,actualLights,windows=0,0,0
	for _,v in ipairs(root:GetDescendants()) do if v:IsA("BasePart") then actualParts+=1 end;if v:IsA("Light") then actualLights+=1 end;if v:GetAttribute("Level5TintedWindow")==true then windows+=1 end end
	root:SetAttribute("PartCount",actualParts);root:SetAttribute("LightCount",actualLights);root:SetAttribute("TintedWindowCount",windows)
	root:SetAttribute("BiomeCount",8);root:SetAttribute("GroundEnvelopeArea",totalFootprint);root:SetAttribute("PreviousGroundEnvelopeArea",331600)
	root:SetAttribute("GroundEnvelopeExpansionFactor",totalFootprint/331600)
	root:SetAttribute("WindowStandard","Glass RGB(87,102,102), transparency 0.2; no luminous panes")
	root:SetAttribute("Design","Unknown-origin Backrooms. The researchers did not create this place.")
	root:SetAttribute("SpawnCFrame",CFrame.lookAt(origin+V(0,3,5),origin+V(0,3,70)))
	return {Model=root,SpawnCFrame=CFrame.lookAt(origin+V(0,3,5),origin+V(0,3,70)),PreviewCameras=cameras,Waypoints=waypoints,RouteWaypoints=waypoints,SectionGates=sectionGates,Zones=zones,
		FinalHouse=L.FinalHouse,ChuteStart=CF(origin+L.ChuteStart),ChuteEnd=CF(origin+L.ChuteEnd),
		FRouteWaypoints=worldRoute(L.FRouteWaypoints),FRescueRouteWaypoints=worldRoute(L.FRescueRouteWaypoints),FClueRouteWaypoints=worldRoute(L.FClueRouteWaypoints),FAtriumPitBounds=L.FAtriumPitBounds,
		Bounds={Min=origin+V(-287,-50,-12),Max=origin+V(287,188,2680)},GroundEnvelopeArea=totalFootprint,PreviousGroundEnvelopeArea=331600}
end
return Architecture
