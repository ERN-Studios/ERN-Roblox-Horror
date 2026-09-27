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
	local function colorRoof(home,tint)
		-- The shared roof MaterialVariant carries a blue base hue. These two
		-- reference rows need their own visibly different shingle colors.
		for _,piece in ipairs(home:GetDescendants()) do
			if piece:IsA("BasePart") and (piece.Name=="PitchedRoof" or piece.Name=="RoofRidge" or piece.Name=="RoofCladdingSeam") then
				piece.MaterialVariant="";piece.Material=Enum.Material.Slate
				piece.Color=piece.Name=="RoofCladdingSeam" and tint:Lerp(C.dark,.25) or tint
			end
		end
	end
	local function colorClapboard(home,tint)
		local exterior={SideWall=true,BackWall=true,BackWallWing=true,BackWallHeader=true,FacadeLintel=true,WindowApron=true,FacadePier=true,GableBaseBand=true,ClosedGableTriangle=true}
		for _,piece in ipairs(home:GetDescendants()) do
			if piece:IsA("BasePart") and exterior[piece.Name] then
				-- Keep the shared horizontal siding texture while preserving the
				-- photographed sage/taupe distinction between house fronts.
				piece.Color=tint
			end
		end
	end
	local function porch(into,frame,width,depth,roofTint,postOffsetX)
		local p=model("WhiteColumnPorch",into)
		part(p,"PorchEdge",V(width,.24,.5),frame*CF(0,.12,-depth),C.white,nil,false)
		for _,s in ipairs({-1,1}) do
			local roof=part(p,"ShallowPitchedPorchRoof",V((width+3)/2,.55,depth+2),frame*CF(s*(width+3)/4,13.35,-depth/2)*CFrame.Angles(0,0,-s*math.rad(12)),roofTint or C.dark,Enum.Material.Slate)
			roof.MaterialVariant="";roof.Color=roofTint or C.dark
		end
		part(p,"PorchFascia",V(width+3,.75,.35),frame*CF(0,12.05,-depth-1),C.white)
		for _,s in ipairs({-1,1}) do
			local offset=V(postOffsetX or 0,0,0)
			part(p,"SquarePorchColumn",V(.75,11.7,.75),frame*CF(s*(width/2-1),6,-depth+.7)+offset,C.white)
			part(p,"ColumnFoot",V(1.2,.6,1.2),frame*CF(s*(width/2-1),.3,-depth+.7)+offset,C.white)
			part(p,"PorchSideHandrail",V(.22,.25,depth-1),frame*CF(s*(width/2-1),3.3,-depth/2),C.white,nil,false)
			for j=1,3 do part(p,"PorchSideSpindle",V(.16,3,.16),frame*CF(s*(width/2-1),1.8,-depth+j*depth/4),C.white,nil,false) end
			local half=(width-8)/2
			part(p,"FrontBalustradeTop",V(half,.25,.2),frame*CF(s*(width+8)/4,3.3,-depth+.7),C.white,nil,false)
			for j=0,3 do part(p,"FrontBalustradeSpindle",V(.15,3,.15),frame*CF(s*(4+j*half/3),1.8,-depth+.7),C.white,nil,false) end
		end
		return p
	end
	local function balconyRail(into,front,y,z,width)
		part(into,"WhiteBalconyTopRail",V(.2,.25,width),CF(front,y+3.4,z),C.white,nil,false)
		part(into,"WhiteBalconyBottomRail",V(.2,.18,width),CF(front,y+.5,z),C.white,nil,false)
		for j=0,math.ceil(width/4) do
			part(into,"WhiteBalconySpindle",V(.16,2.9,.16),CF(front,y+1.9,z-width/2+width*j/math.ceil(width/4)),C.white,nil,false)
		end
	end
	local function scenicCottageFront(into,name,x,z,width,height,siding,roofTint)
		-- This thin, nonblocking frontage closes the large gaps in S03's arrival
		-- perspective. It never replaces a clue home or a Watcher-supporting room.
		local facade=model(name,into)
		local frame=CF(x,0,z)*yaw(180)
		part(facade,"ClapboardFront",V(width,height,.55),frame*CF(0,height/2,0),siding,Enum.Material.Wood,false)
		for y=2.5,height-1,2.5 do
			part(facade,"SidingShadowLine",V(width,.08,.06),frame*CF(0,y,-.34),siding:Lerp(C.dark,.16),nil,false)
		end
		for _,level in ipairs(height>23 and {7,20} or {7,16}) do
			for _,side in ipairs({-1,1}) do
				local wx=side*width*.27
				part(facade,"TallDarkSash",V(5.7,7.4,.12),frame*CF(wx,level,-.39),Color3.fromRGB(49,59,56),Enum.Material.Glass,false)
				for _,edge in ipairs({-1,1}) do
					part(facade,"WhiteWindowJamb",V(.32,8.1,.22),frame*CF(wx+edge*3,level,-.48),C.white,nil,false)
				end
				for _,dy in ipairs({-3.9,0,3.9}) do
					part(facade,"WhiteWindowRail",V(6.3,.25,.22),frame*CF(wx,level+dy,-.48),C.white,nil,false)
				end
				part(facade,"CentreMullion",V(.18,7.6,.22),frame*CF(wx,level,-.49),C.white,nil,false)
				for _,edge in ipairs({-1,1}) do
					part(facade,"NarrowShutter",V(.7,8,.22),frame*CF(wx+edge*3.5,level,-.43),siding:Lerp(C.dark,.35),Enum.Material.Wood,false)
				end
			end
		end
		part(facade,"RecessedFrontDoor",V(4.8,9,.18),frame*CF(0,4.5,-.43),Color3.fromRGB(71,79,69),Enum.Material.Wood,false)
		for _,side in ipairs({-1,1}) do
			part(facade,"DoorJamb",V(.38,9.5,.27),frame*CF(side*2.6,4.75,-.49),C.white,nil,false)
		end
		part(facade,"DoorHeader",V(5.6,.4,.27),frame*CF(0,9.6,-.49),C.white,nil,false)
		local half=width/2+1
		local pitch=math.rad(31)
		local gableRise=(width/2)*math.tan(pitch)
		local gableBase=.5+math.tan(pitch)
		part(facade,"GableBaseBand",V(width,gableBase,.55),frame*CF(0,height+gableBase/2,-.02),siding,Enum.Material.Wood,false)
		for _,side in ipairs({-1,1}) do
			local roof=part(facade,"PitchedSlateRoof",V(half/math.cos(pitch),.42,10),frame*CF(side*half/2,height+half*math.tan(pitch)/2+.35,4)*CFrame.Angles(0,0,-side*pitch),roofTint,Enum.Material.Slate,false)
			roof.MaterialVariant="";roof.Color=roofTint
			part(facade,"GableWhiteRake",V(half/math.cos(pitch),.27,.4),frame*CF(side*half/2,height+half*math.tan(pitch)/2+.4,-1.3)*CFrame.Angles(0,0,-side*pitch),C.white,nil,false)
			part(facade,"ClosedGableTriangle",V(.6,gableRise,width/2),frame*CF(side*width/4,height+gableBase+gableRise/2,-.03)*CFrame.Angles(0,-side*math.pi/2,0),siding,Enum.Material.Wood,false,"WedgePart")
		end
		part(facade,"RoofRidge",V(.38,.38,10.5),frame*CF(0,height+half*math.tan(pitch)+.4,4),roofTint,Enum.Material.Slate,false)
		part(facade,"PorchFascia",V(width*.78,.5,.4),frame*CF(0,11,-5),C.white,nil,false)
		part(facade,"PorchCanopy",V(width*.8,.35,5.4),frame*CF(0,11.3,-2.7),roofTint,Enum.Material.Slate,false)
		for _,side in ipairs({-1,1}) do
			part(facade,"PorchPost",V(.65,10.8,.65),frame*CF(side*width*.36,5.4,-4.5),C.white,nil,false)
			part(facade,"PorchRail",V(width*.26,.22,.24),frame*CF(side*width*.24,3.3,-4.5),C.white,nil,false)
		end
		return facade
	end
	local Czone=zone("C_PastelVillage",V(-280,0,456),V(280,100,936))
	local S03=model("S03_BrightCottageAtrium",Czone)
	floor(Czone,"GreenCarpetNeighbourhood",0,0,696,560,480,C.green)
	floor(Czone,"CentralSandRunner",0,.025,696,12,478,C.carpet)
	local colors={Color3.fromRGB(186,186,158),Color3.fromRGB(166,179,166),Color3.fromRGB(193,178,157),Color3.fromRGB(197,187,168)}
	for court,info in ipairs({{-145,545},{145,545},{-145,840},{145,840}}) do
		local cx,cz=info[1],info[2]
		local cluster=model("PastelCourt_"..court,S03)
		floor(cluster,"CarpetCourtSquare",cx,.03,cz,124,104,C.carpet)
		local frames={CF(cx,0,cz-50)*yaw(180),CF(cx,0,cz+50),CF(cx-65,0,cz)*yaw(-90),CF(cx+65,0,cz)*yaw(90)}
		for i,frame in ipairs(frames) do
			local width= i==2 and 32 or 28
			local roofTint=court%2==0 and Color3.fromRGB(91,94,87) or Color3.fromRGB(119,105,87)
			local home=house(cluster,"CourtHouse_"..court.."_"..i.."_0",frame,width,25,13.8,colors[(court+i-2)%4+1],roofTint,{open=true,backOpening=i==1,furniture=i==2 and (court%5+1) or nil,glitchedTable=court==2})
			colorRoof(home,roofTint)
			colorClapboard(home,colors[(court+i-2)%4+1])
			if i==1 then K.registerWatcher(home,"VillageCourtWindow_"..court,Czone.Name) end
			if (court==1 or court==4) and i<=2 then porch(cluster,frame,width,7,Color3.fromRGB(98,102,95)) end
			floor(cluster,"PorchThreshold",0,0,-3,28,6,C.pink,frame)
			-- Shutters and tiny offsets are architectural variation, never scaled homes.
			for _,s in ipairs({-1,1}) do part(cluster,"PastelShutter",V(.65,7.5,.25),frame*CF(s*(width/2+.45),6.55,-.6),colors[(court+1)%4+1],Enum.Material.Wood) end
		end
		local side=cx<0 and -1 or 1
		floor(cluster,"CourtConnectingCarpet",side*66,.045,cz,132,13,C.carpet)
	end
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({650,715,765}) do
			local frame=CF(side*120,0,z)*yaw(side*90)
			local roofTint=Color3.fromRGB(100,106,97)
			local home=house(Czone,"CrossStreetCottage_"..side.."_"..i.."_0",frame,28,26,13.8,colors[(i+(side+1)/2)%4+1],roofTint,{open=true})
			colorRoof(home,roofTint)
			colorClapboard(home,colors[(i+(side+1)/2)%4+1])
			if i~=2 then porch(S03,frame,28,6,Color3.fromRGB(113,105,89)) end
		end
	end
	-- Short residential lanes occupy the spaces between the four courts. Their
	-- doors, rooflines and asymmetric heights read as houses at walking scale.
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({615,675,745,805}) do
			local frame=CF(side*50,0,z)*yaw(side*90)
			local roofTint=Color3.fromRGB(104,107,99)
			local home=house(Czone,"VillageInnerLaneHome_"..side.."_"..i.."_0",frame,32,26,13.8,colors[(i+(side+1)/2)%4+1],roofTint,{open=true,completeHome=true,furniture=i==1 and (side<0 and 6 or 7) or nil})
			colorRoof(home,roofTint)
			colorClapboard(home,colors[(i+(side+1)/2)%4+1])
		end
		for i,z in ipairs({655,750}) do
			-- The right-side apartment wall now occupies this former scenic lot.
			-- Keep the left-side ground homes and all four Watcher court houses.
			if side<0 then
				local roofTint=Color3.fromRGB(106,109,101)
				local home=house(Czone,"OuterVillageStack_"..side.."_"..i.."_0",CF(side*244,0,z)*yaw(side*90),30,28,13.8,colors[i%4+1],roofTint,{open=true,completeHome=true})
				colorRoof(home,roofTint)
				colorClapboard(home,colors[i%4+1])
			end
		end
	end
	-- A separate rectilinear apartment facade rises behind the cottage row.
	-- Its compact rail rhythm replaces the forty-six unreachable upper homes.
	local apartment=model("RectangularApartmentWall",S03)
	part(apartment,"CreamApartmentCore",V(5,84,230),CF(185,42,705),Color3.fromRGB(220,216,197),Enum.Material.Plaster)
	for bay,z in ipairs({615,657,699,741,783}) do
		for level=2,5 do
			local y=level*14
			local inset=bay%2==0 and 2 or 0
			part(apartment,"RecessedBalconyBay",V(.5,11.4,29),CF(182,y+5.8,z+inset),Color3.fromRGB(181,181,165),nil,false)
			part(apartment,"ProjectingBalconyDeck",V(15,.6,32),CF(175,y-.3,z+inset),C.pale)
			balconyRail(apartment,167.6,y,z+inset,31)
			part(apartment,"BalconyDoorShadow",V(.2,8,5),CF(181.6,y+5,z+inset-7),C.dark,nil,false)
			-- The photograph reads as a stack of recessed homes, rather than
			-- continuous horizontal concrete stripes. Frame each landing as a bay.
			part(apartment,"ApartmentBalconyCeiling",V(14,.32,31),CF(175,y+11.6,z+inset),Color3.fromRGB(225,221,204),Enum.Material.Plaster,false)
			part(apartment,"ApartmentWindowPair",V(.2,7.6,5.4),CF(181.5,y+5,z+inset+6),Color3.fromRGB(62,72,69),Enum.Material.Glass,false)
			for _,edge in ipairs({-1,1}) do
				part(apartment,"ApartmentWindowJamb",V(.27,8,.27),CF(181.1,y+5,z+inset+6+edge*2.75),C.white,nil,false)
			end
			part(apartment,"ApartmentWindowHead",V(.27,.28,6),CF(181.1,y+9,z+inset+6),C.white,nil,false)
			part(apartment,"ApartmentWindowSill",V(.4,.26,6),CF(181.1,y+1,z+inset+6),C.white,nil,false)
			local porchLamp=part(apartment,"WarmBalconyDownlight",V(2.5,.13,3.2),CF(174.5,y+11.38,z+inset),Color3.fromRGB(252,228,177),Enum.Material.Neon,false)
			local glow=Instance.new("SurfaceLight");glow.Face=Enum.NormalId.Bottom;glow.Range=16;glow.Brightness=.3;glow.Shadows=false;glow.Color=Color3.fromRGB(255,227,180);glow.Parent=porchLamp
		end
	end
	for _,z in ipairs({594,636,678,720,762,804}) do
		part(apartment,"FullHeightBalconyPier",V(3.2,74,3.2),CF(181,49,z),Color3.fromRGB(226,221,202),Enum.Material.Plaster,false)
	end
	for _,y in ipairs({28,42,56,70,84}) do
		part(apartment,"RecessedStoreyBand",V(.5,.58,226),CF(181.2,y+11.9,705),C.white,Enum.Material.Plaster,false)
	end
	for level=2,4 do
		local y=level*14
		local z=699+(level%2)*18
		part(apartment,"ExposedStairLanding",V(21,.65,12),CF(158,y-.3,z),C.pale)
		part(apartment,"ExposedStairFlight",V(2.5,.55,25),CF(157,y+7,z+12)*CFrame.Angles(math.rad(-29),0,0),C.pale)
	end
	-- A closer, deeper balcony face frames the right of the arrival view.
	-- All of it is scenic; the enterable lane homes underneath remain intact.
	local nearWing=model("NearRightApartmentBalconies",S03)
	part(nearWing,"CreamWingCore",V(3,90,128),CF(96,45,795),Color3.fromRGB(213,213,197),Enum.Material.Plaster,false)
	for _,level in ipairs({2,3,4,5}) do
		local y=level*14
		for bay,z in ipairs({757,797,837}) do
			local zz=z+(level+bay)%2*3
			part(nearWing,"DeepBalconyShadow",V(.2,10,23),CF(94.3,y+5,zz),Color3.fromRGB(97,105,99),nil,false)
			part(nearWing,"DeepBalconyDeck",V(16,.55,26),CF(86,y-.28,zz),C.pale,nil,false)
			balconyRail(nearWing,77.8,y,zz,25)
			part(nearWing,"RecessedDoor",V(.18,8,5.5),CF(94.1,y+5,zz),C.dark,nil,false)
		end
	end
	local foreground=model("CloserVariedCottageFronts",S03)
	scenicCottageFront(foreground,"WestTwoStoreyClapboard",-62,835,28,27,Color3.fromRGB(174,178,161),Color3.fromRGB(73,79,72))
	scenicCottageFront(foreground,"EastLowGable",37,835,28,22,Color3.fromRGB(196,187,163),Color3.fromRGB(102,92,78))
	-- A projecting three-light bay interrupts the otherwise flat cottage row.
	-- It is scenic and sits ahead of the existing facade, never across a path.
	local bayFrame=CF(37,0,835)*yaw(180)
	local cottageBay=model("EastCottageProjectingBay",foreground)
	part(cottageBay,"BayWindowCanopy",V(10,.42,3.8),bayFrame*CF(7.2,11,-2),C.white,Enum.Material.Wood,false)
	part(cottageBay,"BayWindowSill",V(10,.34,3.3),bayFrame*CF(7.2,3.1,-2),C.white,Enum.Material.Wood,false)
	part(cottageBay,"BayWindowGlazing",V(9.1,7.5,.16),bayFrame*CF(7.2,7,-3.5),Color3.fromRGB(49,63,59),Enum.Material.Glass,false)
	for _,x in ipairs({2.55,5.65,8.75,11.85}) do
		part(cottageBay,"BayWindowMullion",V(.2,7.8,.24),bayFrame*CF(x,7,-3.61),C.white,nil,false)
	end
	for _,y in ipairs({3.25,7,10.75}) do
		part(cottageBay,"BayWindowCrossbar",V(9.4,.22,.24),bayFrame*CF(7.2,y,-3.61),C.white,nil,false)
	end
	local tower=model("SeparateManyWindowTower",S03)
	part(tower,"TowerCore",V(31,88,66),CF(-110,44,600),Color3.fromRGB(220,222,208),Enum.Material.Plaster,false)
	for level=0,10 do
		for j=0,6 do
			local z=574+j*8.5
			part(tower,"DarkTowerWindow",V(.2,5.8,5.3),CF(-93.8,5+level*7.6,z),Color3.fromRGB(53,65,65),Enum.Material.Glass,false)
			for _,edge in ipairs({-1,1}) do part(tower,"TowerWindowJamb",V(.2,6.1,.16),CF(-93.62,5+level*7.6,z+edge*2.72),C.white,nil,false) end
			part(tower,"TowerWindowSill",V(.28,.2,5.55),CF(-93.61,2+level*7.6,z),C.white,nil,false)
		end
		part(tower,"WhiteFloorBand",V(.35,.24,66),CF(-93.5,level*7.6+8,600),C.white,nil,false)
	end
	-- The arrival-facing end reads as separate apartment windows and cream
	-- piers, matching the side's residential facade rather than curtain glass.
	for level=0,10 do
		local y=5+level*7.6
		for bay=0,4 do
			part(tower,"FrontTowerWindow",V(4.25,5.45,.18),CF(-121+bay*5.5,y,633.18),Color3.fromRGB(53,65,65),Enum.Material.Glass,false)
		end
		part(tower,"FrontTowerFloorBand",V(29,.35,.26),CF(-110,y+3.28,633.35),C.white,nil,false)
	end
	for _,x in ipairs({-123.75,-118.25,-112.75,-107.25,-101.75,-96.25}) do
		part(tower,"FrontTowerPier",V(.32,83,.26),CF(x,44,633.35),C.white,nil,false)
	end
	-- Pull the separate window tower into the left background of the arrival
	-- composition. Its glazing and trim move together without changing routes.
	tower:PivotTo(tower:GetPivot()+V(10,0,150))
	-- At the distant end, staggered office facades replace a single blank cap.
	-- Their lower edges float above circulation and never bisect the gate route.
	local distant=model("LayeredFarResidentialClosure",S03)
	for _,info in ipairs({{-58,507,44,62},{39,493,48,70}}) do
		local x,z,w,h=info[1],info[2],info[3],info[4]
		part(distant,"PaleUpperMass",V(w,h,.7),CF(x,24+h/2,z),Color3.fromRGB(194,199,188),Enum.Material.Plaster,false)
		for row=0,5 do
			for col=0,3 do
				local wx=x-w/2+7+col*(w-14)/3
				part(distant,"DarkDistantWindow",V(5.2,6,.14),CF(wx,30+row*9.4,z+.45),Color3.fromRGB(59,69,68),Enum.Material.Glass,false)
			end
			part(distant,"ThinFloorBand",V(w+.5,.18,.2),CF(x,27+row*9.4,z+.52),C.white,nil,false)
		end
		for _,y in ipairs({42,61,80}) do
			part(distant,"DistantBalconyLedge",V(w*.72,.32,4),CF(x,y,z+2.2),Color3.fromRGB(218,219,204),nil,false)
			part(distant,"DistantBalconyRail",V(w*.72,.18,.2),CF(x,y+3.2,z+4.2),C.white,nil,false)
			for _,postX in ipairs({-w*.35,0,w*.35}) do part(distant,"DistantBalconyPost",V(.16,3,.16),CF(x+postX,y+1.6,z+4.2),C.white,nil,false) end
		end
	end
	for _,z in ipairs({552,688,824}) do part(S03,"HeavyCofferBeam",V(550,2.2,3.2),CF(0,96,z),C.pale,nil,false) end
	for _,x in ipairs({-130,0,130}) do part(S03,"LongCofferBeam",V(3.2,2.2,474),CF(x,96,696),C.pale,nil,false) end
	for _,x in ipairs({-70,70}) do
		for _,z in ipairs({610,745,879}) do
			part(S03,"SquareCeilingLight",V(8,.12,8),CF(x,99.42,z),Color3.fromRGB(224,223,210),Enum.Material.Neon,false)
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
	-- The photograph's planted cottage courts need leaf silhouettes at ground
	-- level. Crossed alpha cards give the beds depth without blocking the route.
	local planting=model("S03_CottageGardenCutouts",S03)
	local function plantCutout(name,texture,x,z,width,height,angle)
		local plant=model(name,planting)
		for plane=0,1 do
			local card=part(plant,"TransparentFoliagePlane",V(width,height,.12),CF(x,height/2,z)*yaw(angle+plane*90),C.white,Enum.Material.SmoothPlastic,false)
			card.Transparency=1;card.CanTouch=false;card.CanQuery=false;card.CastShadow=false
			for _,face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back}) do
				local decal=Instance.new("Decal")
				decal.Name="GeneratedFoliageCutout";decal.Face=face;decal.Texture=texture;decal.Parent=card
			end
		end
	end
	local hedgeTexture="rbxassetid://96127727672974"
	for i,site in ipairs({{-31,856,13,6,20},{28,850,13,6,20},{-49,842,11,5,37},{55,843,11,5,-15},{-37,780,12,5,8},{48,775,12,5,33}}) do
		plantCutout("CottageHedge_"..i,hedgeTexture,site[1],site[2],site[3],site[4],site[5])
	end
	plantCutout("BurgundyCourtyardMaple","rbxassetid://73750223479530",40,870,18,20,25)
	camera("VillageFourCourts",V(0,8,916),V(10,52,710))
	camera("VillageUpperCrossing",V(-101,19,696),V(135,35,838))
	camera("VillageBackCourt",V(171,6,881),V(220,49,840))
	for _,z in ipairs({462,535,610,682,719,790,870,930}) do point(0,3,z) end

	-- D has a real twelve-stud depression, raised domestic sidewalks and a
	-- cross-street at grade. Lower and upper circuits reconnect without jumping.
	local D=zone("D_FloralTerraces",V(-160,-14,936),V(160,320,1296))
	local S04=model("S04_MistyTowerCanyon",D)
	local terraceStone=Color3.fromRGB(167,164,145)
	local towerSlate=Color3.fromRGB(78,81,76)
	floor(D,"SunkenGreenCarpet",0,-12,1116,320,360,C.green)
	floor(D,"ArrivalAtGrade",0,0,942,320,12,C.carpet)
	floor(D,"DepartureAtGrade",0,0,1279,320,34,C.carpet)
	stairs(D,"DownToSunkenStreet",CF(0,0,948),22,-12,32,24,C.pink,true)
	stairs(D,"StreetExitStair",CF(0,-12,1230),22,12,32,24,C.pink,true)
	floor(D,"SunkenPinkRunner",0,-11.97,1105,16,250,C.pink)
	for _,s in ipairs({-1,1}) do
		floor(D,"RaisedPorchPromenade",s*128,0,1116,64,336,terraceStone)
		part(D,"TerraceRetainingWall",V(.8,12,336),CF(s*96,-6,1116),terraceStone)
		-- The exit street returns to full-width grade at1262: no fall edge
		-- remains there, so continuing the rail would block the offset gate route.
		K.edgeRail(D,s*96,0,948,1262,{{1097,1115}})
		for i,z in ipairs({994,1109,1214}) do
			local frame=CF(s*105,0,z)*yaw(s*90)
			local clapboard=i==1 and (s<0 and Color3.fromRGB(211,204,184) or Color3.fromRGB(132,130,115)) or (i%2==0 and Color3.fromRGB(183,181,165) or Color3.fromRGB(169,171,157))
			local nearHome=i==1
			local groundRoof=towerSlate
			if nearHome then groundRoof=nil end
			local home=house(S04,"FloralTowerHome_"..s.."_"..i.."_0",frame,30,26,13.8,clapboard,groundRoof,{open=true,backOpening=i==2,furniture=i==3 and (s<0 and 3 or 5) or nil})
			colorRoof(home,towerSlate);colorClapboard(home,clapboard)
			if nearHome then
				local upper=house(S04,"FloralTowerUpperHome_"..s.."_"..i,frame*CF(0,14,0),30,26,13.8,clapboard,towerSlate,{open=false})
				colorRoof(upper,towerSlate);colorClapboard(upper,clapboard)
			end
			-- Set the west arrival posts closer to the promenade rail so the
			-- ground route clears both posts without losing the white porch.
			if i~=2 then porch(S04,frame,30,6,towerSlate,s<0 and i==1 and 2 or nil) end
			if i==1 then K.registerWatcher(home,"FloralTerraceWindow_"..s,D.Name) end
		end
		for i,z in ipairs({1045,1170}) do
			local frame=CF(s*48,-12,z)*yaw(s*90)
			local lower=house(S04,"LowerFloralHome_"..s.."_"..i,frame,28,26,13.8,Color3.fromRGB(166,162,144),nil,{open=true})
			local upper=house(S04,"UpperFloralHome_"..s.."_"..i,frame*CF(0,14,0),28,26,13.8,Color3.fromRGB(177,173,157),Color3.fromRGB(67,73,70),{open=false})
			colorClapboard(lower,Color3.fromRGB(166,162,144));colorClapboard(upper,Color3.fromRGB(177,173,157))
			colorRoof(upper,Color3.fromRGB(67,73,70))
			porch(S04,frame,28,7,Color3.fromRGB(76,80,76))
		end
		for i,z in ipairs({1032,1158,1250}) do
			local p=part(D,"FloralPaperWallPanel",V(.06,34,34),CF(s*159.33,28,z),C.pale,nil,false)
			K.material(p,"Wallpaper")
		end
	end
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({1004,1220}) do
			local roofTint=Color3.fromRGB(87,88,82)
			local pocketClapboard=i==1 and (side<0 and Color3.fromRGB(132,130,115) or Color3.fromRGB(211,204,184)) or C.rose
			local home=house(D,"SunkenPocketStack_"..side.."_"..i.."_0",CF(side*26,-12,z)*yaw(side*90),26,24,13.8,pocketClapboard,roofTint,{open=true})
			colorRoof(home,roofTint)
			colorClapboard(home,pocketClapboard)
		end
	end
	-- Tall, restrained shafts sit behind the gabled street houses. The small
	-- asymmetric balcony banks and vertical windows have a different facade
	-- language from S03's broad, bright apartment landings.
	for _,side in ipairs({-1,1}) do
		local tower=model(side<0 and "WestRecessedTower" or "EastRecessedTower",S04)
		local outer=side*151
		for tier=0,5 do
			local tone=Color3.fromRGB(224,214,192):Lerp(Color3.fromRGB(193,192,181),tier/5*.82)
			local shaft=part(tower,"PaleTowerShaft",V(8,47.6,324),CF(outer,11.75+tier*47.5,1116),tone,Enum.Material.Plaster)
			shaft.Transparency=tier>=4 and (tier-3)*.08 or 0
		end
		for _,z in ipairs({981,1063,1145,1227}) do
			part(tower,"VerticalConcretePier",V(4,285,3),CF(side*141,130.5,z),Color3.fromRGB(228,218,195),Enum.Material.Plaster)
		end
		for level=1,19 do
			local y=level*14
			local haze=math.clamp((level-1)/18*.82,0,.82)
			local tone=Color3.fromRGB(225,214,191):Lerp(Color3.fromRGB(191,191,180),haze)
			for bay,z in ipairs({1025,1115,1205}) do
				local offsetZ=(side<0 and bay%2 or (bay+1)%2)*7
				local narrow=bay==2 and 17 or 20
				local deckX=side*(138-(bay==2 and 2 or 0)-(level%3==0 and 1 or 0))
				part(tower,"InsetBalconyShadow",V(.25,10,narrow),CF(side*146,y+6,z+offsetZ),Color3.fromRGB(117,121,112):Lerp(tone,.42),nil,false)
				local deck=part(tower,"OffsetBalconyDeck",V(10,.55,narrow+2),CF(deckX,y-.3,z+offsetZ),tone,nil,level<=12)
				deck.Transparency=level>12 and (level-12)/7*.24 or 0
				-- The upper balconies dissolve into the mist. Full sash trim on
				-- every distant storey adds thousands of invisible tiny instances.
				if level<=9 then
					part(tower,"BalconyRecessDoor",V(.2,7.6,5.6),CF(side*145.7,y+5,z+offsetZ-5.5),Color3.fromRGB(66,76,72):Lerp(tone,haze*.38),Enum.Material.Glass,false)
					part(tower,"BalconyRecessWindow",V(.2,7.6,5.6),CF(side*145.7,y+5,z+offsetZ+5.5),Color3.fromRGB(66,76,72):Lerp(tone,haze*.38),Enum.Material.Glass,false)
					for _,windowZ in ipairs({z+offsetZ-5.5,z+offsetZ+5.5}) do
						for _,edge in ipairs({-1,1}) do
							part(tower,"BalconyOpeningJamb",V(.26,8,.23),CF(side*145.45,y+5,windowZ+edge*2.9),C.white,nil,false)
						end
						part(tower,"BalconyOpeningHeader",V(.3,.26,6),CF(side*145.45,y+9,windowZ),C.white,nil,false)
					end
				end
				local railX=deckX-side*5.2
				if level<=8 then
					balconyRail(tower,railX,y,z+offsetZ,narrow+1)
				else
					part(tower,"HazyUpperRail",V(.2,.23,narrow+1),CF(railX,y+3.3,z+offsetZ),tone,nil,false)
					if level<13 then
						for post=0,4 do part(tower,"HazyUpperPost",V(.15,3,.15),CF(railX,y+1.8,z+offsetZ-narrow/2+narrow*post/4),tone,nil,false) end
					end
				end
				if level<=9 and level%2==1 then
					local warm=part(tower,"BalconyUndersideLamp",V(2.4,.14,2.4),CF(deckX,y-.67,z+offsetZ),Color3.fromRGB(248,226,176),Enum.Material.Neon,false)
					local glow=Instance.new("SurfaceLight");glow.Face=Enum.NormalId.Bottom;glow.Range=14;glow.Brightness=.22;glow.Shadows=false;glow.Color=Color3.fromRGB(255,226,181);glow.Parent=warm
				end
			end
			for _,z in ipairs({993,1073,1163,1250}) do
				part(tower,"NarrowVerticalWindow",V(.2,8.4,3.2),CF(side*146,y+4.5,z),Color3.fromRGB(51,61,59):Lerp(tone,haze),Enum.Material.Glass,false)
				if level<=8 then
					for _,edge in ipairs({-1,1}) do
						part(tower,"NarrowWindowJamb",V(.25,8.8,.18),CF(side*145.78,y+4.5,z+edge*1.66),C.white,nil,false)
					end
					part(tower,"NarrowWindowSill",V(.32,.21,3.6),CF(side*145.76,y+.2,z),C.white,nil,false)
				end
			end
		end
	end
	-- A separate middle-distance facade makes the towers recede behind the
	-- porch roofs instead of reading as one flat pair of parallel walls.
	-- It starts well above all playable streets and is entirely scenic.
	local middleTower=model("MistyMiddleDistanceResidence",S04)
	local middleFace=part(middleTower,"CreamResidenceCore",V(42,302,2.4),CF(-70,139,1125),Color3.fromRGB(204,199,183),Enum.Material.Plaster,false)
	middleFace.MaterialVariant=""
	for _,x in ipairs({-91,-49}) do
		local pier=part(middleTower,"FullHeightCornerPier",V(2,302,9),CF(x,139,1120),Color3.fromRGB(218,212,194),Enum.Material.Plaster,false)
		pier.MaterialVariant=""
	end
	for level=0,14 do
		local y=60+level*14
		local fade=level/14*.55
		for _,x in ipairs({-80,-60}) do
			part(middleTower,"RecessedResidenceWindow",V(7.4,8,.18),CF(x,y,1123.6),
				Color3.fromRGB(57,68,67):Lerp(Color3.fromRGB(143,146,137),fade),Enum.Material.Glass,false)
		end
		part(middleTower,"ProjectingWhiteBalcony",V(37,.38,5),CF(-70,y-4.4,1121),C.pale,Enum.Material.Plaster,false)
		part(middleTower,"BalconyFrontRail",V(37,.25,.2),CF(-70,y-1.2,1118.4),C.white,nil,false)
		if level%3==0 then
			for _,x in ipairs({-87,-70,-53}) do
				part(middleTower,"BalconyWhitePost",V(.2,3.1,.2),CF(x,y-2.8,1118.4),C.white,nil,false)
			end
		end
	end
	for _,spec in ipairs({{1180,.88},{1238,.77}}) do
		local veil=part(S04,"MistyTowerDepthVeil",V(240,274,.12),CF(0,168,spec[1]),Color3.fromRGB(166,160,151),Enum.Material.SmoothPlastic,false)
		veil.Transparency=spec[2]
	end
	-- A second, more distant bank fills the otherwise blank end of the canyon.
	-- It begins above the exit stair and has no collidable pieces or ground mass.
	local rearTowers=model("MistyRearTowerLayers",S04)
	for _,side in ipairs({-1,1}) do
		part(rearTowers,"RecedingCreamShaft",V(4,300,36),CF(side*77,150,1248),Color3.fromRGB(211,205,188),Enum.Material.Plaster,false)
		for level=0,18 do
			local y=35+level*13
			local z=level%2==0 and 1239 or 1256
			local fade=level/18*.78
			local ledge=Color3.fromRGB(225,216,192):Lerp(Color3.fromRGB(188,189,178),fade)
			part(rearTowers,"RecedingBalconyDeck",V(12,.42,15),CF(side*71,y-.25,z),ledge,nil,false)
			balconyRail(rearTowers,side*64.8,y,z,14)
			part(rearTowers,"MistyDoorRecess",V(.15,7,4),CF(side*74.8,y+4,z),Color3.fromRGB(80,92,89):Lerp(ledge,fade),Enum.Material.Glass,false)
		end
	end
	local farFace=model("MistyFarApartmentClosure",S04)
	for _,info in ipairs({{-61,34},{-8,40},{49,36}}) do
		local x,w=info[1],info[2]
		part(farFace,"FarPlasterFacade",V(w,264,.55),CF(x,144,1289),Color3.fromRGB(213,207,190),Enum.Material.Plaster,false)
		for level=0,19 do
			local y=19+level*13.2
			local mist=level/19*.72
			for _,side in ipairs({-1,1}) do
				part(farFace,"FadingStackWindow",V(6,7.5,.13),CF(x+side*w*.23,y,1288.6),Color3.fromRGB(56,67,66):Lerp(Color3.fromRGB(169,174,164),mist),Enum.Material.Glass,false)
				if level<=8 then part(farFace,"FadingWindowSill",V(6.5,.2,.24),CF(x+side*w*.23,y-3.86,1288.48),C.white,nil,false) end
			end
			if level%3==1 then
				part(farFace,"FarBalconyBand",V(w*.82,.35,3.6),CF(x,y-4,1287.5),Color3.fromRGB(224,220,202),nil,false)
				part(farFace,"FarBalconyRail",V(w*.82,.22,.18),CF(x,y-.8,1285.7),C.white,nil,false)
			end
		end
	end
	house(D,"SunkenCornerResidence",CF(0,-12,1132),36,24,13.8,Color3.fromRGB(180,177,160),towerSlate,{open=true,completeHome=true,furniture=8})
	floor(D,"RaisedCrossStreet",0,0,1106,320,18,terraceStone)
	for _,z in ipairs({1097,1115}) do
		rail(D,CF(0,0,z),146)
		-- The outer promenades are already at this same height on both sides.
		-- Only the central sunken street needs a fall barrier; outer rails would
		-- bisect actual homes and prevent reaching the cross-street at grade.
	end
	-- Guard the twelve-stud drop at both grade changes; the central stair
	-- opening stays clear at x=-11..11, and the side rails join the terrace lips.
	for _,z in ipairs({948,1262}) do
		for _,s in ipairs({-1,1}) do rail(D,CF(s*53.5,0,z),85) end
	end
	stairs(D,"SunkenWestReturn",CF(-86,-12,1057),14,12,32,24,C.pink,true)
	floor(D,"SunkenWestLanding",-86,0,1094,18,10,C.pink)
	stairs(D,"SunkenEastReturn",CF(86,-12,1158)*yaw(180),14,12,32,24,C.pink,true)
	floor(D,"SunkenEastLanding",86,0,1121,18,12,C.pink)
	camera("FloralSunkenArrival",V(9,5,943),V(-73,66,1108))
	camera("FloralLowerStreet",V(-15,-6,1031),V(90,37,1195))
	camera("FloralHighPorches",V(-93,6,1130),V(116,32,1212))
	point(0,3,941);point(0,2.5,948);point(0,-9,980);point(0,-9,1040);point(0,-9,1112);point(0,-9,1175);point(0,-9,1230);point(0,3,1264);point(0,3,1290)

	-- E: several real rooms deep. Side routes return behind the houses, while
	-- a succession of through-houses forms an understandable central passage.
	local E=zone("E_DomesticLabyrinth",V(-160,0,1296),V(160,44,1596))
	local S10=model("S10_EmptyBalconyRoom",E)
	local warmBroadloom=Color3.fromRGB(174,163,143)
	local warmPlaster=Color3.fromRGB(211,203,185)
	local broadloom=floor(E,"DomesticBroadloom",0,0,1446,320,300,warmBroadloom)
	-- The carpet variant normally resets its tint toward white. Give this
	-- district the subdued warm-beige broadloom visible in the reference.
	broadloom.MaterialVariant="";broadloom.Material=Enum.Material.Fabric;broadloom.Color=warmBroadloom
	for _,s in ipairs({-1,1}) do
		-- These two real ground rooms retain the existing supported Window
		-- Watcher panes; the repeated side-room array no longer hides the void.
		local homeX=s<0 and -54 or 88
		local home=house(E,"DomesticRoom_"..s.."_1_1",CF(homeX,0,1340)*yaw(s*90),36,28,13.8,C.cream,nil,{open=true,backOpening=true})
		K.registerWatcher(home,"DomesticWindow_"..s,E.Name)
		-- Leave the upper balcony shaft visible beside S10's three windows.
		local ceilingStart=s<0 and 1296 or 1390
		local ceilingLength=1596-ceilingStart
		part(E,"LowRoomCeilingBand",V(114,.6,ceilingLength),CF(s*103,16,ceilingStart+ceilingLength/2),C.ceiling)
	end
	for i,z in ipairs({1460,1540}) do
		house(E,"NestedThroughHouse_"..i.."_0",CF(0,0,z),66,28,13.8,C.cream,nil,{open=true,backOpening=true})
	end
	-- The gate-five clock candidate stays a true enterable home beyond the
	-- sparse front room, with the original HousePuzzleCandidate attributes.
	house(E,"LabyrinthEndResidence_2_0",CF(0,0,1570),44,20,13.8,C.pale,nil,{open=true,completeHome=true,furniture=7})
	for _,z in ipairs({1415,1505,1580}) do
		local p=part(E,"SharedLowDomesticPanel",V(6,.15,3),CF(0,15,z),Color3.fromRGB(211,216,188),Enum.Material.Neon,false)
		p:SetAttribute("TubeState","Dim")
		local l=Instance.new("SurfaceLight");l.Face=Enum.NormalId.Bottom;l.Range=26;l.Angle=150;l.Brightness=.45;l.Shadows=false;l.Parent=p
	end
	-- The first view is a low, broad carpeted room with a six-panel door and
	-- a separate 18-stud right passage. Its left windows look across a sealed
	-- shaft toward actual stacked railings; the glass prevents a fall.
	local roomCarpet=part(S10,"ContinuousRoomCarpet",V(72,.34,83),CF(0,.06,1348),warmBroadloom,Enum.Material.Fabric)
	roomCarpet.MaterialVariant="";roomCarpet.Material=Enum.Material.Fabric;roomCarpet.Color=warmBroadloom
	part(S10,"RightRoomWall",V(.7,16,83),CF(-36,8,1348),warmPlaster,Enum.Material.Plaster)
	part(S10,"LeftWindowApron",V(.7,3.4,83),CF(36,1.7,1348),warmPlaster,Enum.Material.Plaster)
	part(S10,"LeftWindowHeader",V(.7,3.4,83),CF(36,14.3,1348),warmPlaster,Enum.Material.Plaster)
	for _,span in ipairs({{1306.5,1319},{1333,1339},{1353,1359},{1373,1389.5}}) do
		part(S10,"LeftWindowPier",V(.7,9.2,span[2]-span[1]),CF(36,8,(span[1]+span[2])/2),warmPlaster,Enum.Material.Plaster)
	end
	for _,z in ipairs({1326,1346,1366}) do
		local glass=part(S10,"InteriorAtriumWindowGlass",V(.15,9.2,14),CF(35.5,8,z),Color3.fromRGB(70,81,79),Enum.Material.Glass)
		glass.Transparency=.66
		for _,y in ipairs({3.4,8,12.6}) do part(S10,"WindowCrossbar",V(.3,.17,14.5),CF(35.25,y,z),C.white,nil,false) end
		for _,zz in ipairs({z-7.1,z+7.1}) do part(S10,"WindowJamb",V(.3,9.6,.22),CF(35.25,8,zz),C.white,nil,false) end
		part(S10,"WindowCentreMullion",V(.3,9.2,.2),CF(35.25,8,z),C.white,nil,false)
	end
	-- The return is a shallow, nonblocking visual bay: two front-facing tall
	-- windows remain legible from arrival while the central x=0 line stays free.
	local windowReturn=model("S10_TwoTallWindowReturn",S10)
	part(windowReturn,"LowPlasterApron",V(24,3.4,.48),CF(24,1.7,1332),C.cream,Enum.Material.Plaster,false)
	part(windowReturn,"HighPlasterHeader",V(24,3.4,.48),CF(24,14.3,1332),C.cream,Enum.Material.Plaster,false)
	for _,span in ipairs({{12,13.55},{20.05,25.95},{32.45,36}}) do
		part(windowReturn,"PlasterWindowPier",V(span[2]-span[1],9.2,.48),CF((span[1]+span[2])/2,8,1332),C.cream,Enum.Material.Plaster,false)
	end
	for _,wx in ipairs({16.8,29.2}) do
		local pane=part(windowReturn,"TallReturnWindowGlass",V(6.5,9.2,.12),CF(wx,8,1331.69),Color3.fromRGB(63,77,77),Enum.Material.Glass,false)
		pane.Transparency=.34
		for _,edge in ipairs({-1,1}) do part(windowReturn,"TallReturnJamb",V(.27,9.6,.2),CF(wx+edge*3.32,8,1331.55),C.white,nil,false) end
		for _,y in ipairs({3.35,8,12.65}) do part(windowReturn,"TallReturnCrossbar",V(6.8,.2,.2),CF(wx,y,1331.55),C.white,nil,false) end
		part(windowReturn,"TallReturnMullion",V(.18,9.5,.2),CF(wx,8,1331.53),C.white,nil,false)
	end
	part(S10,"BroadPortalHeader",V(76,1.4,.85),CF(0,15.3,1306.5),C.white,Enum.Material.Plaster)
	for _,s in ipairs({-1,1}) do part(S10,"BroadPortalJamb",V(.85,16,.85),CF(s*36.6,8,1306.5),C.white,Enum.Material.Plaster) end
	part(S10,"CentralPartitionLeft",V(32.2,16,.7),CF(19.9,8,1358),warmPlaster,Enum.Material.Plaster)
	part(S10,"CentralPartitionRight",V(14.2,16,.7),CF(-10.9,8,1358),warmPlaster,Enum.Material.Plaster)
	for _,span in ipairs({{19.9,32.2},{-10.9,14.2}}) do
		part(S10,"CentralPartitionBaseboard",V(span[2],.52,.2),CF(span[1],.26,1357.52),C.white,nil,false)
		part(S10,"CentralPartitionCrown",V(span[2],.38,.38),CF(span[1],15.7,1357.5),C.white,nil,false)
	end
	part(S10,"RoomSideBaseboard",V(.28,.58,83),CF(-35.48,.29,1348),C.white,nil,false)
	part(S10,"RoomSideCrown",V(.44,.38,83),CF(-35.44,15.65,1348),C.white,nil,false)
	part(S10,"CentralSixPanelDoor",V(7.6,10,.35),CF(0,5,1357.6),C.white,Enum.Material.Wood)
	for _,s in ipairs({-1,1}) do
		for _,row in ipairs({1,2,3}) do
			local y=row==1 and 1.8 or row==2 and 5.3 or 8.2
			local h=row==2 and 2.9 or 1.55
			part(S10,"RaisedDoorPanel",V(2.4,h,.12),CF(s*1.75,y,1357.34),Color3.fromRGB(224,222,210),Enum.Material.Wood,false)
		end
	end
	local knob=part(S10,"BrassDoorKnob",V(.35,.35,.35),CF(2.7,4.9,1357.1),Color3.fromRGB(147,130,80),Enum.Material.Metal,false)
	knob.Shape=Enum.PartType.Ball
	part(S10,"DoorFrameHeader",V(8.6,.42,.65),CF(0,10.2,1357.3),C.white)
	for _,s in ipairs({-1,1}) do part(S10,"DoorFrameJamb",V(.45,10.2,.65),CF(s*4,5.1,1357.3),C.white) end
	part(S10,"PassageHeader",V(18,5.4,.75),CF(-27,13.3,1358),warmPlaster,Enum.Material.Plaster)
	for _,x in ipairs({-18.3,-35.7}) do part(S10,"PassageJamb",V(.45,10.7,.75),CF(x,5.35,1358),C.white) end
	part(S10,"LowSuspendedCeiling",V(72,.45,83),CF(0,16.2,1348),C.ceiling,Enum.Material.Plaster)
	-- The low ceiling joins the side bands at x=46. These strips remove the
	-- accidental high atrium slit above the domestic room's window wall.
	for _,s in ipairs({-1,1}) do
		part(S10,"WindowWallCeilingReturn",V(10,.45,83),CF(s*41,16.2,1348),C.ceiling,Enum.Material.Plaster,false)
	end
	for _,z in ipairs({1321,1343,1365,1382}) do part(S10,"CeilingGridCrossbeam",V(72,.13,.15),CF(0,15.9,z),C.white,nil,false) end
	for _,x in ipairs({-18,0,18}) do part(S10,"CeilingGridLongBeam",V(.15,.13,83),CF(x,15.9,1348),C.white,nil,false) end
	for _,z in ipairs({1324,1347,1372}) do
		local lamp=part(S10,"LongFluorescentPanel",V(18,.16,3.2),CF(0,15.85,z),Color3.fromRGB(224,226,214),Enum.Material.Neon,false)
		local light=Instance.new("SurfaceLight");light.Face=Enum.NormalId.Bottom;light.Range=24;light.Brightness=.72;light.Shadows=false;light.Parent=lamp
	end
	local balconies=model("ContainedOppositeBalconies",S10)
	-- Begin the shaft behind the arrival crossing so the route from gate four
	-- reaches the room portal before the first window starts at z=1319.
	part(balconies,"DarkShaftBacking",V(1,43,69.5),CF(119,21.5,1354.75),Color3.fromRGB(53,58,55),Enum.Material.Plaster)
	part(balconies,"DarkShaftFloor",V(82,.12,69.5),CF(77,.07,1354.75),Color3.fromRGB(45,48,44),Enum.Material.SmoothPlastic,false)
	for level=0,2 do
		local y=level*14
		for _,z in ipairs({1327,1354,1380}) do
			part(balconies,"OppositeBalconyDeck",V(10,.55,23),CF(61,y-.3,z),C.pale)
			balconyRail(balconies,55.8,y,z,22)
			part(balconies,"ShadowDoor",V(.15,9,6),CF(77,y+5,z),C.dark,nil,false)
		end
	end
	camera("DomesticRoomArrival",V(0,6,1299),V(-3,7,1367))
	camera("DomesticBackLoop",V(-94,6,1398),V(-90,8,1519))
	camera("DomesticNestedCeiling",V(0,6,1510),V(-13,28,1550))
	point(0,3,1302);point(0,3,1347);point(-27,3,1354);point(-27,3,1366)
	for _,z in ipairs({1399,1440,1461,1489}) do point(0,3,z) end
	point(-45,3,1518);point(-45,3,1560);point(-45,3,1590);point(-120,3,1590)
	return {PreviewCameras=cameras,Waypoints=waypoints,Zones=zones}
end
return Districts
