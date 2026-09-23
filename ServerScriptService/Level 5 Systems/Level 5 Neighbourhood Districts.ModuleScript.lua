-- Three architectural districts for the expanded Indoor Suburbs.
-- K owns the common kit and origin transform; this module owns no services,
-- outer enclosure, global ceiling, Lighting settings, entities or gameplay.
local Districts = {}

function Districts.Build(K)
	local model,part,floor,stairs,rail=K.model,K.part,K.floor,K.stairs,K.rail
	local house,window,texture,wallLamp=K.house,K.window,K.texture,K.wallLamp
	local C,V,CF=K.C,K.V,K.CF
	local yaw=function(degrees) return CFrame.Angles(0,math.rad(degrees),0) end
	local cameras,waypoints,zones={},{},{}
	local function camera(name,p,t) table.insert(cameras,{name=name,position=p,lookAt=t}) end
	local function route(points) for _,p in ipairs(points) do table.insert(waypoints,p) end end
	local function path(into,name,a,b,width,color)
		local middle=(a+b)/2
		local p=floor(into,name,0,.035,0,width,(b-a).Magnitude,color or C.carpet,CFrame.lookAt(middle,b))
		-- Decorative carpets never create a second walking/collision surface.
		p.CanCollide=false
	end
	local function pathLoop(into,name,points,width,color)
		for i=1,#points-1 do path(into,name.."_"..i,points[i],points[i+1],width,color) end
	end
	local function shutters(into,frame,width,color)
		for _,s in ipairs({-1,1}) do
			local center=s*(width/4+1.35)
			for _,side in ipairs({-1,1}) do
				local x=center+side*(width/4-1.85)
				part(into,"PaintedWindowShutter",V(.8,7.3,.2),frame*CF(x,6.6,-.58),color,Enum.Material.Wood,false)
				for _,y in ipairs({4.3,6.6,8.9}) do part(into,"ShutterCrossSlat",V(.86,.11,.22),frame*CF(x,y,-.69),C.white,Enum.Material.Wood,false) end
			end
		end
	end
	local function porch(into,frame,width,color)
		floor(into,"CarpetDoorstep",0,.025,-3,width,6,C.carpet,frame)
		-- A canopy and posts distinguish a porch from a pasted-on house front.
		part(into,"PorchCanopy",V(width+1,.4,5.5),frame*CF(0,11.8,-2.8),color)
		for _,s in ipairs({-1,1}) do
			part(into,"PorchPost",V(.45,11.6,.45),frame*CF(s*(width/2-.4),5.8,-5.1),C.white)
		end
	end

	-- C: four overlapping courts replace a single straight miniature street.
	local village=model("C_PastelVillage",K.root)
	floor(village,"ContinuousGreenVillageCarpet",0,0,316,360,240,C.green)
	local cottages={
		{-113,224,-90,27,23,14,C.pale,C.blue,true,true},
		{-66,230,0,24,19,13,C.rose,C.lavender,true,false},
		{95,226,90,29,22,14,C.blue,C.lavender,true,true},
		{145,273,90,24,18,13,C.lavender,C.blue,true,false},
		{-139,285,-90,24,24,13,C.yellow,C.blue,true,true},
		{-81,299,-24,29,22,14,C.pale,C.lavender,true,false},
		{61,287,14,27,24,14,C.rose,C.blue,true,true},
		{112,329,135,25,21,13,C.yellow,C.lavender,true,false},
		{-134,355,-110,27,23,14,C.blue,C.lavender,true,true},
		{-64,365,180,25,22,13,C.lavender,C.blue,true,false},
		{62,369,0,28,21,14,C.pale,C.blue,true,true},
		{129,399,90,27,22,14,C.rose,C.lavender,false,false},
		{-120,410,-90,28,23,14,C.yellow,C.blue,true,false},
		{-58,414,180,27,23,13,C.rose,C.lavender,false,false},
	}
	for i,a in ipairs(cottages) do
		local f=CF(a[1],0,a[2])*yaw(a[3])
		local m=house(village,"CourtCottage_"..string.format("%02d",i),f,a[4],a[5],a[6],a[7],a[8],{open=a[9],backOpening=a[10],lit=false})
		m:SetAttribute("District","PastelVillage")
		m:SetAttribute("Enterable",a[9]);m:SetAttribute("ThroughHouseRoute",a[10])
		shutters(m,f,a[4],i%2==0 and C.blue or C.lavender)
		floor(m,"FrontCarpetStep",0,.015,-2.2,9,4.4,C.carpet,f)
		if i==1 or i==4 or i==7 or i==10 or i==13 then porch(m,f,10,a[7]) end
		if i%3==0 then
			-- Small fenced patches sit to one side; there is always a central gate.
			rail(m,f*CF(-8,0,-8),6)
			rail(m,f*CF(8,0,-8),6)
		end
	end
	local villageMain={V(0,0,196),V(-25,0,229),V(-5,0,268),V(31,0,305),V(9,0,338),V(-24,0,376),V(0,0,416),V(0,0,436)}
	pathLoop(village,"WindingMainCarpet",villageMain,14,C.carpet)
	local westLoop={V(-25,0,229),V(-99,0,224),V(-113,0,259),V(-114,0,316),V(-110,0,357),V(-94,0,396),V(-24,0,376)}
	local eastLoop={V(-5,0,268),V(46,0,252),V(118,0,263),V(94,0,307),V(86,0,341),V(103,0,389),V(60,0,420),V(0,0,416)}
	pathLoop(village,"WestCourtLoop",westLoop,10,C.carpet)
	pathLoop(village,"EastCourtLoop",eastLoop,10,C.carpet)
	path(village,"MiddleCourtCrossLink",V(-112,0,316),V(104,0,334),10,C.carpet)
	-- Low roofless garden-room outlines and carpet islands make the courts
	-- recognizable without turning the whole hall into a furnished town.
	for i,p in ipairs({V(-22,0,307),V(27,0,385),V(45,0,221),V(-119,0,386)}) do
		local m=model("EmptyGardenRoom_"..i,village)
		local f=CF(p)*yaw(i%2==0 and 12 or -10)
		floor(m,"FadedCarpetIsland",0,.025,0,19,15,i%2==0 and C.carpet or C.green,f)
		for _,s in ipairs({-1,1}) do part(m,"LowGardenBoundary",V(.7,2.1,15),f*CF(s*9.5,1.05,0),C.pale) end
		part(m,"GardenFarBoundary",V(19,2.1,.7),f*CF(0,1.05,7.5),C.pale)
	end
	camera("Village_EntryWide",V(-8,8,202),V(-68,12,262))
	camera("Village_OffsetCourts",V(-109,7,310),V(82,10,330))
	camera("Village_BackLane",V(113,7,374),V(-43,11,405))
	route({V(0,3,200),V(-25,3,229),V(-5,3,268),V(31,3,305),V(9,3,338),V(-24,3,376),V(0,3,416),V(0,3,432)})
	table.insert(zones,{Name="C_PastelVillage",Model=village,Min=V(-180,0,196),Max=V(180,48,436),CeilingHeight=48,HouseCount=14,EnterableHouses=12,ThroughHouses=6,RouteCount=3,Description="Four offset pastel courts, twelve enterable cottages, six through-house shortcuts and two broad carpet loops."})

	-- D: three continuous choices: the sunken pink street and either raised
	-- porch promenade. Two bridges and side flights let players change routes.
	local terraces=model("D_FloralTerraces",K.root)
	floor(terraces,"SunkenGreenCarpet",0,-12,536,180,200,C.green)
	floor(terraces,"TerraceEntryLanding",0,0,443,180,14,C.carpet)
	floor(terraces,"TerraceExitLanding",0,0,627,180,18,C.carpet)
	stairs(terraces,"PinkStreetDescent",CF(0,0,450),18,-12,28,24,C.pink,true)
	floor(terraces,"LowerPinkStreet",0,-12,534,18,112,C.pink)
	stairs(terraces,"PinkStreetAscent",CF(0,-12,590),18,12,28,24,C.pink,true)
	for _,s in ipairs({-1,1}) do
		floor(terraces,"RaisedPorchPromenade",s*53,0,534,20,168,C.yellow)
		for i,z in ipairs({464,502,548,587}) do
			local f=CF(s*63,0,z)*yaw(s*90)
			local m=house(terraces,"TerraceHouse_"..s.."_"..i,f,22,21,11.8,i%2==0 and C.yellow or C.rose,i%2==0 and C.blue or C.lavender,{open=true,lit=false})
			shutters(m,f,22,C.yellow)
			if i%2==1 then porch(m,f,9,C.yellow) end
			local paper=part(terraces,"FloralWallBand",V(.08,15.5,34),CF(s*89.3,23.7,z),Color3.fromRGB(206,191,151),Enum.Material.SmoothPlastic,false)
			texture(paper,K.config.FloralTexture,s==1 and Enum.NormalId.Left or Enum.NormalId.Right,14)
			part(terraces,"WallpaperLowerRail",V(.25,.45,34),CF(s*89.1,15.8,z),C.white)
		end
		local intervals=s==1 and {{450,485.5},{494.5,508},{520,563.5},{572.5,618}} or {{450,485.5},{494.5,548},{560,563.5},{572.5,618}}
		for _,r in ipairs(intervals) do rail(terraces,CF(s*43,0,(r[1]+r[2])/2)*yaw(90),r[2]-r[1]) end
	end
	for _,z in ipairs({490,568}) do
		floor(terraces,"PorchCrossBridge",0,0,z,126,9,C.yellow)
		rail(terraces,CF(0,0,z-4.5),84);rail(terraces,CF(0,0,z+4.5),84)
		-- Bridge undersides are clean; lower-route headroom remains10.8studs.
		for _,s in ipairs({-1,1}) do part(terraces,"BridgeSquarePier",V(1.2,12,1.2),CF(s*39,-6,z),C.yellow) end
	end
	stairs(terraces,"RightPromenadeFlight",CF(12,-12,514)*yaw(90),10,12,32,24,C.pink,true)
	stairs(terraces,"LeftPromenadeFlight",CF(-12,-12,554)*yaw(-90),10,12,32,24,C.pink,true)
	-- Side-flight feet meet broad carpet aprons rather than an isolated tread.
	floor(terraces,"RightFlightApron",15,-12,514,20,13,C.pink)
	floor(terraces,"LeftFlightApron",-15,-12,554,20,13,C.pink)
	local function underPorchRoom(s,z)
		local m=model("UnderPorchRoom_"..s.."_"..z,terraces)
		local f=CF(s*43,-12,z)*yaw(s*90)
		floor(m,"AlcoveCarpet",0,.02,13,18,26,C.carpet,f)
		for _,side in ipairs({-1,1}) do
			part(m,"AlcoveSideWall",V(.65,10.5,26),f*CF(side*9,5.25,13),C.pale)
			part(m,"AlcoveDoorPier",V(5.5,10.5,.65),f*CF(side*6.25,5.25,0),C.pale)
			part(m,"AlcoveDoorTrim",V(.3,9.3,.8),f*CF(side*3.65,4.65,-.08),C.white)
		end
		part(m,"AlcoveHeader",V(7,1.5,.65),f*CF(0,9.75,0),C.pale)
		part(m,"AlcoveBack",V(18,10.5,.65),f*CF(0,5.25,26),C.cream)
		part(m,"AlcoveCeiling",V(18,.45,26),f*CF(0,10.5,13),C.ceiling)
		part(m,"AlcoveCrown",V(18,.3,.75),f*CF(0,10.2,-.12),C.white)
	end
	for _,s in ipairs({-1,1}) do underPorchRoom(s,478);underPorchRoom(s,579) end
	camera("Terraces_LongDescent",V(0,8,442),V(4,-3,516))
	camera("Terraces_UnderBridge",V(-19,-5,528),V(49,7,575))
	camera("Terraces_PorchRoute",V(49,6,593),V(-31,9,497))
	route({V(0,3,442),V(0,-3,464),V(0,-9,482),V(0,-9,520),V(0,-9,570),V(0,-3,604),V(0,3,626),V(0,3,633)})
	table.insert(zones,{Name="D_FloralTerraces",Model=terraces,Min=V(-90,-13.2,436),Max=V(90,32,636),CeilingHeight=32,LowestFloor=-12,RetainingWallBottom=-13.2,HouseCount=8,EnterableHouses=8,RouteCount=3,MaximumStairRise=.5,Description="A sunken pink street, two raised yellow porch routes, two crossbridges and four low domestic alcoves. Outer enclosure must retain the lower floor down to−13.2."})

	-- E: offset domestic rooms form three converging routes. There are no
	-- required switches, locked doors, items, enemies or arbitrary dead ends.
	local rooms=model("E_DomesticLabyrinth",K.root)
	floor(rooms,"ContinuousDomesticCarpet",0,0,716,200,160,C.carpet)
	local function wall(name,frame,length,doors,windows,color)
		local m=model(name,rooms)
		local openings={}
		for _,d in ipairs(doors or {}) do table.insert(openings,{at=d[1],width=d[2],bottom=0,height=d[3] or 10.5,door=true}) end
		for _,w in ipairs(windows or {}) do table.insert(openings,{at=w[1],width=w[2],bottom=w[3] or 3,height=w[4] or 6.5,door=false}) end
		table.sort(openings,function(a,b) return a.at<b.at end)
		local cursor=0;local height=14.8
		local function solid(start,finish)
			if finish-start<.02 then return end
			part(m,"PlasterWall",V(finish-start,height,.65),frame*CF((start+finish)/2,height/2,0),color or C.cream,Enum.Material.Plaster)
			part(m,"WhiteBaseboard",V(finish-start,.45,.9),frame*CF((start+finish)/2,.23,0),C.white)
		end
		for _,o in ipairs(openings) do
			local left,right=o.at-o.width/2,o.at+o.width/2
			assert(left>=cursor and right<=length,"Overlapping domestic wall openings: "..name)
			solid(cursor,left)
			local top=o.bottom+o.height
			part(m,"OpeningLintel",V(o.width,height-top,.65),frame*CF(o.at,top+(height-top)/2,0),color or C.cream,Enum.Material.Plaster)
			if o.door then
				for _,s in ipairs({-1,1}) do part(m,"DeepWhiteDoorCasing",V(.42,o.height+.25,1.0),frame*CF(o.at+s*(o.width/2+.16),o.height/2,0),C.white,Enum.Material.Wood) end
				part(m,"WhiteDoorCrown",V(o.width+.85,.42,1.0),frame*CF(o.at,o.height+.1,0),C.white,Enum.Material.Wood)
			else
				part(m,"WindowApronWall",V(o.width,o.bottom,.65),frame*CF(o.at,o.bottom/2,0),color or C.cream)
				part(m,"WindowBaseboard",V(o.width,.45,.9),frame*CF(o.at,.23,0),C.white)
				window(m,frame*CF(o.at,o.bottom+o.height/2,-.08),o.width,o.height,false)
			end
			cursor=right
		end
		solid(cursor,length)
		part(m,"ContinuousCrownMoulding",V(length,.4,.85),frame*CF(length/2,14.45,0),C.white)
		return m
	end
	local function horizontal(name,x1,x2,z,doors,windows,color) return wall(name,CF(x1,0,z),x2-x1,doors,windows,color) end
	local function vertical(name,x,z1,z2,doors,windows,color) return wall(name,CF(x,0,z1)*yaw(-90),z2-z1,doors,windows,color) end
	vertical("WestDomesticBoundary",-86,636,796,nil,{{25,12},{81,12},{137,12}},C.pale)
	vertical("EastDomesticBoundary",86,636,796,nil,{{29,12},{86,12},{139,12}},C.pale)
	vertical("EntryFoyerLeft",-28,636,660,{{13,8}},nil)
	vertical("EntryFoyerRight",28,636,660,{{13,8}},{{4.5,4,3,6}})
	horizontal("OffsetFirstDoorRow",-86,86,660,{{17,9},{72,9},{148,9}},nil,C.pale)
	vertical("FirstSittingRoomWest",-56,660,692,{{18,8}},{{6,6,3,6.5}})
	vertical("FirstSittingRoomEast",8,660,692,nil,{{18,11,3,6.5}})
	vertical("EastAnteroomDivider",44,660,692,{{14,8}},nil,C.pale)
	horizontal("SittingRoomToGallery",-86,44,692,{{17,9},{51,9},{84,9}},{{111,10,3,6.5}})
	horizontal("EastReadingRoomHeader",44,86,692,{{19,9}},nil)
	vertical("WestLoopLounge",-56,692,726,{{16,8}},nil,C.pale)
	vertical("GalleryWestWindowWall",-12,692,726,{{17,8}},{{28,6,3,6.5}})
	vertical("GalleryEastDoorWall",44,692,721,{{14,9}},nil,C.pale)
	horizontal("WestLoopLowerCrossing",-86,-12,726,{{17,9},{52,9}},nil)
	horizontal("OffsetSecondDoorRow",-12,86,721,{{32,10},{78,10}},nil,C.pale)
	vertical("LongSittingRoomWest",-18,726,760,{{13,8}},{{25,8,3,6.5}})
	vertical("LongSittingRoomEast",56,721,760,{{28,8}},{{13,10,3,6.5}})
	horizontal("ExitRoomDoorRow",-86,86,760,{{26,9},{78,10},{155,9}},nil,C.pale)
	vertical("ExitFoyerLeft",-24,760,796,{{19,8}},{{6,7,3,6}})
	vertical("ExitFoyerRight",24,760,796,{{16,8}},{{29,7,3,6}})
	-- A few ceiling soffits deliberately compress the domestic proportions;
	-- they stop well inside the zone, away from the18×14 boundary portals.
	for _,a in ipairs({{-15,671,36,6},{20,732,48,6},{-61,741,37,6}}) do
		part(rooms,"LowDomesticSoffit",V(a[3],2.8,a[4]),CF(a[1],13.4,a[2]),C.pale)
		part(rooms,"SoffitWhiteLip",V(a[3],.35,a[4]+.25),CF(a[1],12.13,a[2]),C.white)
	end
	local roomCarpets={
		{-53,648,54,17,Color3.fromRGB(164,150,132)},
		{-24,680,50,19,Color3.fromRGB(159,152,133)},
		{65,705,34,22,Color3.fromRGB(171,159,140)},
		{-37,709,32,22,Color3.fromRGB(163,150,130)},
		{17,742,65,23,Color3.fromRGB(169,158,138)},
		{58,779,50,24,Color3.fromRGB(160,151,132)},
	}
	for i,a in ipairs(roomCarpets) do local p=floor(rooms,"SubtleRoomCarpet_"..i,a[1],.02,a[2],a[3],a[4],a[5]);p.CanCollide=false end
	local function freestandingFrame(name,x,z,angle)
		local m=model(name,rooms);local f=CF(x,0,z)*yaw(angle)
		for _,s in ipairs({-1,1}) do part(m,"UncannyDoorJamb",V(.6,10.8,.85),f*CF(s*5.1,5.4,0),C.white,Enum.Material.Wood) end
		part(m,"UncannyDoorHeader",V(10.8,.55,.85),f*CF(0,10.8,0),C.white,Enum.Material.Wood)
	end
	freestandingFrame("MisalignedInteriorDoorframe",-29,680,8)
	freestandingFrame("DoorframeToEmptySittingRoom",33,744,-9)
	for _,a in ipairs({{-55,7,704,90},{43,7,675,-90},{-17,7,751,90},{23,7,787,90}}) do wallLamp(rooms,CF(a[1],a[2],a[3])*yaw(a[4])) end
	camera("Domestic_OffsetDoorways",V(-14,6,650),V(-3,7,707))
	camera("Domestic_InteriorWindow",V(-42,6,711),V(22,7,721))
	camera("Domestic_LongSittingRoom",V(42,6,750),V(-12,7,767))
	route({V(0,3,640),V(-14,3,654),V(-14,3,675),V(-2,3,687),V(-2,3,704),V(20,3,712),V(20,3,733),V(-8,3,750),V(-8,3,770),V(0,3,792)})
	table.insert(zones,{Name="E_DomesticLabyrinth",Model=rooms,Min=V(-100,0,636),Max=V(100,15,796),CeilingHeight=15,LowestSoffit=12,RouteCount=3,Description="Offset empty sitting rooms, dark interior windows, deep white doorframes and west/east loops that rejoin the exit foyer.",
		LoopRoutes={
			{V(-14,3,649),V(-45,3,649),V(-69,3,649),V(-69,3,676),V(-69,3,708),V(-35,3,708),V(-4,3,708)},
			{V(20,3,707),V(69,3,707),V(69,3,749),V(69,3,777),V(12,3,777),V(0,3,789)},
		}})
	return {PreviewCameras=cameras,Waypoints=waypoints,Zones=zones}
end

return Districts
