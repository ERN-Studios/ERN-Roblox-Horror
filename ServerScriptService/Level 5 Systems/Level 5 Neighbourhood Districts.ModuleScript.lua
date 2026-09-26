-- Human-scale homes repeated into large, genuinely different indoor districts.
-- K owns origin translation, the common window standard and all material assets.
local Districts={}
function Districts.Build(K)
	local model,part,floor,house,stairs,rail=K.model,K.part,K.floor,K.house,K.stairs,K.rail
	local C,V,CF=K.C,K.V,K.CF
	local yaw=function(deg) return CFrame.Angles(0,math.rad(deg),0) end
	local cameras,waypoints,zones={},{},{}
	local function camera(n,p,t) table.insert(cameras,{name=n,position=p,lookAt=t}) end
	local function point(x,y,z) table.insert(waypoints,V(x,y,z)) end
	local function zone(n,minimum,maximum)
		local m=model(n);table.insert(zones,{Name=n,Model=m,Min=minimum,Max=maximum,CeilingHeight=maximum.Y});return m
	end
	local Czone=zone("C_PastelVillage",V(-280,0,456),V(280,100,936))
	floor(Czone,"GreenCarpetNeighbourhood",0,0,696,560,480,C.green)
	floor(Czone,"CentralSandRunner",0,.025,696,22,478,C.carpet)
	local colors={C.rose,C.blue,C.yellow,C.lavender}
	for court,info in ipairs({{-145,545},{145,545},{-145,840},{145,840}}) do
		local cx,cz=info[1],info[2]
		local cluster=model("PastelCourt_"..court,Czone)
		floor(cluster,"CarpetCourtSquare",cx,.03,cz,124,104,C.carpet)
		local frames={CF(cx,0,cz-50)*yaw(180),CF(cx,0,cz+50),CF(cx-65,0,cz)*yaw(-90),CF(cx+65,0,cz)*yaw(90)}
		for i,frame in ipairs(frames) do
			local outside=(cx<0 and i==3) or (cx>0 and i==4)
			local stories=outside and (court%2==0 and 5 or 6) or 1
			for level=0,stories-1 do
				local home=house(cluster,"CourtHouse_"..court.."_"..i.."_"..level,frame*CF(0,level*14,0),28,25,13.8,colors[(court+i+level-2)%4+1],level==stories-1 and colors[(court+i)%4+1] or nil,{open=level==0,backOpening=level==0 and i==1,furniture=level==0 and i==2 and (court%5+1) or nil,glitchedTable=court==2})
				if i==1 and level==0 then K.registerWatcher(home,"VillageCourtWindow_"..court,Czone.Name) end
			end
			floor(cluster,"PorchThreshold",0,0,-3,28,6,C.pink,frame)
			-- Shutters and tiny offsets are architectural variation, never scaled homes.
			for _,s in ipairs({-1,1}) do part(cluster,"PastelShutter",V(.65,7.5,.25),frame*CF(s*12.3,6.55,-.6),colors[(court+1)%4+1],Enum.Material.Wood) end
		end
		local side=cx<0 and -1 or 1
		floor(cluster,"CourtConnectingCarpet",side*66,.045,cz,132,13,C.carpet)
	end
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({650,715,765}) do
			for level=0,(i==2 and 2 or 0) do
				house(Czone,"CrossStreetCottage_"..side.."_"..i.."_"..level,CF(side*120,level*14,z)*yaw(side*90),28,26,13.8,colors[(i+(side+1)/2)%4+1],level==(i==2 and 2 or 0) and C.lavender or nil,{open=level==0})
			end
		end
	end
	-- Short residential lanes occupy the spaces between the four courts. Their
	-- doors, rooflines and asymmetric heights read as houses at walking scale.
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({615,675,745,805}) do
			local stories=i%2==0 and 3 or 2
			for level=0,stories-1 do
				house(Czone,"VillageInnerLaneHome_"..side.."_"..i.."_"..level,CF(side*50,level*14,z)*yaw(side*90),32,26,13.8,colors[(i+(side+1)/2)%4+1],level==stories-1 and C.blue or nil,{open=level==0,completeHome=level==0,furniture=level==0 and i==1 and (side<0 and 6 or 7) or nil})
			end
		end
		for i,z in ipairs({655,750}) do
			for level=0,3 do house(Czone,"OuterVillageStack_"..side.."_"..i.."_"..level,CF(side*244,level*14,z)*yaw(side*90),30,28,13.8,colors[(i+level)%4+1],level==3 and C.lavender or nil,{open=level==0,completeHome=level==0}) end
		end
	end
	floor(Czone,"WhiteBridgeCarpet",0,14,700,230,16,C.pink)
	for _,z in ipairs({692,708}) do
		rail(Czone,CF(0,14,z),182)
		for _,s in ipairs({-1,1}) do rail(Czone,CF(s*112,14,z),6) end
	end
	stairs(Czone,"WestBridgeFlight",CF(-100,0,655),14,14,32,28,C.pink,true)
	floor(Czone,"WestBridgeLanding",-100,14,690,18,10,C.pink)
	stairs(Czone,"EastBridgeFlight",CF(100,0,745)*yaw(180),14,14,32,28,C.pink,true)
	floor(Czone,"EastBridgeLanding",100,14,709,18,10,C.pink)
	for _,x in ipairs({-115,115}) do part(Czone,"BridgeSupportPier",V(2,14,2),CF(x,7,700),C.white) end
	camera("VillageFourCourts",V(-20,8,474),V(-145,26,546))
	camera("VillageUpperCrossing",V(-101,19,696),V(135,35,838))
	camera("VillageBackCourt",V(171,6,881),V(220,49,840))
	for _,z in ipairs({462,535,610,682,719,790,870,930}) do point(0,3,z) end

	-- D has a real twelve-stud depression, raised domestic sidewalks and a
	-- cross-street at grade. Lower and upper circuits reconnect without jumping.
	local D=zone("D_FloralTerraces",V(-160,-14,936),V(160,88,1296))
	floor(D,"SunkenGreenCarpet",0,-12,1116,320,360,C.green)
	floor(D,"ArrivalAtGrade",0,0,942,320,12,C.carpet)
	floor(D,"DepartureAtGrade",0,0,1279,320,34,C.carpet)
	stairs(D,"DownToSunkenStreet",CF(0,0,948),22,-12,32,24,C.pink,true)
	stairs(D,"StreetExitStair",CF(0,-12,1230),22,12,32,24,C.pink,true)
	floor(D,"SunkenPinkRunner",0,-11.97,1105,16,250,C.pink)
	for _,s in ipairs({-1,1}) do
		floor(D,"RaisedPorchPromenade",s*128,0,1116,64,336,C.yellow)
		part(D,"TerraceRetainingWall",V(.8,12,336),CF(s*96,-6,1116),C.yellow)
		-- The exit street returns to full-width grade at1262: no fall edge
		-- remains there, so continuing the rail would block the offset gate route.
		K.edgeRail(D,s*96,0,948,1262,{{1097,1115}})
		for i,z in ipairs({994,1109,1214}) do
			local frame=CF(s*105,0,z)*yaw(s*90)
			for level=0,5 do
				local home=house(D,"FloralTowerHome_"..s.."_"..i.."_"..level,frame*CF(0,level*14,0),30,26,13.8,(level+i)%2==0 and C.yellow or C.pale,nil,{open=level==0,backOpening=level==0 and i==2,furniture=level==0 and i==3 and (s<0 and 3 or 5) or nil})
				if level==0 and i==1 then K.registerWatcher(home,"FloralTerraceWindow_"..s,D.Name) end
			end
		end
		for i,z in ipairs({1045,1170}) do house(D,"LowerFloralHome_"..s.."_"..i,CF(s*48,-12,z)*yaw(s*90),28,26,13.8,i==1 and C.rose or C.yellow,C.blue,{open=true}) end
		for i,z in ipairs({1032,1158,1250}) do
			local p=part(D,"FloralPaperWallPanel",V(.06,34,34),CF(s*159.33,28,z),C.pale,nil,false)
			K.material(p,"Wallpaper")
		end
	end
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({1004,1220}) do
			for level=0,2 do house(D,"SunkenPocketStack_"..side.."_"..i.."_"..level,CF(side*26,-12+level*14,z)*yaw(side*90),26,24,13.8,i==1 and C.pale or C.rose,level==2 and C.blue or nil,{open=level==0}) end
		end
	end
	house(D,"SunkenCornerResidence",CF(0,-12,1132),36,24,13.8,C.yellow,C.lavender,{open=true,completeHome=true,furniture=8})
	floor(D,"RaisedCrossStreet",0,0,1106,320,18,C.yellow)
	for _,z in ipairs({1097,1115}) do
		rail(D,CF(0,0,z),146)
		-- The outer promenades are already at this same height on both sides.
		-- Only the central sunken street needs a fall barrier; outer rails would
		-- bisect actual homes and prevent reaching the cross-street at grade.
	end
	stairs(D,"SunkenWestReturn",CF(-86,-12,1057),14,12,32,24,C.pink,true)
	floor(D,"SunkenWestLanding",-86,0,1094,18,10,C.pink)
	stairs(D,"SunkenEastReturn",CF(86,-12,1158)*yaw(180),14,12,32,24,C.pink,true)
	floor(D,"SunkenEastLanding",86,0,1121,18,12,C.pink)
	camera("FloralSunkenArrival",V(9,5,943),V(-73,22,1108))
	camera("FloralLowerStreet",V(-15,-6,1031),V(90,37,1195))
	camera("FloralHighPorches",V(-93,6,1130),V(116,32,1212))
	point(0,3,941);point(0,2.5,948);point(0,-9,980);point(0,-9,1040);point(0,-9,1112);point(0,-9,1175);point(0,-9,1230);point(0,3,1264);point(0,3,1290)

	-- E: several real rooms deep. Side routes return behind the houses, while
	-- a succession of through-houses forms an understandable central passage.
	local E=zone("E_DomesticLabyrinth",V(-160,0,1296),V(160,44,1596))
	floor(E,"DomesticBroadloom",0,0,1446,320,300,C.carpet)
	for _,s in ipairs({-1,1}) do
		for i,z in ipairs({1340,1430,1520}) do
			for row,x in ipairs({54,114}) do
				local home=house(E,"DomesticRoom_"..s.."_"..row.."_"..i,CF(s*x,0,z)*yaw(s*90),36,28,13.8,(row+i)%2==0 and C.pale or C.cream,nil,{open=true,backOpening=true,furniture=row==2 and i==2 and (s<0 and 1 or 4) or nil})
				if row==1 and i==1 then K.registerWatcher(home,"DomesticWindow_"..s,E.Name) end
			end
		end
		part(E,"LowRoomCeilingBand",V(114,.6,300),CF(s*103,16,1446),C.ceiling)
		for _,z in ipairs({1387,1477,1570}) do
			-- The two cross-lane homes replace these former free-standing frames;
			-- retaining a frame inside a new room would obstruct its furniture.
			if not (s==1 and z==1387) and not (s==-1 and z==1477) then K.doorframe(E,CF(s*91,0,z),12,11.5) end
		end
	end
	for i,z in ipairs({1370,1460,1540}) do
		for level=0,2 do
			house(E,"NestedThroughHouse_"..i.."_"..level,CF(level==0 and 0 or (i%2==0 and 4 or -4),level*14,z),level==0 and 66 or 58,28,13.8,level==1 and C.pale or C.cream,nil,{open=level==0,backOpening=level==0})
		end
	end
	for i,z in ipairs({1310,1570}) do
		for level=0,2 do house(E,"LabyrinthEndResidence_"..i.."_"..level,CF(0,level*14,z),44,i==1 and 26 or 20,13.8,C.pale,nil,{open=level==0,completeHome=level==0 and i==1,furniture=level==0 and i==1 and 7 or nil}) end
	end
	house(E,"EastCrossLaneRoom",CF(72,0,1390)*yaw(90),22,34,13.8,C.cream,nil,{open=true})
	house(E,"WestCrossLaneRoom",CF(-72,0,1478)*yaw(-90),22,34,13.8,C.pale,nil,{open=true})
	for _,z in ipairs({1320,1415,1505,1580}) do
		local p=part(E,"SharedLowDomesticPanel",V(6,.15,3),CF(z==1320 and 28 or 0,15,z),Color3.fromRGB(211,216,188),Enum.Material.Neon,false)
		p:SetAttribute("TubeState","Dim")
		local l=Instance.new("SurfaceLight");l.Face=Enum.NormalId.Bottom;l.Range=26;l.Angle=150;l.Brightness=.45;l.Shadows=false;l.Parent=p
	end
	camera("DomesticRoomArrival",V(5,6,1302),V(34,13,1406))
	camera("DomesticBackLoop",V(-94,6,1398),V(-90,8,1519))
	camera("DomesticNestedCeiling",V(0,6,1510),V(-13,28,1550))
	for _,z in ipairs({1302,1347,1371,1399,1440,1461,1489,1539,1569,1590}) do point(0,3,z) end
	return {PreviewCameras=cameras,Waypoints=waypoints,Zones=zones}
end
return Districts
