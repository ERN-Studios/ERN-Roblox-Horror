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
	F:SetAttribute("CourtVersion","2026-09-27.reference-07-08.1")
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
	-- These are two different reference compositions in one traversable atrium.
	-- Only the unreachable upper apartment shells are replaced; the real lower
	-- homes, ledges, pit, crossings and recovery flights keep their coordinates.
	local cutawaySection=model("S07_StairCutaway",F)
	local walkwaySection=model("S08_UpperAtriumWalkway",F)
	cutawaySection:SetAttribute("ReferenceSection",7)
	walkwaySection:SetAttribute("ReferenceSection",8)
	-- Reference 07 has an open apartment-room stack beside the torn stair core.
	-- These upper storeys are scenic; every new part is non-colliding/non-querying.
	local function scenic(into,name,size,frame,color,material)
		local p=part(into,name,size,frame,color or cream,material or Enum.Material.Plaster,false)
		p.CanQuery=false
		return p
	end
	local function panelDoor(into,frame)
		scenic(into,"CutawayWhitePanelDoor",V(4.9,9.3,.2),frame*CF(0,4.65,-.25),C.white,Enum.Material.Wood)
		for _,sgn in ipairs({-1,1}) do
			scenic(into,"CutawayDoorJamb",V(.34,9.65,.44),frame*CF(sgn*2.58,4.83,-.48),C.white,Enum.Material.Wood)
			for _,yy in ipairs({2.0,4.55,7.15}) do
				scenic(into,"CutawayRaisedDoorPanel",V(1.65,yy==4.55 and 2.15 or 1.25,.12),frame*CF(sgn*1.05,yy,-.40),Color3.fromRGB(226,225,216),Enum.Material.Wood)
			end
		end
		scenic(into,"CutawayDoorHead",V(5.5,.4,.44),frame*CF(0,9.46,-.48),C.white,Enum.Material.Wood)
		local knob=scenic(into,"CutawayBrassKnob",V(.3,.3,.3),frame*CF(1.9,4.65,-.50),Color3.fromRGB(146,125,76),Enum.Material.Metal)
		knob.Shape=Enum.PartType.Ball
	end
	local function openApartmentRoom(into,frame)
		-- A full-depth room, not a dark window decal. The existing solid backing
		-- begins just behind this room, so it cannot expose the district shell.
		scenic(into,"ExposedRoomCarpet",V(29.25,.55,25.4),frame*CF(0,-.28,12.7),Color3.fromRGB(181,168,151),Enum.Material.Fabric)
		scenic(into,"ExposedRoomCeiling",V(29.25,.45,25.4),frame*CF(0,13.58,12.7),Color3.fromRGB(230,224,210))
		for _,sgn in ipairs({-1,1}) do
			scenic(into,"ExposedRoomSideWall",V(.72,13.35,25.5),frame*CF(sgn*14.65,6.68,12.75))
			scenic(into,"OpenRoomWhiteJamb",V(.36,12.5,.46),frame*CF(sgn*14.28,6.55,-.3),C.white)
		end
		scenic(into,"ExposedRoomBackWall",V(29.2,13.35,.7),frame*CF(0,6.68,25.55))
		scenic(into,"OpenRoomWhiteHeader",V(29.2,.42,.46),frame*CF(0,13.25,-.3),C.white)
		scenic(into,"BrokenFloorSlabLip",V(29.2,.45,1.15),frame*CF(0,-.2,-.55),Color3.fromRGB(214,205,187))
		panelDoor(into,frame*CF(-5.2,0,25.08))
		local lamp=scenic(into,"OpenRoomWarmSconce",V(.42,.75,.26),frame*CF(9.8,8.1,25.01),Color3.fromRGB(244,199,123),Enum.Material.Neon)
		lamp.CastShadow=false
	end
	local function upperApartmentFront(into,frame,cutaway,level,side,bayIndex)
		if cutaway and side<0 and bayIndex==3 then
			openApartmentRoom(into,frame)
			return
		end
		local opening=cutaway and side<0 and bayIndex==4
		if opening then
			for _,sgn in ipairs({-1,1}) do
				plasterPart(into,"TornApartmentPier",V(10.1,13.8,.8),frame*CF(sgn*9.95,6.9,0))
				plasterPart(into,"ContinuousCutawayReturn",V(.7,13.6,1.8),frame*CF(sgn*4.5,6.8,-.18))
			end
			plasterPart(into,"TornApartmentHeader",V(30,1,.9),frame*CF(0,13.3,0))
			-- The broken floor ends project into the cut, with exposed substrate;
			-- the central opening stays clear for the visible stair flight.
			for _,sgn in ipairs({-1,1}) do
				scenic(into,"BrokenFloorSlabStub",V(4.1,.42,3.1),frame*CF(sgn*7.0,.05,-1.5),Color3.fromRGB(219,210,191))
				scenic(into,"BrokenFloorCarpetEdge",V(3.8,.10,2.75),frame*CF(sgn*7.0,.31,-1.5),Color3.fromRGB(172,158,142),Enum.Material.Fabric)
				scenic(into,"SingleBrokenPlasterEdge",V(.72,2.8,1.65),
					frame*CF(sgn*4.8,6.8,-.7),Color3.fromRGB(229,219,198))
			end
			part(into,"RecessedStairwellShadow",V(8.6,11.2,.15),frame*CF(0,5.6,6.8),Color3.fromRGB(68,62,57),Enum.Material.SmoothPlastic,false)
			panelDoor(into,frame*CF(9.9,0,-.45))
			local lamp=scenic(into,"CutawayWarmSconce",V(.38,.7,.25),frame*CF(13.1,8.6,-.52),Color3.fromRGB(244,199,123),Enum.Material.Neon)
			lamp.CastShadow=false
			local stairFrame=frame*CF(0,.5,1.8)
			local stair=stairs(into,"ExposedCarpetHalfFlight_"..level,stairFrame,7,5.5,7.5,8,Color3.fromRGB(163,145,130),true)
			for _,p in ipairs(stair:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false;p.CanQuery=false end end
			local a=stairFrame:PointToWorldSpace(V(0,0,0))
			local b=stairFrame:PointToWorldSpace(V(0,5.5,7.5))
			local slant=CFrame.lookAt((a+b)/2,b)
			for _,sgn in ipairs({-1,1}) do
				scenic(into,"StairFlightStringer",V(.35,.55,(b-a).Magnitude+.3),slant*CF(sgn*3.45,-.7,0),Color3.fromRGB(222,213,192))
				for i=1,7 do
					local t=i/8
					local post=stairFrame*CF(sgn*3.33,1.6+5.5*t,7.5*t)
					scenic(into,"TurnedStairBaluster",V(.14,2.65,.14),post,C.white)
					local bead=scenic(into,"BalusterTurning",V(.29,.27,.29),post*CF(0,.25,0),C.white)
					bead.Shape=Enum.PartType.Ball
				end
				for _,endpoint in ipairs({{0,0},{5.5,7.5}}) do
					local post=stairFrame*CF(sgn*3.33,endpoint[1]+1.7,endpoint[2])
					scenic(into,"SubstantialWhiteNewel",V(.4,3.4,.4),post,C.white)
					local cap=scenic(into,"NewelBallCap",V(.55,.55,.55),post*CF(0,1.9,0),C.white)
					cap.Shape=Enum.PartType.Ball
				end
			end
			return
		end
		plasterPart(into,"ApartmentFrontPlane",V(30,13.8,.75),frame*CF(0,6.9,0))
		plasterPart(into,"StoreyCornice",V(30.6,.42,1.1),frame*CF(0,13.6,-.26))
		local windowX=cutaway and 6 or (bayIndex%2==0 and -6.8 or 6.8)
		window(into,frame*CF(windowX,7.4,-.48),cutaway and 7.2 or 8,7.2,false,true)
		if cutaway then
			part(into,"WhitePanelDoor",V(4.8,9.4,.22),frame*CF(-7,4.7,-.52),C.white,Enum.Material.Wood,false)
			for _,dy in ipairs({2.2,5,7.8}) do part(into,"DoorRaisedPanel",V(3.5,1.35,.13),frame*CF(-7,dy,-.69),C.pale,Enum.Material.Wood,false) end
			part(into,"DoorHandle",V(.25,.25,.35),frame*CF(-5.45,4.25,-.78),Color3.fromRGB(135,119,84),Enum.Material.Metal,false)
		else
			-- Reference 08 has modest projecting white-metal balconies beside
			-- dark apartment windows, not the torn rooms of reference 07.
			if level<=56 and bayIndex%2==0 then
				floor(into,"TinyApartmentBalcony",-8,0,-2.8,8,5,C.carpet,frame)
				rail(into,frame*CF(-8,0,-5.5),8)
				for _,sgn in ipairs({-1,1}) do rail(into,frame*CF(-8+sgn*4,0,-2.8)*yaw(90),5) end
			end
			local lamp=part(into,"WarmDoorSconce",V(.45,.8,.32),frame*CF(-8.5,8.8,-.55),Color3.fromRGB(247,214,151),Enum.Material.Neon,false)
			lamp.CastShadow=false
		end
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
				-- Bay 3 supplies the open stacked rooms visible beside the torn
				-- stair bay. Its y=0 television clue home remains unchanged.
				local cutaway=side<0 and (bayIndex==3 or bayIndex==4) and (y==14 or y==28)
				local furniture=y==0 and ((side<0 and bayIndex==1 and 7) or (side<0 and bayIndex==3 and 8) or (side>0 and bayIndex==1 and 6)) or nil
				if y>=42 then
					upperApartmentFront(z<1830 and cutawaySection or walkwaySection,frame,z<1830,y,side,bayIndex)
				else
					local home=dwelling(wall,"PlasterDwelling_"..bayIndex.."_"..y,frame,30,26,13.8,{open=open,cutaway=cutaway,furniture=furniture~=nil})
					if cutaway then
						home:SetAttribute("UncannyCutaway",true)
						home:SetAttribute("ReferenceSection",7)
						-- The original house retains its support, side walls, back wall
						-- and doorway to the real ledge. Its rear panel door is scenic.
						panelDoor(home,frame*CF(bayIndex==3 and -5.2 or 7.5,0,25.1))
					end
					if side<0 and bayIndex==3 and y==0 then
						clueHome=home;home.Name="TelevisionClueResidence";home:SetAttribute("HousePuzzleCandidate",true)
					end
					if side<0 and bayIndex==2 and y==0 then K.registerWatcher(home,"NearGroundWindow",F.Name) end
					if side>0 and bayIndex==9 and y==14 then K.registerWatcher(home,"MiddleCourtWindow",F.Name) end
					if side<0 and bayIndex==9 and y==28 then K.registerWatcher(home,"FarUpperWindow",F.Name) end
				end
			end
		end
	end
	assert(clueHome and clueHome:GetAttribute("Enterable"),"F requires an accessible ground-level television clue residence")
	-- The torn townhouse rises in the open atrium in front of the gallery.
	-- It is wholly non-colliding; the ledges and recovery stairs remain the path.
	local exposedHouse=model("S07_FullHeightExposedStairHouse",cutawaySection)
	exposedHouse:SetAttribute("ReferenceSection",7)
	exposedHouse:SetAttribute("ClosedScenicProjection",true)
	local exposedFrame=CF(-8,0,1773)*yaw(-90)
	-- Keep a legible four-storey cut line and continuous white left trim.
	-- Scattered detached plaster chips previously obscured the switchback.
	scenic(exposedHouse,"ContinuousWhiteCutawayTrim",V(.65,56,.7),exposedFrame*CF(-16.35,28,-.6),C.white)
	for storey=0,4 do
		local y=storey*14
		-- A rear landing strip supports the room illusion but leaves the
		-- front half of each stair flight visible from the opposite gallery.
		local slab=scenic(exposedHouse,"BrokenOpenFloorSlab",V(33,.58,8),exposedFrame*CF(0,y-.29,17.5),Color3.fromRGB(209,197,177),Enum.Material.Plaster)
		if storey<4 then
			local backWall=scenic(exposedHouse,"OpenRoomBackWall",V(33,13.7,.65),exposedFrame*CF(0,y+6.85,21.7),Color3.fromRGB(215,203,183))
			local roomFill=Instance.new("SurfaceLight")
			roomFill.Face=Enum.NormalId.Front;roomFill.Brightness=.42;roomFill.Range=18;roomFill.Angle=140;roomFill.Shadows=false;roomFill.Parent=backWall
			scenic(exposedHouse,"OpenRoomLeftReturn",V(.68,13.7,22),exposedFrame*CF(-16.15,y+6.85,11),Color3.fromRGB(217,204,183))
			scenic(exposedHouse,"BrokenRightEdgePier",V(1.7,13.7,2.5),exposedFrame*CF(15.5,y+6.85,-.45),Color3.fromRGB(226,211,190))
			scenic(exposedHouse,"ExposedWhiteFloorLip",V(32.5,.4,.65),exposedFrame*CF(0,y+.12,-.55),C.white)
			panelDoor(exposedHouse,exposedFrame*CF(-9,y,21.32))
			local strip=scenic(exposedHouse,"CarpetedLanding",V(12,.08,7),exposedFrame*CF(-5,y+.08,17.5),Color3.fromRGB(174,159,144),Enum.Material.Fabric)
			strip.MaterialVariant=""
			for chip=0,1 do
				scenic(exposedHouse,"UnevenTornPlaster",V(.55+(chip%2)*.25,2.5,1.8+(chip%3)*.37),
					exposedFrame*CF(14.35,y+1.5+chip*3.2,-.7),Color3.fromRGB(234,220,197))
			end
		end
	end
	for level=0,3 do
		local y=level*14
		local direction=level%2==0 and 1 or -1
		local landing=scenic(exposedHouse,"SwitchbackCarpetLanding",V(8,.1,9),
			exposedFrame*CF(direction*12,y+13.98,10),Color3.fromRGB(171,154,138),Enum.Material.Fabric)
		landing.MaterialVariant=""
		-- The stair climbs across the exposed face, so the diagonal reads
		-- clearly from the opposite gallery instead of collapsing into a ladder.
		for step=0,8 do
			local x=direction*(-13+step*3.25)
			local tread=scenic(exposedHouse,"VisibleDiagonalCarpetTread",V(3,.43,8.5),
				exposedFrame*CF(x,y+.25+step*1.55,10),Color3.fromRGB(170,153,139),Enum.Material.Fabric)
			tread.MaterialVariant=""
		end
		for _,frontZ in ipairs({5.5,14.5}) do
			local a=exposedFrame:PointToWorldSpace(V(direction*-13.5,y+2.6,frontZ))
			local b=exposedFrame:PointToWorldSpace(V(direction*13.5,y+15,frontZ))
			scenic(exposedHouse,"DiagonalWhiteStairRail",V(.24,.24,(b-a).Magnitude),CFrame.lookAt((a+b)/2,b),C.white,Enum.Material.Wood)
			for spindle=0,6 do
				local t=spindle/6
				scenic(exposedHouse,"WhiteTurnedStairBaluster",V(.2,2.9,.2),
					exposedFrame*CF(direction*(-13.5+27*t),y+1.2+12.4*t,frontZ),C.white,Enum.Material.Wood)
			end
		end
	end

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
	camera("S07_StairCutawayReferenceView",V(30,4,1773),V(-24,48,1773))
	camera("S08_UpperAtriumWalkwayReferenceView",V(-37,31,1905),V(35,20,1950))
	for _,p in ipairs(route) do table.insert(waypoints,p) end

	-- G: the wide subdivision has habitable terraces below two impossible pairs
	-- of tall stacks. Tilted domestic volumes rest on piers outside enterable homes.
	local G=zone("G_TiltedSubdivision",V(-240,0,2076),V(240,180,2456),"Carpet lawns, two playable terraces and supported tilted houses between towering domestic stacks.")
	local gLawn=floor(G,"SubdivisionGreenCarpet",0,0,2266,480,380,C.green)
	gLawn.Color=Color3.fromRGB(24,42,25);gLawn.MaterialVariant=""
	texture(gLawn,"rbxassetid://108216315862080",Enum.NormalId.Top,8)
	-- The photographed subdivision and bridge canyon share one uninterrupted
	-- dark lawn. The broad grass floor already supports every central waypoint.
	local slopeSection=model("S05_SlopedHouseAnomaly",G)
	local gabledSection=model("S06_GabledFacadeLawn",G)
	local skybridgeSection=model("S09_SkybridgeCanyon",G)
	slopeSection:SetAttribute("ReferenceSection",5)
	gabledSection:SetAttribute("ReferenceSection",6)
	skybridgeSection:SetAttribute("ReferenceSection",9)
	local paleTower=Color3.fromRGB(222,210,184)
	local darkPane=Color3.fromRGB(24,26,22)
	local function decorativeRail(into,a,b,y)
		local length=(b-a).Magnitude
		local frame=CFrame.lookAt((a+b)/2,b)
		part(into,"ContinuousWhiteRail",V(.24,.22,length),frame*CF(0,y+3.2,0),C.white,nil,false)
		for i=0,math.ceil(length/12) do
			local t=i/math.ceil(length/12)
			part(into,"BalconyRailPost",V(.2,3,.2),CF(a:Lerp(b,t)+V(0,y+1.6,0)),C.white,nil,false)
		end
	end
	local function roundedDeck(into,name,center,radius,y,zDirection)
		local deck=part(into,name,V(1,radius*2,radius*2),CF(center.X,y-.5,center.Z)*CFrame.Angles(0,0,math.pi/2),C.pale,Enum.Material.Plaster,false)
		deck.Shape=Enum.PartType.Cylinder
		local previous
		for j=0,8 do
			local angle=math.pi*j/8
			local p=V(center.X+radius*math.cos(angle),0,center.Z+(zDirection or -1)*radius*math.sin(angle))
			if previous then decorativeRail(into,previous,p,y) end
			previous=p
		end
	end
	local function towerArch(into,frame)
		part(into,"ArchedWindowDarkRecess",V(6,11,.2),frame*CF(0,7,-.18),darkPane,Enum.Material.SmoothPlastic,false)
		for _,sgn in ipairs({-1,1}) do part(into,"ArchedWindowJamb",V(.25,11,.32),frame*CF(sgn*3,7,-.34),C.white,nil,false) end
		for _,sgn in ipairs({-1,1}) do part(into,"ArchedWindowMullion",V(.16,10,.25),frame*CF(sgn*1,7,-.37),C.white,nil,false) end
		for _,dy in ipairs({4.7,8.3}) do part(into,"ArchedWindowCrossbar",V(6,.17,.27),frame*CF(0,dy,-.37),C.white,nil,false) end
		local last
		for j=0,6 do
			local a=math.pi*j/6
			local p=frame:PointToWorldSpace(V(3*math.cos(a),12.5+3*math.sin(a),-.36))
			if last then K.beam(into,"ArchedWindowHead",last,p,.24,C.white) end
			last=p
		end
	end
	for _,s in ipairs({-1,1}) do
		for i,z in ipairs({2150,2350}) do
			local tower=model("ImpossibleDomesticTower_"..s.."_"..i,G)
			-- Keep the two real ground homes and their supported Watcher panes.
			-- The former 38 closed upper houses were a repeated silhouette; each
			-- reference now gets its own much lighter upper facade.
			local frame=CF(s*176,0,z)*yaw(s*90)
			local home=house(tower,"TowerDwelling_0",frame,30,28,13.8,C.cream,nil,{open=true})
			if i==1 then
				K.registerWatcher(home,"SubdivisionTowerWindow_"..s,G.Name)
				local group=model(s<0 and "LeftRoundedBalconyTower" or "RightRoundedBalconyTower",slopeSection)
				-- The upper silhouette sits within the 70-degree grass-court view.
				-- Ground Watcher homes stay at x +/-176; the closer mass begins
				-- above terrace headroom and does not change their support or route.
				-- Keep the rounded S05 tower around the inclined homes. Its old
				-- 74-stud tail projected into the next, distinct S06 gabled view.
				part(group,"CreamTowerMass",V(31,76,44),CF(s*82,66,2184),paleTower,Enum.Material.Plaster)
				local nose=part(group,"RoundedTowerNose",V(76,43,43),CF(s*82,66,2184)*CFrame.Angles(0,0,math.pi/2),paleTower,Enum.Material.Plaster)
				nose.Shape=Enum.PartType.Cylinder
				for level=3,8 do
					local y=level*12
					roundedDeck(group,"RoundedProjectingBalcony",V(s*82,0,2184),22.5,y)
					part(group,"SideBalconyBand",V(5,.8,46),CF(s*64.5,y-.4,2184),C.pale,Enum.Material.Plaster,false)
					decorativeRail(group,V(s*61,0,2163),V(s*61,0,2205),y)
					if level<=6 then
						towerArch(group,CF(s*66.3,y,2184)*yaw(s*90))
						towerArch(group,CF(s*82,y,2162.2))
					end
				end
				for _,yy in ipairs({44,68,92}) do
					local lamp=part(group,"WarmApartmentSconce",V(.5,1.2,.5),CF(s*66.2,yy,2200),Color3.fromRGB(245,207,143),Enum.Material.Neon,false)
					lamp.CastShadow=false
				end
			else
				local group=model(s<0 and "WestCurvedBalconyWall" or "EastCurvedBalconyWall",skybridgeSection)
				-- Upper scenic mass draws the canyon inward while the real ground
				-- home, terraced foot route, and Watcher pane stay at their old sites.
				local scenicBase=s<0 and 8 or 16
				part(group,"MonumentalTowerWall",V(25,178-scenicBase,126),CF(s*112,(178+scenicBase)/2,2387),Color3.fromRGB(190,177,145),Enum.Material.Plaster,false)
				-- Vertical apartment bays interrupt the long dark glazing bands.
				-- They are noncolliding scenery behind the balcony route.
				for _,dz in ipairs({-56,-28,0,28,56}) do
					part(group,"FullHeightApartmentBayPier",V(.55,178-scenicBase,1.4),CF(s*99.05,(178+scenicBase)/2,2387+dz),C.pale,Enum.Material.Plaster,false)
				end
				for level=3,13 do
					local y=level*12
					-- The photographed tower has individual dark apartment openings
					-- between pale piers, not one continuous void at each storey.
					for _,offset in ipairs({-42,-14,14,42}) do
						part(group,"RecessedApartmentOpening",V(.18,7.3,16),CF(s*99.3,y+3.8,2387+offset),darkPane,nil,false)
					end
					-- A shallow band leaves the apartment windows visible from the
					-- lawn. Large circular decks swallowed the canyon view at this
					-- camera distance; the separate end bays carry the rounded edge.
					part(group,"CurvedBalconyBand",V(7,.8,120),CF(s*95.5,y-.4,2387),C.pale,Enum.Material.Plaster,false)
					local lip=part(group,"RoundedBandNose",V(120,2,2),CF(s*92,y-.5,2387)*yaw(90),C.pale,Enum.Material.Plaster,false)
					lip.Shape=Enum.PartType.Cylinder
					decorativeRail(group,V(s*91,0,2328),V(s*91,0,2446),y)
					-- Semi-circular end bays break the perfectly planar parapet into the
					-- stacked rounded corner balconies visible on both reference towers.
					for _,endZ in ipairs({2328,2446}) do
						if level%2==1 then
							roundedDeck(group,"RoundedCornerBalcony",V(s*97,0,endZ),10.5,y,endZ==2328 and -1 or 1)
						else
							-- Keep the round deck silhouette at every height; distant
							-- intermediate rails merge visually into the long balcony line.
							local endSlab=part(group,"RoundedCornerSoffit",V(1,21,21),
								CF(s*97,y-.5,endZ)*CFrame.Angles(0,0,math.pi/2),C.pale,Enum.Material.Plaster,false)
							endSlab.Shape=Enum.PartType.Cylinder
						end
					end
				end
				-- Bring the two stacked facades into the bridge canyon. The
				-- bridges terminate at the inner balcony faces in the reference.
				group:PivotTo(group:GetPivot()+V(-s*20,0,0))
			end
		end
	end
	floor(G,"WestEightStudTerrace",-110,8,2270,80,242,C.carpet)
	floor(G,"EastSixteenStudTerrace",110,16,2270,80,242,C.carpet)
	for _,s in ipairs({-1,1}) do
		local y=s<0 and 8 or 16
		for i,z in ipairs({2188,2270,2352}) do
			local frame=CF(s<0 and -116 or 130,y,z)*yaw(s*90)
			-- The middle east cottage hid almost the entire gabled facade from
			-- the S06 lawn camera. The detailed facade below owns that bay instead.
			if not (s>0 and i==2) then
				house(G,"TerraceCottage_"..s.."_"..i,frame,30,29,13.8,i==2 and C.rose or C.pale,i==2 and C.lavender or C.blue,{open=true,backOpening=i==2,furniture=i==2 and (s<0 and 3 or 5) or nil})
			end
			if s>0 and i~=2 then part(G,"EastCottageOuterSupportPier",V(3,16,3),CF(156,8,z),C.pale,Enum.Material.Plaster) end
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
	-- Two old, closed outer tilted-house stacks projected across the S06
	-- black recess. The central inclined S05 homes below already carry that
	-- anomaly, so omit these duplicate scenic stacks from the new section.
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

	-- 05: the planted volume actually hangs between the two rounded towers.
	-- Its lowest edge is above the ground runner and terrace approach, while
	-- pale diagonal ribs carry the pitched houses rather than a detached ramp.
	local slope=CF(0,58,2183)*CFrame.Angles(0,0,math.rad(-50))
	part(slopeSection,"InclinedDarkPlantedMass",V(84,4.8,34),slope,Color3.fromRGB(29,51,31),Enum.Material.Grass,false)
	-- The broad lawn face must read from the ground approach as green turf,
	-- rather than only showing the pale underside of the suspended volume.
	local frontTurf=part(slopeSection,"InclinedVisibleGrassFace",V(72,.3,24),
		CF(0,53,2166)*CFrame.Angles(0,0,math.rad(-50))*CFrame.Angles(math.rad(65),0,0),
		Color3.fromRGB(66,88,60),Enum.Material.Grass,false)
	local frontWeave=texture(frontTurf,"rbxassetid://108216315862080",Enum.NormalId.Top,8)
	if frontWeave then frontWeave.Transparency=.45 end
	part(slopeSection,"InclinedStructuralUnderside",V(85,6,35),slope*CF(0,-4,0),paleTower,Enum.Material.Plaster)
	for _,x in ipairs({-24,24}) do
		local y=x<0 and 86 or 30
		part(slopeSection,"InclineSupportPier",V(6,y-2,7),CF(x,(y-2)/2,2180),paleTower,Enum.Material.Plaster)
	end
	for i,data in ipairs({{-13,76,2160,-16},{15,45,2162,13}}) do
		local x,y,z,roll=table.unpack(data)
		local siding=i==1 and Color3.fromRGB(185,172,153) or Color3.fromRGB(206,190,166)
		local tilted=house(slopeSection,"VisiblyTiltedGabledHome_"..i,CF(x,y,z)*CFrame.Angles(0,0,math.rad(roll)),34,24,13.8,siding,Color3.fromRGB(89,74,66),{open=false})
		for _,piece in ipairs(tilted:GetDescendants()) do
			if piece:IsA("BasePart") and piece.Name=="WindowGlass" then piece.Color=Color3.fromRGB(35,38,35) end
		end
		tilted:SetAttribute("ClosedScenicProjection",true)
	end
	part(slopeSection,"LowerSuspendedTileCeiling",V(300,.7,100),CF(0,112,2130),Color3.fromRGB(155,151,133),Enum.Material.Plaster,false)
	for _,x in ipairs({-82,0,82}) do
		for _,z in ipairs({2102,2144,2172}) do
			part(slopeSection,"BrightRectangularCeilingPanel",V(9,.15,5),CF(x,111.55,z),Color3.fromRGB(231,230,218),Enum.Material.Neon,false)
		end
	end

	-- 06: a long gabled wall belongs to the lawn's east side. A full-height
	-- black recess is framed by actual separated plaster spans, not a black
	-- patch on a continuous wall. It is a blind facade, not a route shortcut.
	for _,span in ipairs({{2178,2254},{2272,2362}}) do
		part(gabledSection,"SeparatedGabledWallMass",V(2,178,span[2]-span[1]),CF(162,89,(span[1]+span[2])/2),C.cream,Enum.Material.WoodPlanks)
	end
	part(gabledSection,"BlackOpeningHead",V(2,68,18),CF(162,144,2263),C.cream,Enum.Material.WoodPlanks)
	part(gabledSection,"DeepBlackArchitecturalReturn",V(.3,110,17),CF(191,55,2263),Color3.fromRGB(2,3,2),Enum.Material.SmoothPlastic)
	for _,edge in ipairs({2254,2272}) do
		part(gabledSection,"OpeningPlasterReturn",V(29,110,.65),CF(176.5,55,edge),C.cream,Enum.Material.Plaster,false)
		part(gabledSection,"OpeningWhiteJamb",V(.6,110,.55),CF(160.8,55,edge),C.white,nil,false)
	end
	-- A visual lawn skin makes the already traversable upper terrace read as
	-- the photographed dark field without altering its support or collision.
	local facadeLawn=part(gabledSection,"DarkGabledFacadeLawn",V(80,.08,185),CF(110,16.08,2270),Color3.fromRGB(24,42,25),Enum.Material.Grass,false)
	texture(facadeLawn,"rbxassetid://108216315862080",Enum.NormalId.Top,8)
	-- A black vertical end recess terminates this distinct gabled corridor.
	-- The side-wall slot farther ahead is only legible from its own oblique
	-- approach, so it cannot supply the dark silhouette in the S06 lawn view.
	part(gabledSection,"DeepEndStructuralVoid",V(30,118,.2),CF(126,69,2179),Color3.fromRGB(3,4,3),Enum.Material.SmoothPlastic,false)
	for _,x in ipairs({110.5,141.5}) do
		part(gabledSection,"EndVoidCreamJamb",V(1.8,120,2.3),CF(x,69,2178.3),C.pale,Enum.Material.Plaster,false)
	end
	part(gabledSection,"EndVoidCreamHead",V(34,2.2,2.3),CF(126,129,2178.3),C.pale,Enum.Material.Plaster,false)
	for _,y in ipairs({33,59,85,111}) do
		part(gabledSection,"DeepRecessLandingShadow",V(28,.6,2),CF(126,y,2178.6),Color3.fromRGB(32,35,29),Enum.Material.Concrete,false)
	end
	-- The opposite facade rises above the playable terrace edge. Its open
	-- ground storey preserves the flight, crossing, and inner walkway below.
	part(gabledSection,"WestGabledBalconyWall",V(2,154,124),CF(68,101,2262),C.cream,Enum.Material.Plaster,false)
	for level=3,12 do
		local y=level*12
		-- Individual homes, white vertical divisions and intermittent small
		-- gables replace the single black horizontal stripe in the lawn view.
		for _,dz in ipairs({-38,0,38}) do
			part(gabledSection,"WestFacadeApartmentWindow",V(.15,6,22),CF(69.1,y+3.5,2262+dz),darkPane,nil,false)
			if level%3==0 then
				part(gabledSection,"WestFacadePitchedAwning",V(6,.35,16),
					CF(71.5,y+8.9,2262+dz)*CFrame.Angles(math.rad(19),0,0),
					Color3.fromRGB(82,76,69),Enum.Material.Slate,false)
			end
		end
		for _,dz in ipairs({-51,-19,19,51}) do
			part(gabledSection,"WestFacadeWhitePier",V(.32,11.5,1),CF(69.25,y+5.7,2262+dz),C.white,nil,false)
		end
		part(gabledSection,"WestFacadeBalconyBand",V(5,.8,120),CF(72,y-.4,2262),C.pale,Enum.Material.Plaster,false)
		decorativeRail(gabledSection,V(75,0,2203),V(75,0,2321),y)
	end
	-- The earlier dark plane spanned the entire far lawn and read as a void.
	-- The only deep black is the narrow recessed opening in the east facade.
	for _,z in ipairs({2190,2206,2222,2238,2288,2304,2320,2336}) do
		for level=0,10 do
			local frame=CF(160,16+level*14,z)*yaw(90)
			part(gabledSection,"ClapboardBayFace",V(16,13.8,.5),frame*CF(0,6.9,-.4),C.pale,Enum.Material.WoodPlanks,false)
			part(gabledSection,"DarkGabledWindow",V(6.4,6.2,.12),frame*CF(0,7.2,-.82),darkPane,nil,false)
			for _,sgn in ipairs({-1,1}) do
				part(gabledSection,"WhiteWindowJamb",V(.24,6.7,.22),frame*CF(sgn*3.3,7.2,-.94),C.white,nil,false)
			end
			part(gabledSection,"WhiteWindowMullion",V(.24,6.7,.22),frame*CF(0,7.2,-.98),C.white,nil,false)
			part(gabledSection,"WhiteWindowCrossbar",V(6.6,.16,.22),frame*CF(0,7.2,-.96),C.white,nil,false)
			if level>0 and level%2==0 then
				-- Narrow, projecting white balconies repeat the photograph's
				-- densely stacked house fronts instead of a flat window grid.
				part(gabledSection,"ProjectingHouseBalcony",V(14,.55,5),frame*CF(0,-.28,-2.5),C.white,Enum.Material.Wood,false)
				decorativeRail(gabledSection,frame:PointToWorldSpace(V(-7,0,-5)),frame:PointToWorldSpace(V(7,0,-5)),0)
			end
			for _,sgn in ipairs({-1,1}) do
				local roofTint=level%3==0 and Color3.fromRGB(190,164,157) or Color3.fromRGB(174,158,142)
				local roof=part(gabledSection,"RepeatedPitchedGable",V(10,.5,11),frame*CF(sgn*4,14.3,-3.2)*CFrame.Angles(0,0,-sgn*math.rad(28)),
					roofTint,Enum.Material.Slate,false)
				roof.MaterialVariant="";roof.Color=roofTint
			end
		end
		local frame=CF(160,16,z)*yaw(90)
		part(gabledSection,"WhiteGroundPorch",V(15,.65,12),frame*CF(0,-.32,-6),C.white,Enum.Material.Wood,false)
		decorativeRail(gabledSection,frame:PointToWorldSpace(V(-7,0,-12)),frame:PointToWorldSpace(V(7,0,-12)),0)
	end

	-- 09: three high bridges cross a dark, ribbed rear canyon. The tiny rear
	-- houses sit off the centre path to gate seven and preserve its left turn.
	for _,bridge in ipairs({{2350,38},{2388,82},{2422,136}}) do
		local z,y=bridge[1],bridge[2]
		part(skybridgeSection,"RailedHighSkybridge",V(184,.85,7),CF(0,y-.45,z),C.pale,Enum.Material.Plaster,false)
		for _,side in ipairs({-1,1}) do
			decorativeRail(skybridgeSection,V(-92,0,z+side*3.5),V(92,0,z+side*3.5),y)
		end
	end
	part(skybridgeSection,"DarkRibbedCeilingField",V(218,.8,190),CF(0,177.5,2358),Color3.fromRGB(47,48,31),Enum.Material.SmoothPlastic,false)
	for i=0,6 do
		local x=-90+i*30
		part(skybridgeSection,"LongDarkCeilingRib",V(.5,.3,185),CF(x,176.9,2358),Color3.fromRGB(17,18,17),Enum.Material.Metal,false)
	end
	for i=0,9 do
		local z=2290+i*17
		part(skybridgeSection,"CentralFluorescentPanel",V(8,.14,4.6),CF(0,176.65,z),Color3.fromRGB(230,231,218),Enum.Material.Neon,false)
	end
	for _,span in ipairs({{-165,-76},{-54,165}}) do
		local farFacade=part(skybridgeSection,"RecessedDomesticCanyonEnd",V(span[2]-span[1],170,.15),
			CF((span[1]+span[2])/2,85,2450),Color3.fromRGB(82,82,65),Enum.Material.Plaster,false)
		local apartmentDetail=texture(farFacade,"rbxassetid://84616323392440",Enum.NormalId.Front,85)
		if apartmentDetail then apartmentDetail.Color3=Color3.fromRGB(111,109,89);apartmentDetail.Transparency=.62 end
	end
	part(skybridgeSection,"DarkHighReturnOverGateSeven",V(22,156,.15),CF(-65,92,2450),
		Color3.fromRGB(8,10,9),Enum.Material.SmoothPlastic,false)
	local cottageGroup=model("ConnectedRearCottageGroup",skybridgeSection)
	for _,x in ipairs({-18,0,18}) do
		-- The central home has front and rear openings so the existing centre
		-- approach can continue through this deliberately domestic far silhouette.
		house(cottageGroup,"RearCanyonCottage_"..x,CF(x,0,2433),17,13,10.5,C.pale,Color3.fromRGB(61,58,55),{open=x==0,backOpening=x==0})
	end
	-- The tower bases rise from planted banks rather than a flat grass field.
	-- Both banks and cutouts are visual only so the gate-seven lawn route remains open.
	for _,side in ipairs({-1,1}) do
		local bank=part(skybridgeSection,"SlopedPlantedBank",V(28,.24,142),
			CF(side*70,6,2355)*CFrame.Angles(0,0,side*math.rad(25)),
			Color3.fromRGB(37,63,36),Enum.Material.Grass,false)
		local bankWeave=texture(bank,"rbxassetid://108216315862080",Enum.NormalId.Top,16)
		if bankWeave then bankWeave.Transparency=.3 end
		for i,z in ipairs({2325,2355,2385,2415}) do
			local height=i%2==0 and 8 or 10
			for plane=0,1 do
				local card=part(skybridgeSection,"BankHedgeCutout",V(18,height,.12),
					CF(side*(69+i%2*4),6+height/2,z)*yaw(i*27+plane*90),
					C.white,Enum.Material.SmoothPlastic,false)
				card.Transparency=1;card.CanQuery=false;card.CanTouch=false;card.CastShadow=false
				for _,face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back}) do
					local decal=Instance.new("Decal")
					decal.Name="GeneratedHedgeFoliage";decal.Face=face
					decal.Texture="rbxassetid://96127727672974";decal.Parent=card
				end
			end
		end
	end
	camera("ExpandedTiltedArrival",V(7,7,2083),V(-172,73,2206))
	camera("ExpandedTiltedTerrace",V(87,22,2330),V(-167,108,2350))
	camera("ExpandedTiltedCrossing",V(-58,14,2267),V(185,61,2238))
	camera("ExpandedTiltedRear",V(-12,8,2440),V(176,112,2345))
	camera("S05_SlopedHouseReferenceView",V(0,7,2100),V(0,68,2200))
	camera("S06_GabledFacadeReferenceView",V(115,23,2314),V(115,65,2188))
	camera("S09_SkybridgeCanyonReferenceView",V(30,7,2288),V(0,30,2420))
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
