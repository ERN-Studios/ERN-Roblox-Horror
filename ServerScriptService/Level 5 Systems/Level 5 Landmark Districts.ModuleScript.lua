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
		table.insert(zones,{Name=name,Model=m,Min=minimum,Max=maximum,CeilingHeight=maximum.Y,Description=description})
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

	-- F: several intimate courts lie below a much taller, tangled domestic skyline.
	-- All houses retain human dimensions. Only the scenic upper floors are closed.
	local F=zone("F_BayWindowCanyon",V(-250,0,1596),V(250,156,2076),"Deep carpet courts, nested small houses and continuous balconies below asymmetric residential towers.")
	F:SetAttribute("CourtVersion","2026-09-26.dense-courts")
	F:SetAttribute("PlayableFloorHeights","0,14,28")
	floor(F,"CanyonCarpet",0,0,1836,500,480,C.carpet)
	local sage=Color3.fromRGB(139,145,119)
	local homes={}
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({1650,1732,1832,1932,2020}) do
			local tower=model("NestedCanyonTower_"..side.."_"..i,F)
			local levels=({6,9,5,8,7})[i]
			for level=0,levels-1 do
				-- Small high-level setbacks articulate the silhouette without
				-- shearing walkable walls into stairs or adjacent rooms.
				local setback=level>=3 and (level%3)*3 or 0
				local frame=CF(side*(140+setback),level*14,z+(level>=4 and (i%2)*3 or 0))*yaw(side*90)
				local home=house(tower,"CanyonHome_"..level,frame,30,28,13.8,(i+level)%3==0 and sage or (i%2==0 and C.pale or C.cream),level==levels-1 and C.blue or nil,{open=level<=2,furniture=level==0 and i==3 and (side<0 and 4 or 2) or nil})
				if (i==1 and level==3) or (i==2 and level==5) or (i==4 and level==4) or (i==5 and level==3) then
					local projection=model("ProjectingDomesticBay",home)
					bay(projection,frame*CF(0,0,-.65),22,8,false)
					projection:SetAttribute("ClosedScenicProjection",true)
				end
				if side==-1 and i==3 and level==1 then K.registerWatcher(home,"MiddleCourtWindow",F.Name) end
				if side==1 and i==5 and level==2 then K.registerWatcher(home,"FarUpperWindow",F.Name) end
				if level>=3 and level%2==1 then
					floor(tower,"ScenicOffsetPorch",0,0,-3,32,6,C.carpet,frame)
					rail(tower,frame*CF(0,0,-6),32)
				end
			end
		end
		for _,height in ipairs({14,28}) do
			floor(F,"ContinuousCanyonBalcony",side*126,height,1831,28,442,C.carpet)
			local gaps=height==14 and (side<0 and {{1652,1665},{1768,1782}} or {{1768,1782},{1889,1901}}) or {{1931,1943},{1963,1977}}
			K.edgeRail(F,side*112,height,1610,2052,gaps)
			rail(F,CF(side*126,height,1610),28);rail(F,CF(side*126,height,2052),28)
		end
		for i,z in ipairs({1710,1880,2010}) do
			for level=0,1 do house(F,"OuterCourtHome_"..side.."_"..i.."_"..level,CF(side*214,level*14,z)*yaw(side*90),30,25,13.8,i%2==0 and C.rose or sage,level==1 and C.lavender or nil,{open=level==0,backOpening=level==0 and i==2}) end
			floor(F,"SideCourtLanding",side*187,.03,z,46,36,C.green)
		end
		for i,z in ipairs({1708,1864,1998}) do
			local levels=i==2 and 3 or 1
			for level=0,levels-1 do
				local home=house(F,"CourtIslandHome_"..side.."_"..i.."_"..level,CF(side*44,level*14,z),28,24,13.8,side<0 and C.rose or C.pale,level==levels-1 and C.blue or nil,{open=level==0,backOpening=level==0})
				if side==-1 and i==1 and level==0 then K.registerWatcher(home,"NearGroundWindow",F.Name) end
			end
		end
	end
	stairs(F,"CanyonFirstFlight",CF(-95,0,1620),14,14,32,28,C.carpet,true)
	floor(F,"CanyonFirstLanding",-110.5,14,1657,43,10,C.carpet)
	floor(F,"CanyonMiddleBridge",0,14,1775,254,14,C.carpet)
	for _,z in ipairs({1768,1782}) do rail(F,CF(0,14,z),224) end
	stairs(F,"CanyonSecondFlight",CF(95,14,1900),14,14,32,28,C.carpet,true)
	floor(F,"CanyonSecondBase",110.5,14,1895,43,10,C.carpet)
	floor(F,"CanyonSecondLanding",110.5,28,1937,43,10,C.carpet)
	floor(F,"CanyonHighBridge",0,28,1970,254,14,C.carpet)
	for _,z in ipairs({1963,1977}) do rail(F,CF(0,28,z),224) end
	for _,side in ipairs({-1,1}) do for _,z in ipairs({1612,1775,1970,2050}) do post(F,side*110,0,z,28) end end
	-- Inhabitable scale without inhabitants: a series of nested domestic blocks
	-- breaks the floor into short, readable courts. The old isolated lintels are
	-- replaced by supported residential volumes and real doorways.
	for i,info in ipairs({{0,1645,46,32,3},{0,1800,50,30,5},{-5,1920,54,28,4},{0,2038,70,24,2}}) do
		local x,z,w,d,count=table.unpack(info)
		for level=0,count-1 do
			house(F,"NestedCourtInfill_"..i.."_"..level,CF(x,level*14,z),w,d,13.8,i%2==0 and sage or C.pale,level==count-1 and C.blue or nil,{open=level==0,completeHome=level==0,furniture=level==0 and i<=2 and (i==1 and 6 or 8) or nil})
		end
	end
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({1800,1960}) do
			local count=i==1 and 4 or 6
			for level=0,count-1 do house(F,"SideCourtDomesticStack_"..side.."_"..i.."_"..level,CF(side*190,level*14,z)*yaw(side*90),30,28,13.8,side<0 and C.rose or sage,level==count-1 and C.lavender or nil,{open=level==0,completeHome=level==0}) end
		end
	end
	camera("ExpandedCanyonArrival",V(8,7,1604),V(-139,48,1741))
	camera("ExpandedCanyonMiddleBalcony",V(-121,20,1789),V(117,48,1935))
	camera("ExpandedCanyonSkyline",V(8,8,1820),V(145,104,1736))
	camera("ExpandedCanyonHighBridge",V(94,34,1970),V(-140,43,1828))
	camera("ExpandedCanyonOuterCourt",V(184,7,1912),V(217,23,2012))
	for _,z in ipairs({1602,1660,1740,1810,1880,1950,2020,2070}) do point(0,3,z) end

	-- G: the wide subdivision has habitable terraces below two impossible pairs
	-- of tall stacks. Tilted domestic volumes rest on piers outside enterable homes.
	local G=zone("G_TiltedSubdivision",V(-240,0,2076),V(240,180,2456),"Carpet lawns, two playable terraces and supported tilted houses between towering domestic stacks.")
	floor(G,"SubdivisionGreenCarpet",0,0,2266,480,380,C.green)
	floor(G,"SubdivisionCentralRunner",0,.03,2266,22,376,C.carpet)
	for _,s in ipairs({-1,1}) do
		for i,z in ipairs({2150,2350}) do
			local tower=model("ImpossibleDomesticTower_"..s.."_"..i,G)
			local count=i==1 and 10 or 11
			for level=0,count-1 do
				local frame=CF(s*(176+(level%3)*2),level*14,z+(level>=5 and s*3 or 0))*yaw(s*90)
				local home=house(tower,"TowerDwelling_"..level,frame,30,28,13.8,(level+i)%3==0 and C.pale or C.cream,level==count-1 and C.blue or nil,{open=level==0})
				if level==3 or level==6 then
					local projection=model("ProjectingDomesticBay",home)
					bay(projection,frame*CF(0,0,-.65),24,8.4,false)
					projection:SetAttribute("ClosedScenicProjection",true)
				end
				if level==0 and i==1 then K.registerWatcher(home,"SubdivisionTowerWindow_"..s,G.Name) end
				if level>=2 and level%2==0 then
					floor(tower,"HighClosedPorch",0,0,-3,33,6,C.carpet,frame)
					rail(tower,frame*CF(0,0,-6),33)
				end
			end
		end
	end
	floor(G,"WestEightStudTerrace",-110,8,2270,80,242,C.carpet)
	floor(G,"EastSixteenStudTerrace",110,16,2270,80,242,C.carpet)
	for _,s in ipairs({-1,1}) do
		local y=s<0 and 8 or 16
		for i,z in ipairs({2188,2270,2352}) do
			local frame=CF(s*116,y,z)*yaw(s*90)
			house(G,"TerraceCottage_"..s.."_"..i,frame,30,29,13.8,i==2 and C.rose or C.pale,i==2 and C.lavender or C.blue,{open=true,backOpening=i==2,furniture=i==2 and (s<0 and 3 or 5) or nil})
		end
		K.edgeRail(G,s*70,y,2149,2391,{{2200,2216},{2263,2277},{2324,2340}})
		for _,z in ipairs({2149,2391}) do rail(G,CF(s*110,y,z),80) end
	end
	-- Solid masonry beneath the terraces closes low headroom crawl-throughs and
	-- makes the domestic streets read as a terraced subdivision, not platforms.
	for _,side in ipairs({-1,1}) do
		local height=side<0 and 8 or 16
		for _,x in ipairs({70,150}) do K.material(part(G,"TerraceFoundationSide",V(1,height,242),CF(side*x,height/2,2270),C.pale,Enum.Material.Plaster),"Plaster") end
		for _,z in ipairs({2149,2391}) do K.material(part(G,"TerraceFoundationEnd",V(81,height,1),CF(side*110,height/2,z),C.pale,Enum.Material.Plaster),"Plaster") end
	end
	-- Flights sit in dedicated inner-side pockets, never under a solid terrace.
	stairs(G,"WestTerraceEntryFlight",CF(-54,0,2176),14,8,24,16,C.pink,true)
	floor(G,"WestTerraceEntryLanding",-68,8,2208,42,16,C.pink)
	stairs(G,"WestTerraceReturnFlight",CF(-54,0,2364)*yaw(180),14,8,24,16,C.pink,true)
	floor(G,"WestTerraceReturnLanding",-68,8,2332,42,16,C.pink)
	stairs(G,"EastTerraceEntryFlight",CF(54,0,2160),14,16,40,32,C.pink,true)
	floor(G,"EastTerraceEntryLanding",68,16,2208,42,16,C.pink)
	stairs(G,"EastTerraceReturnFlight",CF(54,0,2380)*yaw(180),14,16,40,32,C.pink,true)
	floor(G,"EastTerraceReturnLanding",68,16,2332,42,16,C.pink)
	-- Higher platforms remain separate, with ordinary stairs connecting them.
	floor(G,"TerraceCrossingLowerHalf",-22,8,2270,56,14,C.carpet)
	stairs(G,"TerraceCrossingRise",CF(6,8,2270)*yaw(90),14,8,24,16,C.carpet,true)
	floor(G,"TerraceCrossingUpperHalf",47,16,2270,38,14,C.carpet)
	-- The crossing's left end joins the west terrace via a short six-stud apron.
	floor(G,"TerraceCrossingWestApron",-60,8,2270,20,14,C.carpet)
	floor(G,"TerraceCrossingEastApron",68,16,2270,12,14,C.carpet)
	for _,z in ipairs({2263,2277}) do
		rail(G,CF(-34,8,z),72);rail(G,CF(50,16,z),48)
	end
	for _,s in ipairs({-1,1}) do
		local group=model("FusedTiltedHouses_"..s,G)
		for _,z in ipairs({2207,2296}) do
			local frame=CF(s*179,45,z)*yaw(s*90)*CFrame.Angles(math.rad(s*14),0,math.rad(s*21))
			house(group,"TiltedClosedHome_"..z,frame,32,29,13.8,C.cream,C.lavender,{open=false})
		end
		-- The support is hollow over actual domestic rooms, not a solid block.
		for _,z in ipairs({2180,2318}) do part(group,"TallOffsetSupportPier",V(6,50,6),CF(s*216,25,z),C.pale) end
		part(group,"SupportingDomesticLintel",V(57,5,12),CF(s*188,49,2250),C.pale)
	end
	for _,s in ipairs({-1,1}) do
		house(G,"GroundDetachedHome_"..s,CF(s*42,0,2106),28,24,13.8,s<0 and C.rose or C.pale,C.blue,{open=true,backOpening=true})
		house(G,"DepartureDetachedHome_"..s,CF(s*43,0,2410),28,26,13.8,C.cream,C.lavender,{open=true})
	end
	for level=0,2 do house(G,"CentralTerracedResidence_"..level,CF(0,level*14,2220),72,40,13.8,C.cream,nil,{open=level==0,completeHome=level==0,furniture=level==0 and 7 or nil}) end
	-- A smaller ordinary house grows at a wrong angle from the otherwise usable
	-- lower residence. Its base remains supported, far above the crossing.
	house(G,"PerchedAngledResidence",CF(8,42,2240)*yaw(12)*CFrame.Angles(0,0,math.rad(-8)),32,28,13.8,C.pale,C.blue,{open=false})
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({2240,2290}) do
			for level=0,1 do house(G,"OuterGardenResidence_"..side.."_"..i.."_"..level,CF(side*214,level*14,z)*yaw(side*90),28,24,13.8,i==1 and C.rose or C.pale,level==1 and C.lavender or nil,{open=level==0}) end
		end
	end
	camera("ExpandedTiltedArrival",V(7,7,2083),V(-172,73,2206))
	camera("ExpandedTiltedTerrace",V(87,22,2330),V(-167,108,2350))
	camera("ExpandedTiltedCrossing",V(-58,14,2267),V(185,61,2238))
	camera("ExpandedTiltedRear",V(-12,8,2440),V(176,112,2345))
	for _,z in ipairs({2082,2152,2220,2290,2360,2420,2450}) do point(0,3,z) end

	-- H: domestic familiarity compresses into an offset vestibule, then the
	-- narrow descent. This remains architecture only: no puzzle, slide or win.
	local H=zone("H_LastHouse",V(-110,-30,2456),V(110,70,2679),
		"Quiet final residential court, sparse waiting house, offset low vestibule, painted directions and enclosed black descent.")
	floor(H,"QuietCourtCarpet",0,0,2535.5,220,159,C.carpet) -- ends exactly at chute mouth
	for _,s in ipairs({-1,1}) do
		floor(H,"ChuteSideGround",s*57.5,0,2625.5,105,21,C.carpet)
		K.material(part(H,"QuietCourtPlanter",V(4,2,6),CF(s*25,1,2576),C.green,Enum.Material.Grass),"Grass")
		local home=house(H,"QuietClosedNeighbour"..s,CF(s*67,0,2566),28,24,14.2,C.cream,nil,{open=false,lit=false})
		if s==-1 then K.registerWatcher(home,"LastHouseNeighbourWindow",H.Name) end
		for i,z in ipairs({2485,2526}) do house(H,"QuietApproachHouse_"..s.."_"..i,CF(s*75,0,z)*yaw(s*90),28,26,13.8,C.pale,i==1 and C.blue or nil,{open=true,furniture=i==1 and (s<0 and 1 or 2) or nil}) end
	end
	-- One final nested home bends the arrival lane left, then releases it into
	-- the quiet final-house reveal. The vestibule and complete chute stay intact.
	for level=0,2 do house(H,"LastNeighbourhoodHall_"..level,CF(0,level*14,2496),44,30,13.8,C.pale,level==2 and C.blue or nil,{open=level==0,completeHome=level==0,furniture=level==0 and 8 or nil}) end
	path(H,"LastHouseApproach",0,0,2570,17,28,C.pink)
	local finalHouse=house(H,"FinalHouse",CF(0,0,2584),42,31,15,C.pale,nil,{open=true,backOpening=true,lit=false})
	finalHouse:SetAttribute("PuzzleReady",true)
	finalHouse:SetAttribute("FutureDoorPlaneZ",2615)
	finalHouse:SetAttribute("GeometryOnly_NoPuzzle",true)
	finalHouse:SetAttribute("EndingArchitectureVersion","2026-09-25.1")
	finalHouse:SetAttribute("RearVestibuleClearance",10.6)
	for _,s in ipairs({-1,1}) do
		part(finalHouse,"InteriorRoomDivider",V(.55,15,10),CF(s*12,7.5,2590),C.cream)
		skirting(finalHouse,CF(s*12,0,2590)*yaw(90),10)
	end

	-- A few deliberately ordinary objects occupy the side alcove. Nothing sits
	-- in the entry or the turning path, and nothing implies an active puzzle.
	local waiting=model("QuietWaitingAlcove",finalHouse)
	local wood=Color3.fromRGB(121,94,63)
	local woodEdge=Color3.fromRGB(153,122,85)
	local darkWood=Color3.fromRGB(74,58,42)
	local cabinet=CF(-18.35,0,2597.2)*yaw(-90)
	for _,x in ipairs({-2.35,2.35}) do for _,z in ipairs({-.72,.72}) do
		part(waiting,"CabinetRaisedFoot",V(.22,.42,.22),cabinet*CF(x,.21,z),darkWood,Enum.Material.Wood)
	end end
	part(waiting,"LowVeneerSideboard",V(5.8,2.3,2.15),cabinet*CF(0,1.55,0),wood,Enum.Material.Wood)
	part(waiting,"SideboardOverhangingTop",V(6,.22,2.32),cabinet*CF(0,2.81,0),woodEdge,Enum.Material.Wood)
	part(waiting,"SideboardDarkToeRecess",V(5.3,.18,1.8),cabinet*CF(0,.48,0),darkWood,Enum.Material.Wood)
	for _,x in ipairs({-1.42,1.42}) do
		part(waiting,"RecessedSideboardDoor",V(2.66,1.86,.07),cabinet*CF(x,1.59,-1.12),woodEdge,Enum.Material.Wood,false)
		part(waiting,"SmallDullSideboardPull",V(.32,.08,.13),cabinet*CF(x<0 and -.3 or .3,1.9,-1.22),darkWood,Enum.Material.Metal,false)
	end
	local chair=CF(-16.7,0,2589.8)*yaw(-7)
	for _,x in ipairs({-.86,.86}) do for _,z in ipairs({-.86,.86}) do
		part(waiting,"WaitingChairLeg",V(.17,1.7,.17),chair*CF(x,.85,z),wood,Enum.Material.Wood)
	end end
	part(waiting,"WaitingChairSeat",V(2.08,.22,2.08),chair*CF(0,1.81,0),woodEdge,Enum.Material.Wood)
	for _,x in ipairs({-.86,.86}) do
		part(waiting,"WaitingChairBackPost",V(.17,2.35,.17),chair*CF(x,2.65,.86),wood,Enum.Material.Wood)
	end
	part(waiting,"WaitingChairBackRail",V(1.88,.25,.19),chair*CF(0,3.73,.86),woodEdge,Enum.Material.Wood)
	part(waiting,"WaitingChairBackPanel",V(1.53,.62,.13),chair*CF(0,3.1,.86),woodEdge,Enum.Material.Wood)
	thinPicture(finalHouse,CF(-15.3,6.8,2614.5299999999997),4.1,3.3)

	-- The nine-stud opening is intentionally off-axis from both exterior doors.
	-- The return wall ends with 7.475 studs of clear turning depth at the rear.
	-- Preserve the front door and the original seven-stud chute doorway.
	local vestibule=model("OffsetRearVestibule",finalHouse)
	part(vestibule,"VestibuleFrontLeftWall",V(25.5,15,.65),CF(-8.25,7.5,2601.5),C.cream)
	part(vestibule,"VestibuleFrontRightWall",V(7.5,15,.65),CF(17.25,7.5,2601.5),C.cream)
	part(vestibule,"VestibuleDoorLintel",V(9,4.7,.65),CF(9,12.65,2601.5),C.cream)
	K.doorframe(vestibule,CF(9,0,2601.12),9,10.3)
	part(vestibule,"VestibuleReturnWall",V(.65,10.6,5.7),CF(4.5,5.3,2604.35),C.cream)
	part(vestibule,"LowVestibuleCeiling",V(42,.45,13.35),CF(0,10.825,2608.325),C.ceiling)
	skirting(vestibule,CF(-8.25,0,2601.12),25.5)
	skirting(vestibule,CF(17.25,0,2601.12),7.5)
	skirting(vestibule,CF(4.88,0,2604.35)*yaw(90),5.7)
	part(vestibule,"VestibuleCeilingCornice",V(42,.3,.32),CF(0,10.45,2602.04),C.white)
	vestibule:SetAttribute("ClearDoorWidth",9)
	vestibule:SetAttribute("RearTurnDepth",7.475)
	vestibule:SetAttribute("NoGameplayGate",true)

	-- Direction-matched images keep gravity drips downward. Rotate within
	-- the carrier's wall plane; Front (-local Z) always faces into the room.
	-- The image alpha supplies the painted contour: the carrier is invisible.
	local arrows=model("PaintedExitDirections",finalHouse)
	local function paintedArrow(name,position,normal,width,height,direction,canonicalLeft)
		local face=CFrame.lookAt(position,position+normal)
		-- Front-face bitmap right is the negative object-local X direction.
		local imageDirection=canonicalLeft and direction or -direction
		local angle=math.atan2(imageDirection:Dot(face.UpVector),imageDirection:Dot(face.RightVector))
		local surface=part(arrows,name,V(width,height,.015),face*CFrame.Angles(0,0,angle),C.white,Enum.Material.SmoothPlastic,false)
		surface.Transparency=1;surface.CanQuery=false;surface.CanTouch=false;surface.CastShadow=false
		surface:SetAttribute("Level5ExitArrow",true)
		surface:SetAttribute("AlphaBackground",true)
		surface:SetAttribute("CanonicalImageDirection",canonicalLeft and "Left" or "Right")
		surface:SetAttribute("LocalRouteDirection",direction.Unit)
		local asset=canonicalLeft and config.ExitArrowLeftTexture or config.ExitArrowTexture
		if asset and asset~="" then
			local decal=Instance.new("Decal");decal.Name="PaintedExitArrow"
			decal.Texture=tostring(asset);decal.Face=Enum.NormalId.Front
			decal.Color3=Color3.new(1,1,1);decal.Transparency=0;decal.Parent=surface
		else
			surface:SetAttribute("MissingExitArrowTexture",true)
		end
		return surface
	end
	paintedArrow("FirstRightTurnArrow",V(0,6,2601.15),V(0,0,-1),6.2,6.2/1.5,V(1,0,0),true)
	paintedArrow("VestibuleForwardArrow",V(4.855,5.7,2604.35),V(1,0,0),4.8,3.2,V(0,0,1),true)
	paintedArrow("RearLeftTurnArrow",V(8.6,5.7,2614.645),V(0,0,-1),6.2,6.2/1.5,V(-1,0,0))

	local chute=model("NarrowDescent",H)
	local chuteStart,bend,chuteEnd=V(0,0,2615),V(0,-11,2647),V(0,-29,2670)
	local function chuteSegment(a,b,dark)
		local length=(b-a).Magnitude
		local frame=CFrame.lookAt((a+b)/2,b)
		local black=Color3.fromRGB(3,3,3)
		part(chute,"SmoothSlopingFloor",V(7.2,.85,length+.65),frame*CF(0,-.43,0),dark and black or C.carpet,Enum.Material.SmoothPlastic)
		for _,s in ipairs({-1,1}) do part(chute,"CloseChuteWall",V(.7,8.7,length+.65),frame*CF(s*3.95,4.3,0),dark and black or C.cream) end
		part(chute,"LowChuteCeiling",V(8.6,.65,length+.65),frame*CF(0,8.7,0),dark and black or C.ceiling)
		if not dark then part(chute,"LastFluorescent",V(3,.12,1.7),frame*CF(0,8.3,length*.25),Color3.fromRGB(185,191,154),Enum.Material.Neon,false) end
		return frame
	end
	local firstFrame=chuteSegment(chuteStart,bend,false)
	local secondFrame=chuteSegment(bend,chuteEnd,true)

	-- Differently pitched boxes leave a triangular opening above their shared
	-- floor bend. Roof bridges and external side collars close the real shell;
	-- no dark screen, blocker or trigger is placed across the walking passage.
	local function roofClosure(name,a,b,color)
		local midpoint=(a+b)/2
		part(chute,name,V(8.7,.7,(b-a).Magnitude+.9),CFrame.lookAt(midpoint,b),color)
	end
	roofClosure("EntranceRoofClosure",V(0,10.75,2614.7),chuteStart+firstFrame.UpVector*8.7,C.ceiling)
	for _,s in ipairs({-1,1}) do
		part(chute,"EntranceSideCollar",V(.7,10.95,4.15),CF(s*3.95,5.325,2616.375),C.cream)
	end
	roofClosure("BendRoofClosure",bend+firstFrame.UpVector*8.7,bend+secondFrame.UpVector*8.7,Color3.fromRGB(3,3,3))
	for _,s in ipairs({-1,1}) do
		part(chute,"BendSideCollar",V(.7,11.5,8),CF(s*3.95,bend.Y+4,bend.Z+2.5),Color3.fromRGB(3,3,3))
	end

	-- One final painted direction follows the actual slope on the inside wall.
	local descentDirection=(bend-chuteStart).Unit
	local arrowCenter=chuteStart+descentDirection*6+firstFrame.UpVector*4.9+V(-3.585,0,0)
	paintedArrow("DownTheSlopeArrow",arrowCenter,V(1,0,0),5.4,3.6,descentDirection,true)
	floor(chute,"DarkArrivalFloor",0,-29,2674.5,8,9,Color3.fromRGB(2,2,2))
	part(chute,"DarkArrivalCeiling",V(8,.7,9),CF(0,-20.3,2674.5),Color3.fromRGB(2,2,2))
	for _,s in ipairs({-1,1}) do part(chute,"DarkArrivalSide",V(.7,9,9),CF(s*4,-24.5,2674.5),Color3.fromRGB(2,2,2)) end
	part(chute,"DarkArrivalEnd",V(8,9,.7),CF(0,-24.5,2679),Color3.fromRGB(2,2,2))
	chute:SetAttribute("GeometryOnly_NoSlideOrCompletion",true)
	chute:SetAttribute("SuggestedSlideStartFraction",.7)
	chute:SetAttribute("ArchitecturalDarkEnding",true)
	chute:SetAttribute("PitchSeamsClosed",true)
	camera("LastHouseQuietCourt",V(-12,6,2558),V(4,8,2591))
	camera("LastHousePuzzleRoom",V(0,6,2590),V(8,5.8,2602))
	camera("LastHouseVestibule",V(9,5,2604),V(0,5,2614))
	camera("LastHouseDescent",V(0,5,2613),V(0,-10,2646))
	camera("LastHouseDarkArrival",V(0,-18,2662),V(0,-25,2676))
	point(0,3,2462); point(0,3,2515); point(0,3,2558); point(0,3,2581); point(0,3,2597.5)
	point(9,3,2597.5); point(9,3,2610.9); point(0,3,2610.9); point(0,3,2613)
	point(0,-8,2647); point(0,-26,2674)
	return {PreviewCameras=cameras,Waypoints=waypoints,Zones=zones,FinalHouse=finalHouse,ChuteStart=chuteStart,ChuteEnd=chuteEnd}
end

return Districts
