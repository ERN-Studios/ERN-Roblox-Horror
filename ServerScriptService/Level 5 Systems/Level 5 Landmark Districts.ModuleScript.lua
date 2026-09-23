-- The Indoor Suburbs expansion: three connected landmark districts, geometry only.
-- All positions are RELATIVE to the architecture origin. K owns world placement,
-- the tinted-window implementation, material textures and instance accounting.
local Districts = {}

function Districts.Build(K)
	local model,part,floor,stairs,rail,house = K.model,K.part,K.floor,K.stairs,K.rail,K.house
	local window,bay,texture,wallLamp = K.window,K.bay,K.texture,K.wallLamp
	local C,V,CF = K.C,K.V,K.CF
	local yaw = function(a) return CFrame.Angles(0,math.rad(a),0) end
	local config=K.config or {}
	local cameras,waypoints,zones={},{},{}
	local function camera(name,p,t) table.insert(cameras,{name=name,position=p,lookAt=t}) end
	local function point(x,y,z) table.insert(waypoints,V(x,y,z)) end
	local function zone(name,minimum,maximum,description)
		local m=K.root:FindFirstChild(name) or model(name,K.root)
		m:SetAttribute("GeometryOnly",true)
		table.insert(zones,{Name=name,Min=minimum,Max=maximum,Description=description})
		return m
	end
	local function post(into,x,y,z,h)
		part(into,"DomesticSupportPier",V(2,h,2),CF(x,y+h/2,z),C.pale)
		part(into,"PierCapital",V(2.7,.6,2.7),CF(x,y+h-.3,z),C.white)
	end
	local function path(into,name,x,y,z,w,d,col)
		return floor(into,name,x,y+.035,z,w,d,col or C.carpet)
	end
	local function skirting(into,frame,w)
		part(into,"WideWhiteSkirting",V(w,.5,.3),frame*CF(0,.25,0),C.white)
	end
	local function thinPicture(into,frame,w,h)
		part(into,"EmptyPictureFrame",V(w,h,.3),frame,C.white,Enum.Material.Wood)
		part(into,"FadedPicturePaper",V(w-.65,h-.65,.32),frame*CF(0,0,-.03),C.carpet,Enum.Material.Fabric)
	end
	local function fixture(into,x,y,z)
		local panel=part(into,"LowResidentialLightFixture",V(5,.14,2),CF(x,y,z),Color3.fromRGB(236,231,204),Enum.Material.Neon,false)
		part(into,"LowResidentialLightFrame",V(5.4,.16,2.4),CF(x,y+.14,z),C.white)
		local light=Instance.new("SurfaceLight")
		light.Name="PlayableLevelFill"; light.Face=Enum.NormalId.Bottom; light.Angle=140
		light.Brightness=.8; light.Range=30; light.Shadows=false
		light.Color=Color3.fromRGB(249,236,211); light.Parent=panel
	end

	-- F: inhabited-looking domestic architecture becomes an enclosed urban canyon.
	-- Eight staggered façade stacks form courts and slots, rather than two towers.
	local F=zone("F_BayWindowCanyon",V(-150,0,796),V(150,108,1016),
		"Six and seven-storey domestic canyon; two switchback stair circuits, three walkable elevations, bay windows and cutaway rooms.")
	floor(F,"CanyonCarpetGround",0,0,906,300,220,C.carpet)
	path(F,"CentralGreenCarpetRunner",0,0,906,24,220,C.green)
	for _,z in ipairs({808,881,934,1003}) do path(F,"CrossCourtCarpet",0,0,z,176,11,C.pink) end
	local stacks={
		{z=832,x=82,stories=6,color=C.cream},
		{z=878,x=87,stories=7,color=C.pale},
		{z=925,x=79,stories=6,color=C.cream},
		{z=974,x=85,stories=7,color=C.pale},
	}
	for _,side in ipairs({-1,1}) do
		local facing=yaw(side*90)
		for index,spec in ipairs(stacks) do
			local stack=model((side<0 and "West" or "East").."HouseStack"..index,F)
			for storey=0,spec.stories-1 do
				-- Upper overhangs are shallow and intersect the stack beneath them.
				local overhang=storey>=3 and ((storey+index)%3-1)*2.25 or 0
				local face=CF(side*(spec.x-overhang),storey*15,spec.z)*facing
				local cut=(storey==2 and index==2) or (storey==4 and index==3)
				local home=house(stack,"CanyonDwelling_"..storey,face,35,29,14.7,
					(storey+index)%3==0 and C.pale or spec.color,nil,
					{open=storey<3,cutaway=cut,lit=false})
				local besideStair=storey<3 and ((side==-1 and index==1) or (side==1 and index==4))
				if not besideStair and (index==1 or index==4 or (storey%2==0 and index==3)) then
					bay(home,face*CF(storey<3 and -11 or 0,0,-.45),storey<3 and 8 or 14.4,7.6,false)
				elseif not besideStair then
					-- Offset glazed domestic projection, non-emissive like every window.
					part(home,"WindowBoxApron",V(9,2.4,2.7),face*CF(-11,1.2,-1.05),C.pale)
					window(home,face*CF(-11,6.1,-2.5),7.8,7.2,false)
					part(home,"WindowBoxCornice",V(9.6,.45,3),face*CF(-11,10.05,-1.1),C.white)
				end
				if storey>=3 then
					floor(stack,"HighScenicBalcony",0,0,-3.8,35,7.5,C.carpet,face)
					rail(stack,face*CF(0,0,-7.35),35)
				end
			end
			-- Side-facing windows make the slots between houses intentionally domestic.
			for storey=0,2 do
				window(stack,CF(side*(spec.x+15),storey*15+7.6,spec.z-17.9),9,9,false)
			end
		end
	end

	-- A stairwell is a real hole in the walk slab, not stairs intersecting a floor.
	local function balcony(side,height,stairA,stairB,flightX)
		local x=side*72
		floor(F,"CanyonWalkBeforeStair",x,height,(804+stairA)/2,34,stairA-804,C.carpet)
		floor(F,"CanyonWalkAfterStair",x,height,(stairB+1008)/2,34,1008-stairB,C.carpet)
		local low,high=flightX-7,flightX+7
		if low>55 then floor(F,"StairwellInnerBypass",side*(55+low)/2,height,(stairA+stairB)/2,low-55,stairB-stairA,C.carpet) end
		if high<89 then floor(F,"StairwellOuterBypass",side*(high+89)/2,height,(stairA+stairB)/2,89-high,stairB-stairA,C.carpet) end
		local bridgeZ=height==15 and 884 or 929
		for _,span in ipairs({{804,bridgeZ-7},{bridgeZ+7,1008}}) do
			rail(F,CF(side*55,height,(span[1]+span[2])/2)*yaw(90),span[2]-span[1])
		end
		for _,z in ipairs({804,1008}) do rail(F,CF(x,height,z),34) end
	end
	-- West circuit climbs north, turns on its landing, and returns south above itself.
	balcony(-1,15,814,846,65); balcony(-1,30,814,846,79)
	stairs(F,"WestCanyonFirstFlight",CF(-65,0,814),12,15,32,30,C.pink,true)
	stairs(F,"WestCanyonReturnFlight",CF(-79,15,846)*yaw(180),12,15,32,30,C.carpet,true)
	floor(F,"WestSwitchbackLanding",-72,15,850.5,34,9,C.carpet)
	-- East circuit is inverted and farther down the street for a second exploration loop.
	balcony(1,15,934,966,65); balcony(1,30,934,966,79)
	stairs(F,"EastCanyonFirstFlight",CF(65,0,966)*yaw(180),12,15,32,30,C.pink,true)
	stairs(F,"EastCanyonReturnFlight",CF(79,15,934),12,15,32,30,C.carpet,true)
	floor(F,"EastSwitchbackLanding",72,15,929.5,34,9,C.carpet)
	for _,bridge in ipairs({{y=15,z=884,w=112},{y=30,z=929,w=112}}) do
		floor(F,"ResidentialCrossing",0,bridge.y,bridge.z,bridge.w,13,C.carpet)
		for _,s in ipairs({-1,1}) do rail(F,CF(0,bridge.y,bridge.z+s*6.45),bridge.w) end
	end
	for _,side in ipairs({-1,1}) do
		for _,z in ipairs({859,900,946,1003}) do post(F,side*54,0,z,30) end
		-- Additional floors are visibly supported rather than floating slabs.
		part(F,"LowerBalconyFascia",V(1.3,1.8,204),CF(side*55.4,14.1,906),C.white)
		part(F,"UpperBalconyFascia",V(1.3,1.8,204),CF(side*55.4,29.1,906),C.white)
		for _,z in ipairs({851,901,950,1003}) do
			wallLamp(F,CF(side*53.6,7,z)*yaw(-side*90))
		end
	end
	-- Recessed cutaway lounge is discoverable off the main ground-level route.
	local recess=house(F,"CutawayReadingRoom",CF(-127,0,899)*yaw(-90),25,19,14,C.pale,nil,{open=true,cutaway=true,lit=false})
	floor(F,"ReadingRoomSideAccess",-109,0,900,42,13,C.carpet)
	part(recess,"LowEmptySofa",V(5,2.4,10),CF(-136,1.2,899),C.rose,Enum.Material.Fabric)
	thinPicture(recess,CF(-144.1,7,899)*yaw(-90),6,5)
	-- Small fragments of domestic vocabulary break the street's large repeated rhythm.
	for _,z in ipairs({859,906,953}) do
		part(F,"RecessedDoormat",V(8,.12,5),CF(41,.065,z),C.green,Enum.Material.Fabric,false)
		part(F,"ThinHallConsole",V(2.5,3,8),CF(48,1.5,z),C.pale,Enum.Material.Wood)
	end
	for _,p in ipairs({{-65,14.5,873},{65,14.5,898},{-65,29.5,906},{65,29.5,974},{0,14.4,884},{0,29.4,929}}) do fixture(F,p[1],p[2],p[3]) end
	camera("BayWindowCanyonEntrance",V(-11,7,802),V(69,48,890))
	camera("BayWindowCanyonUpperWalk",V(-60,35,855),V(60,54,974))
	camera("BayWindowCanyonCutaway",V(24,8,933),V(-82,29,899))
	point(0,3,802); point(0,3,881); point(0,3,1006)
	point(-65,3,810); point(-65,18,849); point(-79,33,810)
	point(65,3,970); point(65,18,930); point(79,33,970)
	point(0,18,884); point(0,33,929)

	-- G: a distorted residential subdivision arranged around three broad carpet levels.
	local G=zone("G_TiltedSubdivision",V(-160,0,1016),V(160,66,1196),
		"Eight distinct houses around broad green-carpet terraces at 0, 8 and 16 studs; alternate stair routes and a secret through-house passage.")
	floor(G,"SubdivisionGreenCarpet",0,0,1106,320,180,C.green)
	path(G,"EntryBentPath",-17,0,1032,52,13,C.carpet)
	path(G,"MiddleBentPath",12,0,1106,22,152,C.carpet)
	path(G,"ExitBentPath",26,0,1184,74,13,C.carpet)
	-- Substantial supports and white fascia make the height changes intentional.
	local function terrace(name,x,y,z,w,d)
		local m=model(name,G)
		part(m,"TerraceMass",V(w,y,d),CF(x,y/2,z),C.cream)
		floor(m,"TerraceGreenCarpet",x,y,z,w,d,C.green)
		for _,s in ipairs({-1,1}) do
			part(m,"TerraceLongWhiteFascia",V(.3,1.1,d),CF(x+s*w/2,y-.5,z),C.white)
			part(m,"TerraceEndWhiteFascia",V(w,1.1,.3),CF(x,y-.5,z+s*d/2),C.white)
		end
		return m
	end
	local west=terrace("WestRaisedNeighbourhood",-90,8,1094,110,112) -- z1038..1150
	local east=terrace("EastHighNeighbourhood",100,16,1109.5,90,89) -- z1065..1154
	stairs(G,"WestTerraceEntry",CF(-58,0,1018),13,8,20,16,C.pink,true)
	stairs(G,"WestTerraceFarReturn",CF(-43,0,1170)*yaw(180),13,8,20,16,C.pink,true)
	stairs(G,"EastTerraceEntry",CF(73,0,1033),13,16,32,32,C.carpet,true)
	stairs(G,"EastTerraceFarReturn",CF(123,0,1186)*yaw(180),13,16,32,32,C.carpet,true)
	-- Rails follow exposed edges, with clear openings at all four stair landings.
	rail(G,CF(-35,8,1094)*yaw(90),112)
	rail(G,CF(55,16,1109.5)*yaw(90),89)
	for _,r in ipairs({{-105,8,1038,80},{-98,8,1150,94},{116,16,1065,58},{85,16,1154,60}}) do rail(G,CF(r[1],r[2],r[3]),r[4]) end
	path(west,"WestTerraceWalk",-57,8,1094,12,111,C.carpet)
	path(east,"EastTerraceWalk",70,16,1109.5,15,88,C.carpet)
	local h1=house(G,"GroundBlueStarterHouse",CF(-12,0,1046),29,25,14.7,C.blue,C.lavender,{open=true,lit=false})
	local h2=house(west,"RosePorchHouse",CF(-105,8,1057)*yaw(-90),29,27,14.7,C.rose,C.blue,{open=true,lit=false})
	local h3=house(west,"YellowBowWindowHouse",CF(-106,8,1124)*yaw(-90),31,26,14.7,C.yellow,C.lavender,{open=true,lit=false})
	bay(h3,CF(-105.7,8,1124)*yaw(-90)*CF(-10,0,0),8,7,false)
	local secret=house(west,"SecretThroughHouse",CF(-65,8,1104),28,30,14.7,C.lavender,C.blue,{open=true,backOpening=true,lit=false})
	secret:SetAttribute("ExplorationLoop",true)
	thinPicture(secret,CF(-75,15,1133.5),4.5,3.8)
	part(secret,"EmptyRoomBench",V(2.5,2,9),CF(-75,9,1119),C.cream,Enum.Material.Wood)
	local h5=house(east,"HighTerraceCreamHouse",CF(113,16,1086)*yaw(90),30,27,14.7,C.pale,C.blue,{open=true,lit=false})
	local h6=house(east,"HighTerracePinkHouse",CF(113,16,1130)*yaw(90),30,27,14.7,C.pink,C.lavender,{open=true,lit=false})
	local h7=house(east,"ReversedSmallBlueHouse",CF(78,16,1120)*yaw(180),24,25,14.7,C.blue,C.pink,{open=true,lit=false})
	local h8=house(G,"LowExitYellowHouse",CF(37,0,1160),28,25,14.7,C.yellow,C.blue,{open=true,lit=false})
	-- Two tilted scenic houses are fused into broad domestic wall masses. Neither
	-- floats above the lawn, and their silhouettes cut across normal house outlines.
	local fusedA=model("WestFusedTiltedHome",G)
	part(fusedA,"SupportingDomesticVolume",V(46,19,25),CF(-122,17.5,1090),C.pale)
	local tiltedA=house(fusedA,"EmbeddedTiltedRoseHome",CF(-126,19,1078)*CFrame.Angles(0,math.rad(-12),math.rad(17)),31,25,14,C.rose,C.blue,{open=false,lit=false})
	window(fusedA,CF(-121,18,1077.35),14,10,false)
	local fusedB=model("EastFusedTiltedHome",G)
	part(fusedB,"SupportingDomesticVolume",V(34,22,27),CF(130,27,1133),C.cream)
	local tiltedB=house(fusedB,"EmbeddedTiltedCreamHome",CF(120,36,1119)*CFrame.Angles(0,math.rad(18),math.rad(-19)),28,25,13,C.pale,C.lavender,{open=false,lit=false})
	window(fusedB,CF(130,30,1119.2),12,11,false)
	-- A cropped hedge is made of carpeted boxes: it must read as indoor material,
	-- never as an outdoor landscape or an unexplained glowing object.
	for _,v in ipairs({{-147,8,1053},{-143,8,1138},{143,16,1071},{148,0,1174},{-22,0,1176}}) do
		part(G,"CarpetCoveredPlanter",V(5,2,7),CF(v[1],v[2]+1,v[3]),C.green,Enum.Material.Fabric)
		part(G,"PlanterWhiteFoot",V(5.3,.35,7.3),CF(v[1],v[2]+.18,v[3]),C.white)
	end
	fixture(G,-58,23,1082); fixture(G,74,31,1110)
	for _,p in ipairs({{-58,23,1082},{74,31,1110}}) do
		for _,s in ipairs({-1,1}) do part(G,"PendantSuspension",V(.055,65.8-p[2],.055),CF(p[1]+s*2,(65.8+p[2])/2,p[3]),C.grid,Enum.Material.Metal,false) end
	end
	camera("TiltedSubdivisionArrival",V(3,8,1022),V(-89,20,1090))
	camera("TiltedSubdivisionTerraces",V(-38,16,1145),V(113,32,1111))
	camera("TiltedSubdivisionFusedHomes",V(43,7,1176),V(122,39,1132))
	point(0,3,1020); point(10,3,1090); point(10,3,1179); point(0,3,1192)
	point(-58,3,1017); point(-58,11,1042); point(-65,11,1100); point(-65,11,1138); point(-43,3,1173)
	point(73,3,1030); point(73,19,1069); point(123,19,1150); point(123,3,1189)

	-- H: compression and quiet after the larger landmarks. The exit remains an
	-- open architectural preview; the three lamps are deliberately unwired.
	local H=zone("H_LastHouse",V(-60,-30,1196),V(60,26,1319),
		"Quiet final residential court, easy-puzzle room placeholder, arrow-marked rear opening and enclosed steep black chute.")
	floor(H,"QuietCourtCarpet",0,0,1225.5,120,59,C.carpet) -- ends exactly at chute mouth
	for _,s in ipairs({-1,1}) do
		floor(H,"ChuteSideGround",s*32.5,0,1265.5,55,21,C.carpet)
		part(H,"QuietCourtPlanter",V(4,2,6),CF(s*25,1,1216),C.green,Enum.Material.Fabric)
		house(H,"QuietClosedNeighbour"..s,CF(s*44,0,1206),23,24,14.2,C.cream,nil,{open=false,lit=false})
	end
	path(H,"LastHouseApproach",0,0,1210,17,28,C.pink)
	local finalHouse=house(H,"FinalHouse",CF(0,0,1224),42,31,15,C.pale,nil,{open=true,backOpening=true,lit=false})
	finalHouse:SetAttribute("PuzzleReady",true)
	finalHouse:SetAttribute("FutureDoorPlaneZ",1255)
	finalHouse:SetAttribute("GeometryOnly_NoPuzzle",true)
	for _,s in ipairs({-1,1}) do
		part(finalHouse,"InteriorRoomDivider",V(.55,15,10),CF(s*12,7.5,1230),C.cream)
		thinPicture(finalHouse,CF(s*14,7,1254.5),4.5,3.7)
		skirting(finalHouse,CF(s*12,0,1230)*yaw(90),10)
	end
	part(finalHouse,"PuzzleReadySideboard",V(12,3,2),CF(0,1.5,1242),Color3.fromRGB(135,111,82),Enum.Material.Wood)
	for _,x in ipairs({-4,0,4}) do
		part(finalHouse,"UnwiredLampBase",V(.9,.2,.9),CF(x,3.1,1242),C.white,Enum.Material.Metal)
		part(finalHouse,"UnwiredLampStem",V(.15,1.2,.15),CF(x,3.75,1242),C.white,Enum.Material.Metal)
		part(finalHouse,"UnwiredLampShade",V(1.4,.8,1.4),CF(x,4.7,1242),C.pale,Enum.Material.Fabric)
	end
	for _,s in ipairs({-1,1}) do
		local art=part(finalHouse,"ExitArrowArtSurface",V(4.7,4.7,.04),CF(s*7.5,6,1254.58),C.pale,Enum.Material.SmoothPlastic,false)
		if config.ArrowTexture and config.ArrowTexture~="" then
			local decal=Instance.new("Decal"); decal.Name="PaintedExitArrow"; decal.Texture=tostring(config.ArrowTexture); decal.Face=Enum.NormalId.Front; decal.Parent=art
		else
			part(finalHouse,"PaintedArrowShaft",V(3,.18,.05),CF(s*7.5,6,1254.53),C.red,Enum.Material.SmoothPlastic,false)
			for _,v in ipairs({-1,1}) do part(finalHouse,"PaintedArrowHead",V(1.4,.18,.055),CF(s*6.5,6+v*.43,1254.51)*CFrame.Angles(0,0,s*v*math.rad(40)),C.red,Enum.Material.SmoothPlastic,false) end
		end
	end
	local chute=model("NarrowDescent",H)
	local chuteStart,bend,chuteEnd=V(0,0,1255),V(0,-11,1287),V(0,-29,1310)
	local function chuteSegment(a,b,dark)
		local length=(b-a).Magnitude
		local frame=CFrame.lookAt((a+b)/2,b)
		local black=Color3.fromRGB(5,6,6)
		part(chute,"SmoothSlopingFloor",V(7.2,.85,length+.65),frame*CF(0,-.43,0),dark and black or C.carpet,Enum.Material.SmoothPlastic)
		for _,s in ipairs({-1,1}) do part(chute,"CloseChuteWall",V(.7,8.7,length+.65),frame*CF(s*3.95,4.3,0),dark and black or C.cream) end
		part(chute,"LowChuteCeiling",V(8.6,.65,length+.65),frame*CF(0,8.7,0),dark and black or C.ceiling)
		if not dark then part(chute,"LastFluorescent",V(3,.12,1.7),frame*CF(0,8.3,length*.25),Color3.fromRGB(185,191,154),Enum.Material.Neon,false) end
	end
	chuteSegment(chuteStart,bend,false); chuteSegment(bend,chuteEnd,true)
	floor(chute,"DarkArrivalFloor",0,-29,1314.5,8,9,Color3.fromRGB(3,4,4))
	part(chute,"DarkArrivalCeiling",V(8,.7,9),CF(0,-20.3,1314.5),Color3.fromRGB(3,4,4))
	for _,s in ipairs({-1,1}) do part(chute,"DarkArrivalSide",V(.7,9,9),CF(s*4,-24.5,1314.5),Color3.fromRGB(3,4,4)) end
	part(chute,"DarkArrivalEnd",V(8,9,.7),CF(0,-24.5,1319),Color3.fromRGB(3,4,4))
	chute:SetAttribute("GeometryOnly_NoSlideOrCompletion",true)
	chute:SetAttribute("SuggestedSlideStartFraction",.7)
	camera("LastHouseQuietCourt",V(-12,6,1198),V(4,8,1231))
	camera("LastHousePuzzleRoom",V(-8,7,1227),V(2,6,1254))
	camera("LastHouseDescent",V(0,5,1253),V(0,-10,1286))
	point(0,3,1198); point(0,3,1221); point(0,3,1236); point(7,3,1247); point(0,3,1253)
	point(0,-8,1287); point(0,-26,1314)
	return {PreviewCameras=cameras,Waypoints=waypoints,Zones=zones,FinalHouse=finalHouse,ChuteStart=chuteStart,ChuteEnd=chuteEnd}
end

return Districts
