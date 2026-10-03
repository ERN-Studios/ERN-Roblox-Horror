-- Sparse, deterministic domestic furniture for the Indoor Suburbs.
-- Usage: Furniture.FurnishHome(K, homeModel, houseFrame, width, depth, height,
--     {variant=1, backOpening=true, glitchedTable=false})
-- K.part already applies the world origin. All furniture coordinates here are
-- relative to the house floor. Parent architecture chooses which homes call it.
-- No services, Lights, Neon, scripts, Seats, animations or moving assemblies.
local Furniture = {}

Furniture.Version = "2026-09-24.2"
Furniture.MaxHomes = 20
Furniture.MaxPartsPerHome = 100
Furniture.ClearLaneWidth = 7
Furniture.VariantNames = {"SofaTVLounge","ReadingCorner","DiningRoom","JoinedChairs","SparseSittingRoom"}

function Furniture.FurnishHome(K, home, frame, width, depth, height, options)
	options = options or {}
	local config = K.config or {}
	if options.open == false or options.Furnish == false then
		return {Placed=false,Reason="Unselected or closed home",PartCount=0}
	end
	if home:GetAttribute("Level5FurnitureVersion") or home:FindFirstChild("DomesticFurniture") then
		return {Placed=false,Reason="Already furnished",PartCount=0}
	end
	local limit=math.clamp(math.floor(tonumber(config.FurnitureMaxHomes) or Furniture.MaxHomes),0,Furniture.MaxHomes)
	local furnished=tonumber(K.root:GetAttribute("Level5FurnishedHomeCount")) or 0
	if furnished>=limit then return {Placed=false,Reason="Furnished-home cap reached",PartCount=0} end
	if type(width)~="number" or type(depth)~="number" or type(height)~="number"
		or width<18 or depth<10.5 or height<9 then
		return {Placed=false,Reason="Room too small for clear domestic furniture",PartCount=0}
	end
	local variant=1+(math.floor(tonumber(options.variant or options.Variant) or 1)-1)%5
	local compact=depth<16
	if compact then variant=1 end
	local V,CF=K.V,K.CF
	local wood=Color3.fromRGB(111,78,48)
	local edge=Color3.fromRGB(143,107,67)
	local darkWood=Color3.fromRGB(66,47,34)
	local oatmeal=Color3.fromRGB(167,153,123)
	local sage=Color3.fromRGB(108,119,100)
	local brown=Color3.fromRGB(126,105,85)
	local cloth=({oatmeal,sage,brown,oatmeal,sage})[variant]
	local piping=Color3.fromRGB(139,126,105)
	local black=Color3.fromRGB(24,27,25)
	local group=K.model("DomesticFurniture",home)
	group:SetAttribute("FurnitureVersion",Furniture.Version)
	group:SetAttribute("Variant",variant)
	group:SetAttribute("VariantName",Furniture.VariantNames[variant])
	group:SetAttribute("ReservedCenterRouteWidth",Furniture.ClearLaneWidth)
	local partCount,pieceCount=0,0
	local extents={Min=V(math.huge,math.huge,math.huge),Max=V(-math.huge,-math.huge,-math.huge)}
	local yaw=function(a) return CFrame.Angles(0,math.rad(a),0) end
	local function add(into,name,size,localFrame,color,material,collide,className)
		assert(size.X>0 and size.Y>0 and size.Z>0,"Furniture size must be positive")
		assert(partCount<Furniture.MaxPartsPerHome,"Furniture room part budget exceeded")
		local minimum=V(math.huge,math.huge,math.huge)
		local maximum=V(-math.huge,-math.huge,-math.huge)
		for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
			local p=localFrame:PointToWorldSpace(V(sx*size.X/2,sy*size.Y/2,sz*size.Z/2))
			minimum=V(math.min(minimum.X,p.X),math.min(minimum.Y,p.Y),math.min(minimum.Z,p.Z))
			maximum=V(math.max(maximum.X,p.X),math.max(maximum.Y,p.Y),math.max(maximum.Z,p.Z))
		end end end
		assert(minimum.X>=-width/2+.3 and maximum.X<=width/2-.3,"Furniture intersects a house side wall: "..name)
		assert(minimum.Z>=.6 and maximum.Z<=depth-.6,"Furniture intersects a front/back doorway plane: "..name)
		assert(minimum.Y>=-.025 and maximum.Y<=height-.5,"Furniture leaves the room vertically: "..name)
		assert(maximum.X<=-Furniture.ClearLaneWidth/2 or minimum.X>=Furniture.ClearLaneWidth/2,
			"Furniture obstructs the reserved central route: "..name)
		extents.Min=V(math.min(extents.Min.X,minimum.X),math.min(extents.Min.Y,minimum.Y),math.min(extents.Min.Z,minimum.Z))
		extents.Max=V(math.max(extents.Max.X,maximum.X),math.max(extents.Max.Y,maximum.Y),math.max(extents.Max.Z,maximum.Z))
		partCount+=1
		local p=K.part(into,name,size,frame*localFrame,color,material,collide,className)
		if collide==false then p.CanQuery=false;p.CanTouch=false end
		return p
	end
	local function item(name,role)
		pieceCount+=1
		local m=K.model(name,group);m:SetAttribute("FurnitureRole",role or name);return m
	end
	local function fabric(p,face)
		local t=K.texture(p,config.FurnitureUpholsteryTexture,face or Enum.NormalId.Top,2.5)
		if t then t.Color3=cloth;t.Transparency=.35 end
	end
	local function legs(m,f,x,z,legHeight,thickness)
		for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
			add(m,"TaperStyleWoodLeg",V(thickness,legHeight,thickness),f*CF(sx*x,legHeight/2,sz*z),darkWood,Enum.Material.Wood)
		end end
	end
	local function seatCushion(m,f,w,d)
		local base=add(m,"SoftCushionBase",V(w,.28,d),f*CF(0,1.64,0),cloth,Enum.Material.Fabric)
		local top=add(m,"RaisedCushionTop",V(w-.08,.32,d-.26),f*CF(0,1.86,.13),cloth,Enum.Material.Fabric)
		local bevel=add(m,"CushionFrontBevel",V(w-.08,.32,.26),f*CF(0,1.86,-d/2+.13),cloth,Enum.Material.Fabric,true,"WedgePart")
		fabric(base,Enum.NormalId.Front);fabric(top);fabric(bevel,Enum.NormalId.Top)
	end
	local function backCushion(m,f,w,h)
		local p=add(m,"UpholsteredBackCushion",V(w,h,.55),f,cloth,Enum.Material.Fabric)
		local q=add(m,"InsetBackCushionFace",V(w-.13,h-.16,.1),f*CF(0,0,-.31),cloth,Enum.Material.Fabric,false)
		fabric(p,Enum.NormalId.Front);fabric(q,Enum.NormalId.Front)
	end
	local function sofa(f,w)
		local m=item("LowUpholsteredSofa","Sofa")
		legs(m,f,w/2-.55,1.13,.56,.22)
		add(m,"WalnutSofaPlinth",V(w-.3,.22,2.85),f*CF(0,.61,0),darkWood,Enum.Material.Wood)
		add(m,"UpholsteredSofaBase",V(w,.9,3.05),f*CF(0,1.13,0),cloth,Enum.Material.Fabric)
		add(m,"UpholsteredSofaBack",V(w,2.3,.4),f*CF(0,2.4,1.44),cloth,Enum.Material.Fabric)
		for _,s in ipairs({-1,1}) do
			add(m,"BroadSoftSofaArm",V(.58,1.55,3.05),f*CF(s*(w/2-.29),1.82,0),cloth,Enum.Material.Fabric)
			local p=add(m,"InsetSofaArmTop",V(.43,.14,2.9),f*CF(s*(w/2-.29),2.63,0),cloth,Enum.Material.Fabric,false);fabric(p)
		end
		local seats=w<6 and 2 or 3
		local cushionWidth=(w-1.3)/seats
		for i=1,seats do
			local x=-((seats-1)*cushionWidth)/2+(i-1)*cushionWidth
			seatCushion(m,f*CF(x,0,-.16),cushionWidth-.09,2.4)
			backCushion(m,f*CF(x,2.81,1.02)*CFrame.Angles(math.rad(7),0,0),cushionWidth-.09,1.43)
		end
		add(m,"FrontStitchedPiping",V(w-1.1,.055,.06),f*CF(0,1.57,-1.55),piping,Enum.Material.Fabric,false)
	end
	local function armchair(f,tall)
		local m=item(tall and "SlightlyTooTallArmchair" or "UpholsteredArmchair","Armchair")
		legs(m,f,1.05,1.1,.56,.23)
		add(m,"ArmchairBase",V(3,.94,3.0),f*CF(0,1.05,0),cloth,Enum.Material.Fabric)
		local backHeight=tall and 3.55 or 2.0
		add(m,"ArmchairBackFrame",V(3,backHeight,.4),f*CF(0,1.4+backHeight/2,1.42),cloth,Enum.Material.Fabric)
		for _,s in ipairs({-1,1}) do
			add(m,"ArmchairArm",V(.52,1.4,3),f*CF(s*1.24,1.78,0),cloth,Enum.Material.Fabric)
			add(m,"ArmchairArmPiping",V(.42,.07,2.8),f*CF(s*1.24,2.51,0),piping,Enum.Material.Fabric,false)
		end
		seatCushion(m,f*CF(0,0,-.12),1.82,2.38)
		backCushion(m,f*CF(0,1.7+backHeight/2,1.03),1.86,backHeight-.38)
		if tall then m:SetAttribute("BackroomsDistortion","Backrest stretched; feet remain on the floor") end
	end
	local function sideTable(f)
		local m=item("SmallVeneerSideTable","SideTable")
		legs(m,f,.62,.62,1.6,.18)
		add(m,"VeneerSideTableTop",V(1.75,.2,1.75),f*CF(0,1.7,0),edge,Enum.Material.Wood)
		add(m,"DarkRecessedTableEdge",V(1.62,.15,1.62),f*CF(0,1.53,0),darkWood,Enum.Material.Wood)
	end
	local function tvCabinet(f)
		local m=item("VeneerCabinetAndOffCRT","OffTelevision")
		legs(m,f,2.17,.83,.3,.19)
		add(m,"LowVeneerCabinet",V(5.1,1.4,2.35),f*CF(0,1,0),wood,Enum.Material.Wood)
		add(m,"RoundedStyleCabinetTop",V(5.25,.24,2.5),f*CF(0,1.82,0),edge,Enum.Material.Wood)
		for _,s in ipairs({-1,1}) do
			add(m,"RecessedCabinetDoor",V(2.28,1.02,.1),f*CF(s*1.2,1.03,-1.22),edge,Enum.Material.Wood,false)
			add(m,"SmallBrassCabinetPull",V(.38,.07,.16),f*CF(s*.38,1.26,-1.33),Color3.fromRGB(126,107,67),Enum.Material.Metal,false)
		end
		add(m,"CRTLowFoot",V(2.15,.17,1.63),f*CF(-.25,2.025,.08),black)
		local panelWidth,panelHeight=3.35,3.35*.75
		local panelY=2.115+panelHeight/2
		add(m,"DeepCRTBody",V(panelWidth,panelHeight,2.12),f*CF(-.25,panelY,-.02),Color3.fromRGB(69,60,46),Enum.Material.SmoothPlastic)
		-- The generated bitmap contains the entire bezel, screen, dials and vents.
		-- Map it once to a correctly proportioned full front, retaining actual depth.
		local panel=add(m,"FullCRTFrontPanel",V(panelWidth,panelHeight,.15),f*CF(-.25,panelY,-1.12),Color3.fromRGB(39,41,36),Enum.Material.SmoothPlastic,false)
		panel:SetAttribute("ScreenState","Off")
		if config.FurnitureTVTexture and config.FurnitureTVTexture~="" then
			local decal=Instance.new("Decal");decal.Name="CompleteCRTFrontPanel";decal.Texture=tostring(config.FurnitureTVTexture)
			decal.Face=Enum.NormalId.Front;decal.Color3=Color3.fromRGB(255,255,255);decal.Transparency=0;decal.Parent=panel
		end
	end
	local function diningSet(f,glitched)
		local m=item("SmallWoodDiningTable","DiningTable")
		legs(m,f,1.23,1.73,2.48,.21)
		if glitched then
			local tilt=math.rad(5)
			add(m,"FlatDiningTopPlank",V(1.68,.25,4.25),f*CF(-.86,2.605,0),edge,Enum.Material.Wood)
			local tiltedY=2.48+.125*math.cos(tilt)+.84*math.sin(tilt)
			add(m,"MisalignedDiningTopPlank",V(1.68,.25,4.25),f*CF(.86,tiltedY,0)*CFrame.Angles(0,0,tilt),edge,Enum.Material.Wood)
			-- A cleat spans the existing short aprons and supports the raised plank.
			add(m,"RaisedPlankSupportCleat",V(.26,.25,3.74),f*CF(.86,2.445,0),wood,Enum.Material.Wood)
			m:SetAttribute("BackroomsDistortion","Two tabletop planks disagree by five degrees; both remain supported")
			m:SetAttribute("GlitchedTable",true)
		else
			add(m,"VeneerDiningTop",V(3.4,.25,4.25),f*CF(0,2.605,0),edge,Enum.Material.Wood)
		end
		for _,s in ipairs({-1,1}) do
			add(m,"DiningTableLongApron",V(.17,.42,3.65),f*CF(s*1.35,2.22,0),wood,Enum.Material.Wood)
			add(m,"DiningTableShortApron",V(2.8,.42,.17),f*CF(0,2.22,s*1.86),wood,Enum.Material.Wood)
		end
		for _,s in ipairs({-1,1}) do
			local chair=item("PlainWoodDiningChair_"..s,"DiningChair")
			local cf=f*CF(0,0,s*3.3)*(s==-1 and yaw(180) or CF())
			legs(chair,cf,.78,.78,1.62,.16)
			add(chair,"WoodChairSeat",V(1.95,.23,1.95),cf*CF(0,1.735,0),edge,Enum.Material.Wood)
			for _,x in ipairs({-.8,.8}) do add(chair,"WoodChairBackPost",V(.15,2.05,.15),cf*CF(x,2.44,.84),wood,Enum.Material.Wood) end
			add(chair,"WoodChairBackTop",V(1.83,.24,.18),cf*CF(0,3.4,.84),edge,Enum.Material.Wood)
			add(chair,"WoodChairBackPanel",V(1.5,.63,.13),cf*CF(0,2.92,.84),edge,Enum.Material.Wood)
		end
	end
	local function wallClock(x,z)
		local m=item("StoppedWallClock","WallClock")
		local f=CF(x,6.8,z)*yaw(x<0 and -90 or 90)
		add(m,"WalnutClockCase",V(1.6,1.9,.18),f,wood,Enum.Material.Wood,false)
		add(m,"AgedClockFace",V(1.3,1.58,.035),f*CF(0,0,-.11),Color3.fromRGB(188,178,146),Enum.Material.SmoothPlastic,false)
		add(m,"StillClockHourHand",V(.065,.42,.025),f*CF(.13,.13,-.14)*CFrame.Angles(0,0,math.rad(-44)),black,nil,false)
		add(m,"StillClockMinuteHand",V(.047,.62,.025),f*CF(0,.24,-.145),black,nil,false)
	end
	local function framedPrint(x,z)
		local m=item("FadedFramedAbstractPrint","WallArt")
		local f=CF(x,6.15,z)*yaw(x<0 and -90 or 90)
		add(m,"MatteCanvas",V(2.75,3.4,.1),f,Color3.fromRGB(187,176,148),Enum.Material.Fabric,false)
		for _,s in ipairs({-1,1}) do
			add(m,"PictureFrameSide",V(.14,3.65,.16),f*CF(s*1.46,0,0),darkWood,Enum.Material.Wood,false)
			add(m,"PictureFrameEnd",V(3.05,.14,.16),f*CF(0,s*1.76,0),darkWood,Enum.Material.Wood,false)
		end
		add(m,"FadedOchreShape",V(.88,1.42,.025),f*CF(-.5,.25,-.065),Color3.fromRGB(139,115,71),Enum.Material.SmoothPlastic,false)
		add(m,"FadedSageShape",V(.72,.87,.025),f*CF(.55,-.55,-.067),Color3.fromRGB(100,115,91),Enum.Material.SmoothPlastic,false)
	end

	local sofaZ=depth*.56
	local leftX=-width/2+2.35
	local rightX=width/2-2.1
	if variant==1 then
		sofa(CF(leftX,0,sofaZ)*yaw(-90),compact and 5.4 or 7.2)
		tvCabinet(CF(rightX,0,sofaZ)*yaw(90))
		if not compact then framedPrint(-width/2+.56,sofaZ) end
	elseif variant==2 then
		sofa(CF(leftX,0,sofaZ)*yaw(-90),7.2)
		armchair(CF(leftX,0,sofaZ-5.9)*yaw(-90),false)
		sideTable(CF(leftX,0,sofaZ+5.2))
		wallClock(-width/2+.56,sofaZ+5.2)
	elseif variant==3 then
		diningSet(CF(-width/2+2.9,0,sofaZ),options.glitchedTable==true)
		tvCabinet(CF(rightX,0,sofaZ)*yaw(90))
	elseif variant==4 then
		armchair(CF(leftX,0,sofaZ-1.25)*yaw(-90),true)
		armchair(CF(leftX,0,sofaZ+1.25)*yaw(-90),false)
		tvCabinet(CF(rightX,0,sofaZ)*yaw(90))
		group:SetAttribute("BackroomsDistortion","Two chairs share a small edge; one backrest is too tall")
	elseif variant==5 then
		sofa(CF(leftX,0,sofaZ)*yaw(-90),7.2)
		sideTable(CF(leftX,0,sofaZ+5.2))
		wallClock(-width/2+.56,sofaZ-3)
	end
	assert(pieceCount>=2 and pieceCount<=4,"Furniture density exceeded the sparse-room contract")
	group:SetAttribute("PartCount",partCount)
	group:SetAttribute("FurniturePieceCount",pieceCount)
	home:SetAttribute("Level5FurnitureVersion",Furniture.Version)
	home:SetAttribute("Level5FurnitureVariant",variant)
	K.root:SetAttribute("Level5FurnishedHomeCount",furnished+1)
	return {Placed=true,Model=group,Variant=variant,VariantName=Furniture.VariantNames[variant],Compact=compact,PieceCount=pieceCount,PartCount=partCount,
		ClearLaneWidth=Furniture.ClearLaneWidth,LocalBounds=extents,FurnishedHomeCount=furnished+1}
end

Furniture.FurnishHouse=Furniture.FurnishHome
return Furniture
