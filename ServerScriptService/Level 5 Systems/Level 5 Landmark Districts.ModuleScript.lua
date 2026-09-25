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

	-- F: the Window Watcher courts. Ordinary small houses are nested around
	-- close carpet lanes; the lower ceiling hides the former warehouse void.
	-- All coordinates remain local to the existing F envelope. G/H are independent.
	do
		local F=zone("F_BayWindowCanyon",V(-150,0,796),V(150,60,1016),
			"Three intimate indoor house courts, rooflines below a tiled ceiling, continuous white balconies and three walkable elevations.")
		F:SetAttribute("CourtVersion","2026-09-25.window-watcher.1")
		F:SetAttribute("InnerCeilingHeight",60)
		F:SetAttribute("PlayableFloorHeights","0,15,30")
		local sage=Color3.fromRGB(135,140,113)
		local rose=Color3.fromRGB(187,151,137)
		local oatmeal=Color3.fromRGB(201,191,164)
		local roof=Color3.fromRGB(65,66,59)
		local oliveCarpet=Color3.fromRGB(129,126,95)
		floor(F,"ConnectedCarpetCourts",0,0,906,300,220,oliveCarpet)

		local function lane(name,x,z,w,d)
			return path(F,name,x,0,z,w,d,C.carpet)
		end
		-- The readable ground route doglegs around houses instead of exposing
		-- the entire district from its entry. Both x=0 thresholds remain clear.
		lane("ArrivalCarpet",0,808.5,20,25)
		lane("ArrivalLeftTurn",-13,815,46,12)
		lane("WestCourtPath",-26,860.5,14,91)
		lane("MiddleCourtCrossing",-1.5,906,63,14)
		lane("EastCourtPath",23,931,14,50)
		lane("ExitCourtCrossing",11.5,960,37,14)
		lane("ExitCarpet",0,988,20,56)

		local function domesticRail(into,frame,width)
			rail(into,frame,width)
			part(into,"WidePaintedHandrail",V(width,.18,.58),frame*CF(0,3.52,0),C.white,Enum.Material.Wood)
			local n=math.max(1,math.ceil(width/10))
			for i=0,n do
				local x=-width/2+width*i/n
				part(into,"SquareBalconyPost",V(.48,3.7,.48),frame*CF(x,1.85,0),C.white,Enum.Material.Wood)
				part(into,"BalconyPostCap",V(.7,.18,.7),frame*CF(x,3.79,0),C.white,Enum.Material.Wood)
			end
		end
		local function sideRail(x,height,a,b)
			if b-a>.25 then domesticRail(F,CF(x,height,(a+b)/2)*yaw(90),b-a) end
		end
		local function deck(name,x,height,z,w,d)
			local p=floor(F,name,x,height,z,w,d,C.carpet)
			part(F,"PaintedDeckFrontFascia",V(.34,1.1,d),CF(x+(x<0 and w/2 or -w/2),height-.5,z),C.white)
			return p
		end

		local houseCount=0
		local function cottage(into,name,frame,w,d,color,hasRoof,open)
			local home=house(into,name,frame,w,d,14.7,color,hasRoof and roof or nil,{open=open,lit=false})
			home:SetAttribute("DomesticCourtHouse",true)
			houseCount+=1
			local siding=color:Lerp(C.white,.13)
			-- Lap-board shadow lines remain on opaque plaster/wood areas; no
			-- strip crosses a doorway or paints over the standard Glass panes.
			local wing=(w-5.4)/2
			for _,y in ipairs({.7,1.65,2.6}) do for _,s in ipairs({-1,1}) do
				part(home,"LowerClapboardJoint",V(wing,.045,.055),frame*CF(s*(2.7+wing/2),y,-.355),siding,Enum.Material.Wood,false)
			end end
			for _,y in ipairs({11.05,12.3,13.55}) do
				part(home,"UpperClapboardJoint",V(w,.045,.055),frame*CF(0,y,-.355),siding,Enum.Material.Wood,false)
			end
			for _,s in ipairs({-1,1}) do
				part(home,"WhiteCornerBoard",V(.32,14.7,.25),frame*CF(s*(w/2-.14),7.35,-.4),C.white,Enum.Material.Wood,false)
				for i=1,10 do
					part(home,"SideClapboardJoint",V(.045,.045,d),frame*CF(s*(w/2+.35),i*1.32,d/2),siding,Enum.Material.Wood,false)
				end
			end
			return home
		end

		-- The two old furnished-room container names are intentionally retained.
		-- Low corner houses sit outside the two reserved staircase pockets.
		local rows={
			{name="WestHouseStack1",side=-1,x=86,z=827,w=30,d=25,levels=2,color=oatmeal,isolated=true},
			{name="WestHouseStack2",side=-1,x=58,z=878,w=32,d=25,levels=3,color=C.pale},
			{name="WestHouseStack3",side=-1,x=61,z=934,w=30,d=24,levels=2,color=rose},
			{name="WestHouseStack4",side=-1,x=58,z=980,w=31,d=25,levels=2,color=sage},
			{name="EastHouseStack1",side=1,x=60,z=833,w=30,d=25,levels=2,color=rose},
			{name="EastHouseStack2",side=1,x=62,z=887,w=32,d=25,levels=3,color=oatmeal},
			{name="EastHouseStack3",side=1,x=60,z=934,w=30,d=25,levels=2,color=sage},
			{name="EastHouseStack4",side=1,x=86,z=980,w=30,d=25,levels=2,color=C.pale,isolated=true},
		}
		for _,spec in ipairs(rows) do
			local stack=model(spec.name,F)
			for storey=0,spec.levels-1 do
				local setback=storey==2 and 2 or 0
				local frame=CF(spec.side*(spec.x+setback),storey*15,spec.z)*yaw(spec.side*90)
				local width=spec.w-(storey==2 and 2 or 0)
				cottage(stack,"CanyonDwelling_"..storey,frame,width,spec.d,
					storey==0 and spec.color or (storey==1 and oatmeal or C.pale),
					storey==spec.levels-1,storey==0 or not spec.isolated)
				if storey>0 and not spec.isolated then
					-- A shallow porch reaches from the common walk to the actual
					-- setback facade. Floors overlap; there is no doorway gap.
					local edge=spec.side<0 and 58 or 60
					local outer=spec.x+setback+.35
					floor(F,"SetbackDoorPorch",spec.side*(edge+outer)/2,storey*15,spec.z,outer-edge+.7,width,C.carpet)
				end
			end
		end

		-- Central houses conceal the next court. Their raised rooms are real
		-- shells, not solid supports occupying the lower room's interior.
		local hero=model("NestedWatcherHouse",F)
		local heroFrames={CF(10,0,870)*yaw(90),CF(10,15,871)*yaw(90),CF(12,30,870)*yaw(90)}
		cottage(hero,"SageLowerHouse",heroFrames[1],36,28,sage,false,true)
		cottage(hero,"CreamMiddleHouse",heroFrames[2],34,26,oatmeal,false,true)
		local farHome=cottage(hero,"UpperWatchingRoom",heroFrames[3],32,24,C.pale,true,false)
		-- A low side gable creates the ordinary house silhouette in the foreground.
		local nearHome=cottage(F,"NearWatcherCottage",CF(-18,0,834)*yaw(90),22,22,rose,true,false)
		local mid=model("MiddleCourtHouse",F)
		cottage(mid,"MiddleGroundHome",CF(-10,0,919),30,30,rose,false,true)
		local middleHome=cottage(mid,"MiddleUpperHome",CF(-10,15,919),30,30,oatmeal,true,true)
		local exit=model("ExitCourtHouses",F)
		cottage(exit,"ExitGroundHome",CF(30,0,971),28,22,sage,false,true)
		cottage(exit,"ExitUpperHome",CF(30,15,971),28,22,C.pale,true,false)
		cottage(exit,"WestLowGable",CF(-16,0,984)*yaw(-90),24,22,rose,true,true)

		-- Side courts let explorers loop behind the main houses on carpet.
		-- They also prevent the retained 300-stud envelope feeling like an empty hall.
		for _,spec in ipairs({
			{-1,123,850,24,22,C.pale},{-1,124,964,25,22,oatmeal},
			{1,123,854,24,22,sage},{1,124,907,25,22,C.pale},{1,123,967,24,22,rose},
		}) do
			cottage(F,"SideCourtHome_"..spec[1].."_"..spec[3],
				CF(spec[1]*spec[2],0,spec[3])*yaw(spec[1]*90),spec[4],spec[5],spec[6],true,true)
		end
		local reading=house(F,"CutawayReadingRoom",CF(-127,0,900)*yaw(-90),25,19,14,C.pale,nil,{open=true,cutaway=true,lit=false})
		reading:SetAttribute("DomesticCourtHouse",true);houseCount+=1
		thinPicture(reading,CF(-144.1,7,900)*yaw(-90),6,5)
		lane("ReadingRoomSideAccess",-109,900,42,13)
		F:SetAttribute("DomesticHouseCount",houseCount)

		-- Each stair's rising run is kept out of the slab above it. The return
		-- flights sit beside the main walk instead of drilling through a house.
		deck("WestLowerBalcony",-48,15,929,20,158) -- z850..1008
		deck("WestUpperBalcony",-48,30,906,20,204) -- z804..1008
		deck("EastLowerBalcony",49.5,15,881,21,154) -- z804..958
		deck("EastUpperBeforeStair",49.5,30,881,21,154)
		deck("EastUpperInnerBypass",48,30,974,18,32) -- x39..57; flight x58..70
		deck("EastUpperAfterStair",49.5,30,999,21,18)
		stairs(F,"WestCanyonFirstFlight",CF(-46,0,808),12,15,32,30,C.carpet,true)
		stairs(F,"WestCanyonReturnFlight",CF(-64,15,844)*yaw(180),12,15,32,30,C.carpet,true)
		floor(F,"WestSwitchbackLanding",-55,15,845,34,10,C.carpet) -- x-72..-38,z840..850
		floor(F,"WestUpperArrival",-55,30,808,34,10,C.carpet) -- z803..813
		stairs(F,"EastCanyonFirstFlight",CF(46,0,994)*yaw(180),12,15,32,30,C.carpet,true)
		stairs(F,"EastCanyonReturnFlight",CF(64,15,958),12,15,32,30,C.carpet,true)
		floor(F,"EastSwitchbackLanding",55,15,958,34,12,C.carpet)
		floor(F,"EastUpperArrival",55,30,995,34,10,C.carpet)

		for _,height in ipairs({15,30}) do
			local bridgeZ=height==15 and 898 or 960
			floor(F,"CourtCrossing_"..height,0,height,bridgeZ,84,12,C.carpet)
			local function edge(a,b,z)
				domesticRail(F,CF((a+b)/2,height,z),b-a)
			end
			if height==15 then
				-- Open connections into the hero porch and the middle-house porch.
				edge(-42,-2,bridgeZ-6);edge(10,42,bridgeZ-6)
				edge(-42,-16,bridgeZ+6);edge(-4,42,bridgeZ+6)
			else
				edge(-42,42,bridgeZ-6);edge(-42,42,bridgeZ+6)
			end
			local westStart=height==15 and 850 or 804
			for _,span in ipairs({{westStart,bridgeZ-6},{bridgeZ+6,1008}}) do sideRail(-38,height,span[1],span[2]) end
			local eastEnd=height==15 and 952 or 1008
			if bridgeZ-6<eastEnd then sideRail(39,height,804,bridgeZ-6) end
			if bridgeZ+6<eastEnd then sideRail(39,height,bridgeZ+6,eastEnd) end
		end

		-- Outer balcony edges are guarded between homes, never across a door.
		for _,side in ipairs({-1,1}) do for _,height in ipairs({15,30}) do
			local ranges={}
			for _,spec in ipairs(rows) do
				if spec.side==side and not spec.isolated and spec.levels>height/15 then
					table.insert(ranges,{spec.z-spec.w/2-.5,spec.z+spec.w/2+.5})
				end
			end
			table.sort(ranges,function(a,b) return a[1]<b[1] end)
			local cursor=side<0 and (height==15 and 850 or 813) or 804
			local ending=side>0 and 952 or 1008
			for _,range in ipairs(ranges) do
				sideRail(side<0 and -58 or 60,height,cursor,range[1])
				cursor=math.max(cursor,range[2])
			end
			sideRail(side<0 and -58 or 60,height,cursor,ending)
		end end
		-- Flight handrails cover sloping edges; only exposed landing edges get rails.
		domesticRail(F,CF(-65,15,850),14) -- x-72..-58, clear walk continuation
		sideRail(-38,15,840,850)
		-- Clear end rails are placed outside both staircase exit lines.
		domesticRail(F,CF(-55,30,803),34)
		sideRail(-72,15,840,850);sideRail(-72,30,803,813)
		domesticRail(F,CF(66,15,952),12) -- x60..72; deck connection stays open
		sideRail(38,15,952,964)
		sideRail(72,15,952,964);sideRail(72,30,990,1000)
		domesticRail(F,CF(66,30,1000),12) -- x60..72; main walk continues to1008
		sideRail(60,30,1000,1008)
		domesticRail(F,CF(-48,15,1008),20)
		domesticRail(F,CF(-48,30,1008),20)
		domesticRail(F,CF(49.5,15,804),21)
		domesticRail(F,CF(49.5,30,804),21)
		domesticRail(F,CF(49.5,30,1008),21)

		-- The middle-level bridge also reaches the two central open upper homes.
		floor(F,"HeroHouseUpperPorch",4,15,874,12,48,C.carpet) -- x-2..10,z850..898
		sideRail(-2,15,850,892)
		sideRail(10,15,850,854);sideRail(10,15,888,892)
		domesticRail(F,CF(4,15,850),12)
		floor(F,"MiddleHouseUpperApproach",-10,15,911.5,12,15,C.carpet)
		sideRail(-16,15,904,919);sideRail(-4,15,904,919)
		-- The bridge rail spans above leave these two porch connections open.

		for _,x in ipairs({-37,38}) do
			for _,z in ipairs({854,905,952,1003}) do
				if not (x>0 and z>950) then post(F,x,0,z,30) end
			end
		end
		for _,z in ipairs({856,897}) do post(F,-1,0,z,15) end
		post(F,-16,0,914,15)
		-- Architecture owns the one F office ceiling at60; the tallest gable
		-- ends below56. No duplicate ceiling or hidden upper lights are built here.

		-- Geometry-only integration contract. Parent the eventual posed mesh
		-- behind the selected pane; no AI, touch trigger, damage or audio lives here.
		local anchors=model("WindowWatcherAnchors",F)
		local function watcherAnchor(name,home,paneIndex,pose)
			local panes={}
			for _,p in ipairs(home:GetChildren()) do
				if p:IsA("BasePart") and p:GetAttribute("Level5TintedWindow")==true then panes[#panes+1]=p end
			end
			local pane=assert(panes[paneIndex],"Watcher room lacks its standard facade pane")
			local anchor=part(anchors,name,V(.12,.12,.12),CF(),C.white,Enum.Material.SmoothPlastic,false)
			anchor.CFrame=pane.CFrame
			anchor.Transparency=1;anchor.CanQuery=false;anchor.CanTouch=false;anchor.CastShadow=false
			anchor:SetAttribute("Level5WindowWatcherAnchor",true)
			anchor:SetAttribute("Pose",pose)
			anchor:SetAttribute("WindowSurfaceCFrame",pane.CFrame)
			anchor:SetAttribute("WindowNormal",pane.CFrame.LookVector)
			anchor:SetAttribute("GlassThickness",pane.Size.Z)
			anchor:SetAttribute("WallThickness",.65)
			anchor:SetAttribute("GeometryOnly",true)
			local reference=Instance.new("ObjectValue");reference.Name="WindowGlass";reference.Value=pane;reference.Parent=anchor
			for _,spec in ipairs({{"Eye",.7},{"Palm",.17},{"Retreat",2.1}}) do
				local attachment=Instance.new("Attachment");attachment.Name=spec[1]
				attachment.CFrame=CF(0,0,spec[2]);attachment.Parent=anchor
			end
			return anchor
		end
		watcherAnchor("FarUpperWindow",farHome,2,"FarWatching")
		watcherAnchor("NearGroundWindow",nearHome,1,"NearHandOnGlass")
		watcherAnchor("MiddleCourtWindow",middleHome,1,"FarWatching")
		anchors:SetAttribute("Count",3)

		camera("BayWindowCanyonEntrance",V(-4,7,802),V(4,27,870))
		camera("BayWindowCanyonUpperWalk",V(-40,35,854),V(12,36.5,860))
		camera("BayWindowCanyonCutaway",V(23,7,906),V(-22,26,930))
		camera("WindowWatcherNearWindow",V(-27,5.8,841),V(-18,6.3,841))
		camera("WindowWatcherNestedRoofs",V(45,35,915),V(4,30,870))
		point(0,3,802);point(0,3,815);point(-26,3,815);point(-26,3,844)
		point(-26,3,883);point(-26,3,906);point(23,3,906);point(23,3,928)
		point(23,3,956);point(0,3,960);point(0,3,984);point(0,3,1006)
		point(-46,3,804);point(-46,18,847);point(-64,18,847);point(-64,33,809)
		point(-46,33,854);point(-46,33,960);point(0,33,960);point(46,33,960)
		point(46,3,998);point(46,18,955);point(64,18,955);point(64,33,994)
		point(0,18,898);point(4,18,883);point(-10,18,914)
	end

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
	-- The old solid support occupied the enterable pink house at x113..140,
	-- y16..30.7, z1115..1145. Keep the upper scenic mass, with actual support
	-- beside/behind that room instead of a hidden block through its interior.
	part(fusedB,"RaisedDomesticSupportLintel",V(34,6,27),CF(130,35,1133),C.cream)
	part(fusedB,"DomesticRearSupportPier",V(4,16,27),CF(143,24,1133),C.cream)
	for _,z in ipairs({1113.6,1146.4}) do
		part(fusedB,"DomesticFlankSupportPier",V(5,16,2.4),CF(136.5,24,z),C.cream)
	end
	fusedB:SetAttribute("HollowSupportPreservesHouse",true)
	h6:SetAttribute("ScenicSupportHollowed",true)
	local tiltedB=house(fusedB,"EmbeddedTiltedCreamHome",CF(120,36,1119)*CFrame.Angles(0,math.rad(18),math.rad(-19)),28,25,13,C.pale,C.lavender,{open=false,lit=false})
	-- Move the support's decorative pane above the room as well: its previous
	-- y24.5..35.5 extent would remain a collidable pane across the cleared room.
	window(fusedB,CF(130,35,1119.2),12,5.2,false)
	-- A cropped hedge is made of carpeted boxes: it must read as indoor material,
	-- never as an outdoor landscape or an unexplained glowing object.
	for _,v in ipairs({{-147,8,1053},{-143,8,1138},{143,16,1071},{148,0,1174},{-22,0,1176}}) do
		part(G,"CarpetCoveredPlanter",V(5,2,7),CF(v[1],v[2]+1,v[3]),C.green,Enum.Material.Fabric)
		part(G,"PlanterWhiteFoot",V(5.3,.35,7.3),CF(v[1],v[2]+.18,v[3]),C.white)
	end
	-- House courts rely on the shared ceiling; no low exterior pendants.
	camera("TiltedSubdivisionArrival",V(3,8,1022),V(-89,20,1090))
	camera("TiltedSubdivisionTerraces",V(-38,16,1145),V(113,32,1111))
	camera("TiltedSubdivisionFusedHomes",V(43,7,1176),V(122,39,1132))
	point(0,3,1020); point(10,3,1090); point(10,3,1179); point(0,3,1192)
	point(-58,3,1017); point(-58,11,1042); point(-65,11,1100); point(-65,11,1138); point(-43,3,1173)
	point(73,3,1030); point(73,19,1069); point(100,19,1069); point(100,19,1130)
	point(116,19,1130); point(132,19,1130); point(116,19,1130); point(100,19,1130)
	point(100,19,1150); point(123,19,1150); point(123,3,1189)

	-- H: domestic familiarity compresses into an offset vestibule, then the
	-- narrow descent. This remains architecture only: no puzzle, slide or win.
	local H=zone("H_LastHouse",V(-60,-30,1196),V(60,26,1319),
		"Quiet final residential court, sparse waiting house, offset low vestibule, painted directions and enclosed black descent.")
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
	finalHouse:SetAttribute("EndingArchitectureVersion","2026-09-25.1")
	finalHouse:SetAttribute("RearVestibuleClearance",10.6)
	for _,s in ipairs({-1,1}) do
		part(finalHouse,"InteriorRoomDivider",V(.55,15,10),CF(s*12,7.5,1230),C.cream)
		skirting(finalHouse,CF(s*12,0,1230)*yaw(90),10)
	end

	-- A few deliberately ordinary objects occupy the side alcove. Nothing sits
	-- in the entry or the turning path, and nothing implies an active puzzle.
	local waiting=model("QuietWaitingAlcove",finalHouse)
	local wood=Color3.fromRGB(121,94,63)
	local woodEdge=Color3.fromRGB(153,122,85)
	local darkWood=Color3.fromRGB(74,58,42)
	local cabinet=CF(-18.35,0,1237.2)*yaw(-90)
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
	local chair=CF(-16.7,0,1229.8)*yaw(-7)
	for _,x in ipairs({-.86,.86}) do for _,z in ipairs({-.86,.86}) do
		part(waiting,"WaitingChairLeg",V(.17,1.7,.17),chair*CF(x,.85,z),wood,Enum.Material.Wood)
	end end
	part(waiting,"WaitingChairSeat",V(2.08,.22,2.08),chair*CF(0,1.81,0),woodEdge,Enum.Material.Wood)
	for _,x in ipairs({-.86,.86}) do
		part(waiting,"WaitingChairBackPost",V(.17,2.35,.17),chair*CF(x,2.65,.86),wood,Enum.Material.Wood)
	end
	part(waiting,"WaitingChairBackRail",V(1.88,.25,.19),chair*CF(0,3.73,.86),woodEdge,Enum.Material.Wood)
	part(waiting,"WaitingChairBackPanel",V(1.53,.62,.13),chair*CF(0,3.1,.86),woodEdge,Enum.Material.Wood)
	thinPicture(finalHouse,CF(-15.3,6.8,1254.53),4.1,3.3)

	-- The nine-stud opening is intentionally off-axis from both exterior doors.
	-- The return wall ends with 7.475 studs of clear turning depth at the rear.
	-- Preserve the front door and the original seven-stud chute doorway.
	local vestibule=model("OffsetRearVestibule",finalHouse)
	part(vestibule,"VestibuleFrontLeftWall",V(25.5,15,.65),CF(-8.25,7.5,1241.5),C.cream)
	part(vestibule,"VestibuleFrontRightWall",V(7.5,15,.65),CF(17.25,7.5,1241.5),C.cream)
	part(vestibule,"VestibuleDoorLintel",V(9,4.7,.65),CF(9,12.65,1241.5),C.cream)
	K.doorframe(vestibule,CF(9,0,1241.12),9,10.3)
	part(vestibule,"VestibuleReturnWall",V(.65,10.6,5.7),CF(4.5,5.3,1244.35),C.cream)
	part(vestibule,"LowVestibuleCeiling",V(42,.45,13.35),CF(0,10.825,1248.325),C.ceiling)
	skirting(vestibule,CF(-8.25,0,1241.12),25.5)
	skirting(vestibule,CF(17.25,0,1241.12),7.5)
	skirting(vestibule,CF(4.88,0,1244.35)*yaw(90),5.7)
	part(vestibule,"VestibuleCeilingCornice",V(42,.3,.32),CF(0,10.45,1242.04),C.white)
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
	paintedArrow("FirstRightTurnArrow",V(0,6,1241.15),V(0,0,-1),6.2,6.2/1.5,V(1,0,0),true)
	paintedArrow("VestibuleForwardArrow",V(4.855,5.7,1244.35),V(1,0,0),4.8,3.2,V(0,0,1),true)
	paintedArrow("RearLeftTurnArrow",V(8.6,5.7,1254.645),V(0,0,-1),6.2,6.2/1.5,V(-1,0,0))

	local chute=model("NarrowDescent",H)
	local chuteStart,bend,chuteEnd=V(0,0,1255),V(0,-11,1287),V(0,-29,1310)
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
	roofClosure("EntranceRoofClosure",V(0,10.75,1254.7),chuteStart+firstFrame.UpVector*8.7,C.ceiling)
	for _,s in ipairs({-1,1}) do
		part(chute,"EntranceSideCollar",V(.7,10.95,4.15),CF(s*3.95,5.325,1256.375),C.cream)
	end
	roofClosure("BendRoofClosure",bend+firstFrame.UpVector*8.7,bend+secondFrame.UpVector*8.7,Color3.fromRGB(3,3,3))
	for _,s in ipairs({-1,1}) do
		part(chute,"BendSideCollar",V(.7,11.5,8),CF(s*3.95,bend.Y+4,bend.Z+2.5),Color3.fromRGB(3,3,3))
	end

	-- One final painted direction follows the actual slope on the inside wall.
	local descentDirection=(bend-chuteStart).Unit
	local arrowCenter=chuteStart+descentDirection*6+firstFrame.UpVector*4.9+V(-3.585,0,0)
	paintedArrow("DownTheSlopeArrow",arrowCenter,V(1,0,0),5.4,3.6,descentDirection,true)
	floor(chute,"DarkArrivalFloor",0,-29,1314.5,8,9,Color3.fromRGB(2,2,2))
	part(chute,"DarkArrivalCeiling",V(8,.7,9),CF(0,-20.3,1314.5),Color3.fromRGB(2,2,2))
	for _,s in ipairs({-1,1}) do part(chute,"DarkArrivalSide",V(.7,9,9),CF(s*4,-24.5,1314.5),Color3.fromRGB(2,2,2)) end
	part(chute,"DarkArrivalEnd",V(8,9,.7),CF(0,-24.5,1319),Color3.fromRGB(2,2,2))
	chute:SetAttribute("GeometryOnly_NoSlideOrCompletion",true)
	chute:SetAttribute("SuggestedSlideStartFraction",.7)
	chute:SetAttribute("ArchitecturalDarkEnding",true)
	chute:SetAttribute("PitchSeamsClosed",true)
	camera("LastHouseQuietCourt",V(-12,6,1198),V(4,8,1231))
	camera("LastHousePuzzleRoom",V(0,6,1230),V(8,5.8,1242))
	camera("LastHouseVestibule",V(9,5,1244),V(0,5,1254))
	camera("LastHouseDescent",V(0,5,1253),V(0,-10,1286))
	camera("LastHouseDarkArrival",V(0,-18,1302),V(0,-25,1316))
	point(0,3,1198); point(0,3,1221); point(0,3,1237.5)
	point(9,3,1237.5); point(9,3,1250.9); point(0,3,1250.9); point(0,3,1253)
	point(0,-8,1287); point(0,-26,1314)
	return {PreviewCameras=cameras,Waypoints=waypoints,Zones=zones,FinalHouse=finalHouse,ChuteStart=chuteStart,ChuteEnd=chuteEnd}
end

return Districts
