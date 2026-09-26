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

	-- F: continuous domestic walls around a real multi-storey carpeted atrium.
	-- Entry is an upper landing, not a broad ground court. The grade route is
	-- deliberately broken; ordinary stairs and crossings reconnect its pieces.
	local F=zone("F_BayWindowCanyon",V(-250,-42,1596),V(250,84,2076),"Continuous cream plaster dwellings, narrow deep void, carpet ledges and staggered crossings.")
	F:SetAttribute("CourtVersion","2026-09-26.reference-atrium.1")
	F:SetAttribute("PlayableFloorHeights","-42,-28,-14,0,14,28")
	F:SetAttribute("EntryLedgeY",0)
	local pitBounds={Min=V(-50,-42,1668),Max=V(50,-28,1968),Space="local"}
	local voidBounds={Min=V(-28,-42,1668),Max=V(28,0,1968),Space="local"}
	F:SetAttribute("PitMin",pitBounds.Min);F:SetAttribute("PitMax",pitBounds.Max)
	F:SetAttribute("VoidMin",voidBounds.Min);F:SetAttribute("VoidMax",voidBounds.Max)
	local cream=Color3.fromRGB(244,240,223)
	local function plaster(p) return K.material(p,"Plaster",cream) end
	local function plasterPart(into,name,size,frame)
		return plaster(part(into,name,size,frame,cream,Enum.Material.Plaster))
	end
	local function dwelling(into,name,frame,w,d,h,options)
		options=options or {}
		local home=house(into,name,frame,w,d,h,C.pale,nil,options)
		-- Reuse the standard real doors, panes and room metadata, but make this
		-- district solid domestic plaster rather than clapboard/pastel cottages.
		for _,p in ipairs(home:GetDescendants()) do
			if p:IsA("BasePart") and (p:GetAttribute("Level5SurfaceMaterial")=="Siding" or p.Material==Enum.Material.Plaster) then plaster(p) end
		end
		home:SetAttribute("HousePuzzleCandidate",false)
		return home
	end
	local function foundation(name,x,z,w,d)
		plasterPart(F,name,V(w,126,d),CF(x,21,z)) -- -42..84, opaque backing
	end
	floor(F,"AtriumArrivalCarpet",0,0,1632,500,72,C.carpet) -- 1596..1668
	floor(F,"AtriumDepartureCarpet",0,0,2022,500,108,C.carpet) -- 1968..2076
	-- The old outer courts become actual building mass. There is no concealed
	-- grade bypass behind the front rooms or under the gate foundations.
	for _,side in ipairs({-1,1}) do
		foundation("ArrivalResidentialMass",side*165,1643,170,50) -- 1618..1668
		foundation("DepartureResidentialMass",side*165,2002,170,68) -- 1968..2036
	end
	local ledges={
		[-28]={[-1]={{1668,1678},{1710,1968}},[1]={{1668,1968}}},
		[-14]={[-1]={{1788,1856}},[1]={{1766,1830}}},
		[0]={[-1]={{1668,1756},{1964,1968}},[1]={{1668,1724},{1862,1880}}},
		[14]={[-1]={{1668,1932}},[1]={{1668,1880},{1912,1968}}},
		[28]={[-1]={{1668,1840},{1872,1968}},[1]={{1668,1730},{1762,1968}}},
	}
	local bridgeGaps={
		[-28]={[-1]={{1712,1724}},[1]={{1712,1724}}},
		[-14]={[-1]={{1804,1816}},[1]={{1804,1816}}},
		[14]={[-1]={{1692,1704},{1910,1926}},[1]={{1692,1704},{1922,1938}}},
		[28]={[-1]={{1886,1902}},[1]={{1874,1890}}},
	}
	local function railInterval(side,y,a,b,gaps)
		local cuts={}
		for _,g in ipairs(gaps or {}) do if g[2]>a and g[1]<b then table.insert(cuts,{math.max(a,g[1]),math.min(b,g[2])}) end end
		table.sort(cuts,function(x,y) return x[1]<y[1] end)
		K.edgeRail(F,side*28,y,a,b,cuts)
	end
	for y,sides in pairs(ledges) do for _,side in ipairs({-1,1}) do
		for i,span in ipairs(sides[side]) do
			floor(F,"CarpetLedge_"..side.."_"..y.."_"..i,side*39,y,(span[1]+span[2])/2,22,span[2]-span[1],C.carpet)
			plasterPart(F,"CarpetLedgePlasterSoffit",V(22,.22,span[2]-span[1]),CF(side*39,y-1.26,(span[1]+span[2])/2))
			railInterval(side,y,span[1],span[2],bridgeGaps[y] and bridgeGaps[y][side])
		end
	end end
	-- Exposed dead ends receive rails; stair mouths and bridge ends stay clear.
	for _,cap in ipairs({{1,0,1724},{-1,-14,1856},{-1,-28,1668},{1,-28,1668},{-1,-28,1968},{1,-28,1968},{-1,14,1668},{1,14,1668},{1,14,1968},{-1,28,1668},{1,28,1668},{-1,28,1968},{1,28,1968}}) do rail(F,CF(cap[1]*39,cap[2],cap[3]),22) end
	-- At grade the unconnected east ledge must not offer a walk around the void.
	-- Rail the arrival rim between the two genuine side entrances.
	rail(F,CF(0,0,1668),56)
	-- The rear rim has one west stair landing. The other side is protected.
	rail(F,CF(11,0,1968),78)
	floor(F,"PitFloor",0,-42,1818,100,300,C.carpet)
	for _,side in ipairs({-1,1}) do plasterPart(F,"PitSideWall",V(1.4,14,300),CF(side*50.7,-35,1818)) end
	for _,z in ipairs({1667.3,1968.7}) do plasterPart(F,"PitEndWall",V(102.8,42,1.4),CF(0,-21,z)) end
	-- Close beneath the arrival/departure galleries, not just at eye height.
	plasterPart(F,"ArrivalPitFoundation",V(500,42,72),CF(0,-21,1632))
	plasterPart(F,"DeparturePitFoundation",V(500,42,108),CF(0,-21,2022))

	local function onLedge(side,y,z)
		local bands=ledges[y] and ledges[y][side]
		if not bands then return false end
		for _,span in ipairs(bands) do if z>=span[1]+4 and z<=span[2]-4 then return true end end
		return false
	end
	local stairFootprints={
		{side=-1,y=-28,a=1678,b=1710},{side=1,y=-28,a=1734,b=1766},
		{side=-1,y=0,a=1756,b=1788},{side=1,y=-14,a=1830,b=1862},
		{side=1,y=0,a=1880,b=1912},{side=-1,y=14,a=1932,b=1964},
		{side=-1,y=14,a=1840,b=1872},{side=1,y=14,a=1730,b=1762},
	}
	local function roomAccessible(side,y,z)
		if not onLedge(side,y,z) then return false end
		for _,s in ipairs(stairFootprints) do if side==s.side and y==s.y and z>s.a-3 and z<s.b+3 then return false end end
		return true
	end
	local clueHome
	for _,side in ipairs({-1,1}) do
		local wall=model(side<0 and "WestContinuousDwellings" or "EastContinuousDwellings",F)
		for bayIndex=1,10 do
			local z=1653+bayIndex*30 -- 1683..1953, contiguous thirty-stud bays
			local frontage=(bayIndex==4 or bayIndex==8) and 50 or 46
			local massStart=frontage+25.9
			foundation("OpaqueResidentialBacking",side*(massStart+250)/2,z,250-massStart,30)
			for _,y in ipairs({-28,-14,0,14,28,42,56,70}) do
				local open=roomAccessible(side,y,z)
				local frame=CF(side*frontage,y,z)*yaw(side*90)
				local cutaway=(side<0 and bayIndex==4 and y==42) or (side>0 and bayIndex==7 and y==56)
				local furniture=y==0 and ((side<0 and bayIndex==1 and 7) or (side<0 and bayIndex==3 and 8) or (side>0 and bayIndex==1 and 6)) or nil
				local home=dwelling(wall,"PlasterDwelling_"..bayIndex.."_"..y,frame,30,26,13.8,{open=open,cutaway=cutaway,furniture=furniture,completeHome=furniture~=nil})
				if cutaway then
					home:SetAttribute("UncannyCutaway",true)
					part(home,"ClosedPanelDoor",V(5.4,10.3,.32),frame*CF(0,5.15,.05),C.white,Enum.Material.Wood)
				end
				if side<0 and bayIndex==3 and y==0 then
					clueHome=home;home.Name="TelevisionClueResidence";home:SetAttribute("HousePuzzleCandidate",true)
				end
				if side<0 and bayIndex==2 and y==0 then K.registerWatcher(home,"NearGroundWindow",F.Name) end
				if side>0 and bayIndex==9 and y==14 then K.registerWatcher(home,"MiddleCourtWindow",F.Name) end
				if side<0 and bayIndex==9 and y==28 then K.registerWatcher(home,"FarUpperWindow",F.Name) end
				-- Irregular little projections above the walkable floors interrupt
				-- the otherwise continuous domestic wall, like the reference.
				if y>=42 and (bayIndex+(side<0 and 1 or 3)+y/14)%4==0 then
					floor(wall,"ProjectingDomesticBalcony",0,0,-3.5,20,7,C.carpet,frame)
					rail(wall,frame*CF(0,0,-7),20)
					for _,s in ipairs({-1,1}) do rail(wall,frame*CF(s*10,0,-3.5)*yaw(90),7) end
					plasterPart(wall,"BalconyMouldedUnderside",V(21,.65,7.8),frame*CF(0,-1,-3.5))
				end
			end
		end
	end
	assert(clueHome and clueHome:GetAttribute("Enterable"),"F requires an accessible ground-level television clue residence")

	local function flight(name,side,y,z,rise,run)
		local frame=CF(side*37,y,z)
		local m=stairs(F,name,frame,12,rise,run,28,C.carpet,true)
		local a,b=V(side*37,y,z),V(side*37,y+rise,z+run)
		local align=CFrame.lookAt((a+b)/2,b)
		plasterPart(m,"SolidPlasterStairSoffit",V(12,1,(b-a).Magnitude+.2),align*CF(0,-.9,0))
		return m
	end
	flight("MainDescentToLowerGallery",-1,0,1756,-14,32)
	flight("MainRiseToMiddleLanding",1,-14,1830,14,32)
	flight("MainRiseToUpperCrossing",1,0,1880,14,32)
	flight("MainDescentToExitLanding",-1,14,1932,-14,32)
	flight("PitRecoveryFirstFlight",-1,-42,1678,14,32)
	flight("PitRecoverySecondFlight",1,-28,1734,14,32)
	flight("OptionalWestUpperFlight",-1,14,1840,14,32)
	flight("OptionalEastUpperFlight",1,14,1730,14,32)
	local function crossing(name,leftZ,rightZ,y)
		local a,b=V(-37,y,leftZ),V(37,y,rightZ)
		local dir=b-a;local frame=CF((a+b)/2)*yaw(-math.deg(math.atan2(dir.Z,dir.X)))
		local m=model(name,F)
		floor(m,"CrossingCarpet",0,0,0,dir.Magnitude,12,C.carpet,frame)
		plasterPart(m,"CrossingPlasterSoffit",V(dir.Magnitude,.22,12),frame*CF(0,-1.26,0))
		-- Rail the void-spanning centre only; full-width rails would cut into the
		-- receiving ledges and prevent turning onto or off the crossing.
		for _,z in ipairs({-6,6}) do rail(m,frame*CF(0,0,z),56) end
		plasterPart(m,"WhiteBridgeFascia",V(dir.Magnitude,1.6,.45),frame*CF(0,-.7,-6.1))
		plasterPart(m,"WhiteBridgeFascia",V(dir.Magnitude,1.6,.45),frame*CF(0,-.7,6.1))
	end
	crossing("LowerRecoveryCrossing",1718,1718,-28)
	crossing("MainLowerCrossing",1810,1810,-14)
	crossing("NorthUpperReturnCrossing",1698,1698,14)
	crossing("SkewedMainUpperCrossing",1918,1930,14)
	crossing("SkewedHighGalleryCrossing",1894,1882,28)

	-- Solid flat-roof domestic entrance/exit blocks compress the broad envelope
	-- into the ledges. Neither introduces a detached gabled village silhouette.
	for level=0,3 do dwelling(F,"ArrivalDomesticBlock_"..level,CF(0,level*14,1624),40,26,13.8,{open=level==0}) end
	for level=0,2 do dwelling(F,"DepartureDomesticBlock_"..level,CF(0,level*14,2000),48,26,13.8,{open=level==0,furniture=level==0 and 2 or nil}) end

	local route={
		V(-120,3,1608),V(-43,3,1608),V(-37,3,1658),V(-37,3,1683),V(-37,3,1713),V(-37,3,1743),
		V(-37,3,1756),V(-37,-4,1772),V(-37,-11,1788),V(-37,-11,1810),V(37,-11,1810),
		V(37,-11,1830),V(37,-4,1846),V(37,3,1862),V(37,3,1880),V(37,10,1896),V(37,17,1912),
		V(37,17,1930),V(0,17,1924),V(-37,17,1918),V(-37,17,1932),V(-37,10,1948),V(-37,3,1964),
		V(-37,3,1988),V(37,3,1988),V(37,3,2048),V(178,3,2048),V(178,3,2064),
	}
	local rescue={V(0,-39,1818),V(0,-39,1673),V(-37,-39,1673),V(-37,-39,1678),V(-37,-32,1694),V(-37,-25,1710),V(-37,-25,1718),V(37,-25,1718),V(37,-25,1734),V(37,-18,1750),V(37,-11,1766),V(37,-11,1810)}
	local clueRoute={V(-37,3,1743),V(-48,3,1743),V(-66,3,1743)}
	camera("ReferenceAtriumArrival",V(-37,6,1661),V(24,-6,1810))
	camera("ReferenceAtriumVerticalVoid",V(-36,6,1748),V(38,-13,1872))
	camera("ReferenceAtriumLowerCrossing",V(-36,-8,1808),V(42,32,1910))
	camera("ReferenceAtriumUpperSkewBridge",V(31,20,1930),V(-44,35,1770))
	camera("ReferenceAtriumHighGallery",V(-37,34,1905),V(34,13,1730))
	camera("ReferenceAtriumRecoveryFloor",V(0,-36,1828),V(-34,20,1690))
	for _,p in ipairs(route) do table.insert(waypoints,p) end

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
	return {PreviewCameras=cameras,Waypoints=waypoints,Zones=zones,FinalHouse=finalHouse,ChuteStart=chuteStart,ChuteEnd=chuteEnd,FRouteWaypoints=route,FRescueRouteWaypoints=rescue,FClueRouteWaypoints=clueRoute,FAtriumPitBounds=pitBounds,FAtriumVoidBounds=voidBounds}
end

return Districts
