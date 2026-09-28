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
	local function balconyRail(into,front,y,z,width,intervals)
		part(into,"WhiteBalconyTopRail",V(.2,.25,width),CF(front,y+3.4,z),C.white,nil,false)
		part(into,"WhiteBalconyBottomRail",V(.2,.18,width),CF(front,y+.5,z),C.white,nil,false)
		local count=intervals or math.ceil(width/4)
		for j=0,count do
			part(into,"WhiteBalconySpindle",V(.16,2.9,.16),CF(front,y+1.9,z-width/2+width*j/count),C.white,nil,false)
		end
	end
	local function referenceCottage(home,frame,width,depth,height,siding,roofTint,upperStorey)
		-- Dress the actual enterable room rather than covering it with the gallery
		-- builder's solid HouseCore. The original two standard panes, doorway,
		-- floor, clue marker and supporting-house references remain untouched.
		local added=0
		local function detail(name,size,localFrame,color,material,collide)
			added+=1
			return part(home,name,size,frame*localFrame,color,material,collide)
		end
		local floorFrame=home:GetAttribute("HouseFloorFrame")
		assert(typeof(floorFrame)=="CFrame","Reference cottage needs a room frame")
		local clapboard=game:GetService("MaterialService"):FindFirstChild("Level5CourtyardClapboard")
		local exterior={SideWall=true,BackWall=true,BackWallWing=true,BackWallHeader=true,FacadeLintel=true,WindowApron=true,FacadePier=true,GableBaseBand=true,ClosedGableTriangle=true}
		local panes={}
		for _,item in ipairs(home:GetChildren()) do
			if item:IsA("BasePart") and item.Name=="WindowGlass" then table.insert(panes,item) end
			if item:IsA("BasePart") and exterior[item.Name] then
				item.Material=Enum.Material.WoodPlanks
				if clapboard and clapboard:IsA("MaterialVariant") then item.MaterialVariant=clapboard.Name end
				item.Color=siding
			end
		end
		assert(#panes==2,"Reference cottage needs two existing standard panes: "..home.Name)
		for _,pane in ipairs(panes) do
			local localPane=floorFrame:ToObjectSpace(pane.CFrame)
			for _,edge in ipairs({-1,1}) do
				detail("ReferenceWindowShutter",V(.68,7.7,.2),CF(localPane.Position.X+edge*(pane.Size.X/2+.48),localPane.Position.Y,-.52),siding:Lerp(C.dark,.38),Enum.Material.Wood,false)
			end
		end
		local upperHeight=12
		if upperStorey then
			-- Move this house's existing pitched roof; no second roof is layered on
			-- the old one. These scenic upper rooms sit over real ground interiors.
			local roofPieces={GableBaseBand=true,PitchedRoof=true,RoofCladdingSeam=true,WhiteGableTrim=true,ClosedGableTriangle=true,RoofRidge=true}
			for _,item in ipairs(home:GetChildren()) do
				if item:IsA("BasePart") and roofPieces[item.Name] then item.CFrame+=V(0,upperHeight,0) end
			end
			for _,shape in ipairs({
				{"ReferenceUpperFront",V(width,upperHeight,.65),CF(0,height+upperHeight/2,0)},
				{"ReferenceUpperSide",V(.65,upperHeight,depth),CF(-width/2,height+upperHeight/2,depth/2)},
				{"ReferenceUpperSide",V(.65,upperHeight,depth),CF(width/2,height+upperHeight/2,depth/2)},
				{"ReferenceUpperBack",V(width,upperHeight,.65),CF(0,height+upperHeight/2,depth)},
			}) do
				local wall=detail(shape[1],shape[2],shape[3],siding,Enum.Material.WoodPlanks,true)
				if clapboard and clapboard:IsA("MaterialVariant") then wall.MaterialVariant=clapboard.Name end
				wall.Color=siding -- retain the clapboard tint with its MaterialVariant
			end
			for _,side in ipairs({-1,1}) do
				local x=side*width*.25
				local y=height+upperHeight*.56
				detail("ReferenceUpperWindow",V(5.1,5.7,.16),CF(x,y,-.43),C.dark,Enum.Material.Glass,false)
				detail("ReferenceUpperMullion",V(.17,5.7,.2),CF(x,y,-.55),C.white,nil,false)
				detail("ReferenceUpperCrossbar",V(5.1,.17,.2),CF(x,y,-.55),C.white,nil,false)
				detail("ReferenceUpperSill",V(5.7,.27,.5),CF(x,y-3,-.5),C.white,nil,false)
			end
			for _,y in ipairs({height+2.1,height+10.2}) do
				detail("ReferenceSidingReveal",V(width,.09,.12),CF(0,y,-.39),siding:Lerp(C.dark,.2),nil,false)
			end
		end
		local gableY=height+(upperStorey and upperHeight or 0)+width*.18
		detail("ReferenceGableWindowFrame",V(3.55,3.25,.16),CF(0,gableY,-.55),C.white,nil,false)
		detail("ReferenceGableWindow",V(2.8,2.5,.18),CF(0,gableY,-.68),C.dark,Enum.Material.Glass,false)
		detail("ReferenceGableMullion",V(.16,2.5,.2),CF(0,gableY,-.8),C.white,nil,false)
		-- Keep the entrance at ground level and leave the middle of the porch
		-- open so the three clue interiors remain reachable without a step.
		detail("ReferencePorchDeck",V(width+.4,.16,4.5),CF(0,.08,-2.25),C.pale,Enum.Material.WoodPlanks,false)
		local canopy=detail("ReferencePorchCanopy",V(width+1,.42,5.5),CF(0,11.65,-2.75)*CFrame.Angles(math.rad(-6),0,0),roofTint,Enum.Material.Slate,false)
		canopy.MaterialVariant="";canopy.Color=roofTint
		detail("ReferencePorchFascia",V(width+1,.58,.3),CF(0,11.25,-5.35),C.white,nil,false)
		local railWidth=width/2-4.6
		for _,side in ipairs({-1,1}) do
			detail("ReferencePorchColumn",V(.75,10.9,.75),CF(side*(width/2-1),5.45,-4.65),C.white,nil,true)
			detail("ReferencePorchRail",V(railWidth,.25,.22),CF(side*(4.6+railWidth/2),3.15,-4.65),C.white,nil,false)
			if upperStorey then
				for _,j in ipairs({1,2}) do
					detail("ReferencePorchBaluster",V(.18,2.8,.18),CF(side*(4.6+j*railWidth/3),1.65,-4.65),C.white,nil,false)
				end
			end
		end
		home:SetAttribute("S03ReferenceFacade",true)
		home:SetAttribute("S03ScenicUpperStorey",upperStorey==true)
		return added
	end
	local Czone=zone("C_PastelVillage",V(-280,0,456),V(280,100,936))
	local S03=model("S03_BrightCottageAtrium",Czone)
	local foregroundTrim=model("ForegroundCourtWindowDetails",S03)
	local foregroundHomes,foregroundParts=0,0
	local function dressForegroundCourt(frame,width,depth,innerSide)
		-- The nearest cottage backs and inner side walls face the S03 arrival
		-- camera. Add window rhythm outside those solid walls without altering
		-- any room, clue surface, door, floor or Watcher glass.
		local function detail(name,size,pose,color,material)
			foregroundParts+=1
			return part(foregroundTrim,name,size,pose,color,material,false)
		end
		local function window(pose,w,h)
			detail("CourtRearWindow",V(w,h,.16),pose,Color3.fromRGB(56,69,68),Enum.Material.SmoothPlastic)
			for _,side in ipairs({-1,1}) do
				detail("CourtRearWindowJamb",V(.23,h+.3,.25),pose*CF(side*(w/2+.08),0,.13),C.white,nil)
			end
			for _,side in ipairs({-1,1}) do
				detail("CourtRearWindowCrosspiece",V(w+.42,.23,.25),pose*CF(0,side*(h/2+.08),.13),C.white,nil)
			end
			detail("CourtRearWindowMullion",V(.15,h,.24),pose*CF(0,0,.14),C.white,nil)
			detail("CourtRearWindowCrosspiece",V(w,.14,.24),pose*CF(0,0,.14),C.white,nil)
		end
		for _,y in ipairs({6.55,20.4}) do
			for _,x in ipairs({-width*.24,width*.24}) do
				window(frame*CF(x,y,depth+.48),5.1,5.8)
			end
		end
		detail("CourtRearStoreyBand",V(width,.3,.26),frame*CF(0,13.95,depth+.5),C.white,nil)
		local gableY=13.8+12+width*.18
		detail("CourtRearGableFrame",V(3.5,3.1,.16),frame*CF(0,gableY,depth+.53),C.white,nil)
		detail("CourtRearGableWindow",V(2.75,2.35,.18),frame*CF(0,gableY,depth+.65),Color3.fromRGB(56,69,68),Enum.Material.SmoothPlastic)
		detail("CourtRearGableMullion",V(.16,2.35,.22),frame*CF(0,gableY,depth+.79),C.white,nil)
		if innerSide then
			for _,y in ipairs({6.55,20.4}) do
				for _,z in ipairs({8,18}) do
					window(frame*CF(innerSide*(width/2+.48),y,z)*yaw(innerSide*90),5.1,5.8)
				end
			end
			detail("CourtSideStoreyBand",V(depth,.3,.26),frame*CF(innerSide*(width/2+.5),13.95,depth/2)*yaw(innerSide*90),C.white,nil)
		end
		foregroundHomes+=1
	end
	local referenceHomes,referenceParts=0,0
	local function dressReferenceHome(home,frame,width,depth,height,siding,roofTint,upperStorey)
		referenceHomes+=1
		referenceParts+=referenceCottage(home,frame,width,depth,height,siding,roofTint,upperStorey)
	end
	floor(Czone,"GreenCarpetNeighbourhood",0,0,696,560,480,C.green)
	-- Pale stepping stones bend between the offset section gates. The
	-- continuous lawn underneath remains the walkable floor and keeps the
	-- courtyard open instead of reading as one long asphalt strip.
	local steppingSites={
		{60,462,30,8},{34,473,26,8},
		{26,480},{19,508},{10,536},{3,564},{-2,592},{4,620},{0,648},{-3,676},
		{4,704},{-4,732},{0,760},{5,788},{0,816},{-6,844},{-12,872},{-16,900},{-30,928},
		{-50,930,34,8},{-80,932,30,8},{-110,932,30,8},
	}
	assert(#steppingSites==22,"S03 garden path changed its instance budget")
	for _,site in ipairs(steppingSites) do
		part(Czone,"GardenSteppingWalk",V(site[3] or 9,.08,site[4] or 18),CF(site[1],.09,site[2]),Color3.fromRGB(211,207,192),Enum.Material.Concrete,false)
	end
	local colors={Color3.fromRGB(212,207,190),Color3.fromRGB(194,205,187),Color3.fromRGB(203,190,171),Color3.fromRGB(218,211,193)}
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
			dressReferenceHome(home,frame,width,25,13.8,colors[(court+i-2)%4+1],roofTint,court>=3)
			if court>=3 and (i==2 or i==4) then
				dressForegroundCourt(frame,width,25,i==2 and (court==3 and 1 or -1) or nil)
			end
			if i==1 then K.registerWatcher(home,"VillageCourtWindow_"..court,Czone.Name) end
			floor(cluster,"PorchThreshold",0,0,-3,28,6,C.pink,frame)
		end
		local side=cx<0 and -1 or 1
		floor(cluster,"CourtConnectingCarpet",side*66,.045,cz,132,13,C.carpet)
	end
	assert(foregroundHomes==4 and foregroundParts==186,"S03 near-court facade inventory changed")
	foregroundTrim:SetAttribute("DetailedHouseCount",foregroundHomes)
	foregroundTrim:SetAttribute("WindowTrimParts",foregroundParts)
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({650,715,765}) do
			local frame=CF(side*120,0,z)*yaw(side*90)
			local roofTint=Color3.fromRGB(100,106,97)
			local home=house(Czone,"CrossStreetCottage_"..side.."_"..i.."_0",frame,28,26,13.8,colors[(i+(side+1)/2)%4+1],roofTint,{open=true})
			colorRoof(home,roofTint)
			colorClapboard(home,colors[(i+(side+1)/2)%4+1])
			dressReferenceHome(home,frame,28,26,13.8,colors[(i+(side+1)/2)%4+1],roofTint,false)
		end
	end
	-- Short residential lanes occupy the spaces between the four courts. Their
	-- doors, rooflines and asymmetric heights read as houses at walking scale.
	local arrivalCottageParts=0
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({615,675,745,805}) do
			-- The unfurnished east home becomes the near two-storey cottage.
			-- Its doorway still opens toward the lawn, and the central route stays
			-- clear between it and the west lane house.
			local foregroundRight=i==4 and side>0
			local frame=foregroundRight and CF(38,0,890)*yaw(180)
				or CF(side*(i==4 and 30 or 50),0,z)*yaw(side*(i==4 and 155 or 90))
			local roofTint=foregroundRight and Color3.fromRGB(76,91,78) or Color3.fromRGB(104,107,99)
			local siding=foregroundRight and Color3.fromRGB(236,227,209) or colors[(i+(side+1)/2)%4+1]
			local home=house(Czone,"VillageInnerLaneHome_"..side.."_"..i.."_0",frame,32,26,13.8,siding,roofTint,{open=true,completeHome=true,furniture=i==1 and (side<0 and 6 or 7) or nil})
			colorRoof(home,roofTint)
			colorClapboard(home,siding)
			dressReferenceHome(home,frame,32,26,13.8,siding,roofTint,foregroundRight)
			if foregroundRight then
				-- This is the wall facing the arrival camera. Keep its interior
				-- solid and its clue surfaces untouched; the windows are scenic.
				assert(home.Name=="VillageInnerLaneHome_1_4_0")
				-- Native WoodPlanks made this otherwise cream cottage look gray in Play.
				-- Keep its tested clapboard variant on just the cream siding pieces.
				local creamSidingParts=0
				for _,piece in ipairs(home:GetDescendants()) do
					if piece:IsA("BasePart") and piece.Material==Enum.Material.WoodPlanks and piece.Color==siding then
						piece.MaterialVariant="Level5CourtyardClapboard"
						creamSidingParts+=1
					end
				end
				assert(creamSidingParts==17,"S03 arrival cottage siding inventory changed")
				local function arrivalDetail(name,size,localFrame,color,material)
					arrivalCottageParts+=1
					local piece=part(home,name,size,frame*localFrame,color,material,false)
					piece.CanQuery=false;piece.CanTouch=false
					return piece
				end
				for _,y in ipairs({6.7,20.1}) do
					for _,windowZ in ipairs({7,19}) do
						arrivalDetail("ArrivalSideWindowFrame",V(6.4,6.4,.12),CF(16.45,y,windowZ)*yaw(90),C.white,nil)
						arrivalDetail("ArrivalSideWindowGlass",V(5.7,5.7,.14),CF(16.6,y,windowZ)*yaw(90),Color3.fromRGB(54,65,65),Enum.Material.Glass)
						arrivalDetail("ArrivalSideWindowMullion",V(.16,5.7,.2),CF(16.7,y,windowZ)*yaw(90),C.white,nil)
						arrivalDetail("ArrivalSideWindowCrossbar",V(5.7,.16,.2),CF(16.7,y,windowZ)*yaw(90),C.white,nil)
						arrivalDetail("ArrivalSideWindowSill",V(6.6,.25,.65),CF(16.64,y-3.25,windowZ)*yaw(90),C.white,nil)
						for _,edge in ipairs({-1,1}) do
							arrivalDetail("ArrivalSideWindowShutter",V(.72,6.4,.2),CF(16.66,y,windowZ+edge*3.65)*yaw(90),Color3.fromRGB(117,125,112),Enum.Material.Wood)
						end
					end
				end
				arrivalDetail("ArrivalSideStoreyBand",V(26,.3,.36),CF(16.63,13.93,13)*yaw(90),C.white,nil)
				arrivalDetail("ArrivalSidePorchTopRail",V(4.2,.25,.22),CF(15,3.15,-2.55)*yaw(90),C.white,nil)
				arrivalDetail("ArrivalSidePorchBottomRail",V(4.2,.2,.22),CF(15,.55,-2.55)*yaw(90),C.white,nil)
				for _,porchZ in ipairs({-3.45,-1.45}) do
					arrivalDetail("ArrivalSidePorchBaluster",V(.18,2.6,.18),CF(15,1.85,porchZ),C.white,nil)
				end
			end
			if i==4 then
				if foregroundRight then
					part(Czone,"CottageEntryWalk",V(34,.08,10),CF(21,.1,895),Color3.fromRGB(211,207,192),Enum.Material.Concrete,false)
				else
					part(Czone,"CottageEntryWalk",V(26,.08,6),CF(-16.5,.1,812),Color3.fromRGB(211,207,192),Enum.Material.Concrete,false)
				end
			end
		end
		for i,z in ipairs({655,750}) do
			-- The right-side apartment wall now occupies this former scenic lot.
			-- Keep the left-side ground homes and all four Watcher court houses.
			if side<0 then
				local roofTint=Color3.fromRGB(106,109,101)
				local home=house(Czone,"OuterVillageStack_"..side.."_"..i.."_0",CF(side*244,0,z)*yaw(side*90),30,28,13.8,colors[i%4+1],roofTint,{open=true,completeHome=true})
				colorRoof(home,roofTint)
				colorClapboard(home,colors[i%4+1])
				dressReferenceHome(home,CF(side*244,0,z)*yaw(side*90),30,28,13.8,colors[i%4+1],roofTint,false)
			end
		end
	end
	assert(arrivalCottageParts==33,"S03 arrival cottage trim changed its instance budget")
	S03:SetAttribute("ArrivalCottageDetailParts",arrivalCottageParts)
	assert(referenceHomes==32 and referenceParts==610,"S03 reference cottages changed their instance budget")
	S03:SetAttribute("ReferenceCottageCount",referenceHomes)
	S03:SetAttribute("ReferenceCottageDetailParts",referenceParts)
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
			balconyRail(apartment,167.6,y,z+inset,31,5)
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
		part(apartment,"FullHeightBalconyPier",V(5.4,84,4.4),CF(167,47,z),Color3.fromRGB(226,221,202),Enum.Material.Plaster,false)
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
	-- Seat the scenic block behind the real east cottages; its former
	-- shift filled three open entry lanes with the colliding apartment core.
	for _,apartmentPart in ipairs(apartment:GetDescendants()) do
		if apartmentPart:IsA("BasePart") then apartmentPart.CFrame-=V(35,0,0) end
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
			balconyRail(nearWing,77.8,y,zz,25,5)
			part(nearWing,"RecessedDoor",V(.18,8,5.5),CF(94.1,y+5,zz),C.dark,nil,false)
		end
	end
	-- The arrival camera looks along Z, so the side balcony run above is
	-- nearly edge-on. Turn its near end toward the central lawn. Its first
	-- balcony level clears the foreground cottage roof and leaves the route open.
	local frontBalconyParts=0
	local function frontBalconyPart(name,size,frame,color,material)
		frontBalconyParts+=1
		return part(nearWing,name,size,frame,color,material,false)
	end
	frontBalconyPart("CourtFacingCreamCore",V(120,54,2.2),CF(55,67,860),Color3.fromRGB(223,218,201),Enum.Material.Plaster)
	for _,x in ipairs({-5,25,55,85,115}) do
		frontBalconyPart("CourtFacingBalconyPier",V(4.2,54,4.5),CF(x,67,871.3),Color3.fromRGB(230,225,205),Enum.Material.Plaster)
	end
	for level=0,3 do
		local y=42+level*12.5
		frontBalconyPart("CourtFacingStoreyBand",V(120,.42,2.5),CF(55,y-.55,861.8),C.white,Enum.Material.Plaster)
		for bay=0,3 do
			local x=10+bay*30
			frontBalconyPart("CourtFacingRecessedBay",V(25,10.7,.2),CF(x,y+5.4,861.2),Color3.fromRGB(132,130,116),Enum.Material.SmoothPlastic)
			frontBalconyPart("CourtFacingBalconyDeck",V(26,.55,12),CF(x,y-.3,865.7),C.pale,Enum.Material.Concrete)
			frontBalconyPart("CourtFacingBalconySoffit",V(26,.28,11.5),CF(x,y+11.6,865.7),Color3.fromRGB(231,226,209),Enum.Material.Plaster)
			frontBalconyPart("CourtFacingWarmWindow",V(7,6.7,.24),CF(x-5,y+5.8,861.4),Color3.fromRGB(237,208,157),Enum.Material.Glass)
			frontBalconyPart("CourtFacingDoor",V(4.6,8,.24),CF(x+5.2,y+4.9,861.4),Color3.fromRGB(48,58,56),Enum.Material.Glass)
			frontBalconyPart("CourtFacingWindowMullion",V(.2,6.7,.27),CF(x-5,y+5.8,861.59),C.white,nil)
			frontBalconyPart("CourtFacingWindowSill",V(7.4,.24,.45),CF(x-5,y+2.3,861.6),C.white,nil)
			frontBalconyPart("CourtFacingTopRail",V(26,.2,.2),CF(x,y+3.3,871.55),C.white,nil)
			frontBalconyPart("CourtFacingBottomRail",V(26,.2,.2),CF(x,y+.45,871.55),C.white,nil)
			for spindle=0,3 do
				frontBalconyPart("CourtFacingBaluster",V(.18,3,.18),CF(x-12+spindle*8,y+1.85,871.55),C.white,nil)
			end
		end
	end
	assert(frontBalconyParts==218,"S03 court-facing balconies changed their instance budget")
	nearWing:SetAttribute("CourtFacingBalconyParts",frontBalconyParts)
	-- The former two thin cottage fronts and projecting bay occupied the same
	-- foreground as enterable homes. Their visible details now live on those homes.
	local tower=model("SeparateManyWindowTower",S03)
	tower.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
	-- The separate modern tower wraps windows and pale floor bands around a
	-- circular core, unlike the flat balcony wall behind the cottage row.
	-- It is scenic and stays below the coffered ceiling and outside the route.
	local towerX,towerZ,towerRadius=-125,790,18
	local core=part(tower,"CurvedTowerCore",V(88,36,36),CF(towerX,44,towerZ)*CFrame.Angles(0,0,math.pi/2),Color3.fromRGB(226,224,214),Enum.Material.Plaster,false)
	core.MaterialVariant="";core.Color=Color3.fromRGB(226,224,214)
	core.Shape=Enum.PartType.Cylinder
	-- The camera-facing half needs window rhythm; the hidden rear arc does not.
	for column=6,14 do
		local angle=2*math.pi*column/20
		for level=0,10 do
			local frame=CF(towerX,5+level*7.6,towerZ)*CFrame.Angles(0,angle,0)*CF(0,0,-towerRadius-.2)
			part(tower,"CurvedTowerWindow",V(4.2,5.45,.16),frame,Color3.fromRGB(68,73,72),Enum.Material.SmoothPlastic,false)
		end
	end
	for column=5,14 do
		local edgeAngle=2*math.pi*(column+.5)/20
		part(tower,"CurvedTowerPier",V(.32,83,.35),CF(towerX,44,towerZ)*CFrame.Angles(0,edgeAngle,0)*CF(0,0,-towerRadius-.35),C.white,Enum.Material.SmoothPlastic,false)
	end
	for level=0,10 do
		local ring=part(tower,"CurvedTowerFloorBand",V(.3,36.8,36.8),CF(towerX,level*7.6+8.28,towerZ)*CFrame.Angles(0,0,math.pi/2),C.white,Enum.Material.SmoothPlastic,false)
		ring.Shape=Enum.PartType.Cylinder
	end
	local cornice=part(tower,"CurvedTowerCornice",V(.6,37.4,37.4),CF(towerX,88.3,towerZ)*CFrame.Angles(0,0,math.pi/2),C.white,Enum.Material.SmoothPlastic,false)
	cornice.Shape=Enum.PartType.Cylinder
	-- The far apartment bank is behind the north cottages, above their gables
	-- and below the suspended ceiling beams. Persistent streaming keeps this
	-- distant architecture present from the arrival court camera.
	local distant=model("LayeredFarResidentialClosure",S03)
	distant.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
	local farParts=0
	local function farPart(name,size,frame,color,material)
		farParts+=1
		return part(distant,name,size,frame,color,material,false)
	end
	for wing,info in ipairs({{-150,476,124},{-15,480,138},{118,475,116}}) do
		local x,z,w=info[1],info[2],info[3]
		local shellColor=wing==2 and Color3.fromRGB(224,219,204) or Color3.fromRGB(215,215,201)
		farPart("CreamApartmentCore",V(w,68,2.5),CF(x,60,z),shellColor,Enum.Material.Plaster)
		for _,side in ipairs({-1,1}) do
			farPart("ApartmentSideReturn",V(2,68,7),CF(x+side*(w/2-1),60,z+3.1),shellColor,Enum.Material.Plaster)
		end
		local bayWidth=(w-8)/3
		for level=0,4 do
			local y=30+level*13
			farPart("CreamStoreyBand",V(w,.36,.8),CF(x,y+11.7,z+1.5),C.white,Enum.Material.Plaster)
			for bay=1,3 do
				local bx=x-w/2+4+(bay-.5)*bayWidth
				local warm=(wing+level+bay)%5==0
				local paneColor=warm and Color3.fromRGB(227,207,156) or Color3.fromRGB(62,72,72)
				farPart("DeepBalconyRecess",V(bayWidth-1,9,.18),CF(bx,y+5.7,z+1.48),Color3.fromRGB(133,137,126),Enum.Material.SmoothPlastic)
				for _,side in ipairs({-1,1}) do
					farPart("BalconyBayCheek",V(.42,10,4.8),CF(bx+side*(bayWidth/2-.55),y+5.8,z+3.6),shellColor,Enum.Material.Plaster)
				end
				farPart("DeepBalconyDeck",V(bayWidth-1,.52,8),CF(bx,y-.26,z+5.3),Color3.fromRGB(226,223,209),Enum.Material.Plaster)
				farPart("BalconySoffit",V(bayWidth-1,.28,8),CF(bx,y+11.35,z+5.3),Color3.fromRGB(236,233,218),Enum.Material.Plaster)
				local windowX=bx-bayWidth*.17
				farPart("ApartmentWindow",V(bayWidth*.45,7.4,.16),CF(windowX,y+5.6,z+1.66),paneColor,warm and Enum.Material.SmoothPlastic or Enum.Material.Glass)
				farPart("ApartmentDoor",V(4.5,8,.16),CF(bx+bayWidth*.29,y+5.3,z+1.66),Color3.fromRGB(53,67,66),Enum.Material.Glass)
				farPart("WhiteWindowMullion",V(.17,7.4,.23),CF(windowX,y+5.6,z+1.54),C.white,nil)
				farPart("WhiteWindowSill",V(bayWidth*.45+.5,.24,.42),CF(windowX,y+1.8,z+1.58),C.white,nil)
				farPart("BalconyTopRail",V(bayWidth-1,.23,.2),CF(bx,y+3.25,z+9.38),C.white,nil)
				farPart("BalconyBottomRail",V(bayWidth-1,.18,.2),CF(bx,y+.5,z+9.38),C.white,nil)
				for post=0,3 do
					farPart("BalconyRailPost",V(.18,2.9,.18),CF(bx-(bayWidth-1)/2+(bayWidth-1)*post/3,y+1.85,z+9.38),C.white,nil)
				end
			end
		end
	end
	assert(farParts==699,"S03 far apartment bank changed its instance budget")
	distant:SetAttribute("ReferenceBalconyParts",farParts)
	-- The right court's outer wall has its own inward-facing apartment face.
	-- It sits beyond the cottage roofs and never occupies the walking lane.
	local sideWing=model("RightCourtApartmentWall",S03)
	local sideParts=0
	local function sidePart(name,size,frame,color,material)
		sideParts+=1
		return part(sideWing,name,size,frame,color,material,false)
	end
	sidePart("RightCourtCreamCore",V(3,68,160),CF(261,60,820),Color3.fromRGB(217,215,202),Enum.Material.Plaster)
	for _,z in ipairs({740,780,820,860,900}) do
		sidePart("RightCourtWhitePier",V(.4,68,1.2),CF(259.2,60,z),C.white,Enum.Material.Plaster)
	end
	for level=0,4 do
		local y=30+level*13
		for bay,z in ipairs({760,800,840,880}) do
			local warm=(level+bay)%6==0
			sidePart("RightCourtBalconyRecess",V(.2,9,25),CF(259.35,y+5.7,z),Color3.fromRGB(126,133,125),nil)
			sidePart("RightCourtBalconyDeck",V(9,.52,29),CF(254.5,y-.26,z),Color3.fromRGB(228,225,210),Enum.Material.Plaster)
			sidePart("RightCourtBalconySoffit",V(9,.28,29),CF(254.5,y+11.35,z),Color3.fromRGB(236,233,219),Enum.Material.Plaster)
			sidePart("RightCourtWindow",V(.16,7.4,8.5),CF(259.18,y+5.5,z-5.6),warm and Color3.fromRGB(226,206,158) or Color3.fromRGB(59,72,71),warm and Enum.Material.SmoothPlastic or Enum.Material.Glass)
			sidePart("RightCourtDoor",V(.16,8,5.1),CF(259.18,y+5.3,z+6.3),Color3.fromRGB(53,67,66),Enum.Material.Glass)
			sidePart("RightCourtTopRail",V(.2,.23,29),CF(249.8,y+3.25,z),C.white,nil)
			sidePart("RightCourtBottomRail",V(.2,.18,29),CF(249.8,y+.5,z),C.white,nil)
			for post=0,4 do
				sidePart("RightCourtRailPost",V(.18,2.9,.18),CF(249.8,y+1.85,z-14.5+29*post/4),C.white,nil)
			end
		end
	end
	assert(sideParts==246,"S03 right apartment wall changed its instance budget")
	sideWing:SetAttribute("ReferenceBalconyParts",sideParts)
	for _,z in ipairs({552,688,824}) do part(S03,"HeavyCofferBeam",V(550,5,5),CF(0,97,z),C.pale,nil,false) end
	for _,x in ipairs({-130,0,130}) do part(S03,"LongCofferBeam",V(5,5,474),CF(x,97,696),C.pale,nil,false) end
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
	-- Low planted islands interrupt the vacant court lawn while keeping
	-- the stepping path and all cottage thresholds open.
	for _,z in ipairs({585,700,865}) do
		for _,side in ipairs({-1,1}) do
			part(planting,"CourtGardenBed",V(20,.16,9),CF(side*75,.08,z),Color3.fromRGB(91,112,75),Enum.Material.Grass,false)
		end
	end
	for _,side in ipairs({-1,1}) do
		part(planting,"NearCottageGardenBed",V(23,.16,9),CF(side*30,.08,850),Color3.fromRGB(101,119,78),Enum.Material.Grass,false)
	end
	for i,site in ipairs({{-31,856,13,6,20},{28,850,13,6,20},{-49,842,11,5,37},{55,843,11,5,-15},{-82,790,12,5,8},{82,790,12,5,33},
		{-75,585,17,6,12},{75,585,17,6,-17},{-75,700,18,6,-9},{75,700,18,6,22},{-75,865,18,6,14},{75,865,18,6,-12}}) do
		plantCutout("CottageHedge_"..i,hedgeTexture,site[1],site[2],site[3],site[4],site[5])
	end
	plantCutout("BurgundyCourtyardMaple","rbxassetid://73750223479530",70,891,18,20,25)
	camera("VillageFourCourts",V(-30,7,920),V(-20,54,720))
	camera("VillageUpperCrossing",V(-101,19,696),V(135,35,838))
	camera("VillageBackCourt",V(171,6,881),V(220,49,840))
	for _,z in ipairs({462,535,610,682,719,790,870,930}) do point(0,3,z) end

	-- D has a real twelve-stud depression, raised domestic sidewalks and a
	-- cross-street at grade. Lower and upper circuits reconnect without jumping.
	local D=zone("D_FloralTerraces",V(-160,-14,936),V(160,320,1296))
	local S04=model("S04_MistyTowerCanyon",D)
	local towerHomes,towerDetails,towerGables,towerPorches=0,0,0,0
	local function towerCottageFinish(home,frame,width,height,siding,roofTint,hasGable,hasPorch,deepPorch)
		-- Refinish the existing rooms. Their doorway, standard glass, floor,
		-- Watcher reference and puzzle marker stay on the original house model.
		local exterior={SideWall=true,BackWall=true,BackWallWing=true,BackWallHeader=true,FacadeLintel=true,WindowApron=true,FacadePier=true,GableBaseBand=true,ClosedGableTriangle=true}
		local clapboard=game:GetService("MaterialService"):FindFirstChild("Level5CourtyardClapboard")
		for _,piece in ipairs(home:GetChildren()) do
			if piece:IsA("BasePart") and exterior[piece.Name] then
				piece.Material=Enum.Material.WoodPlanks
				piece.MaterialVariant=clapboard and clapboard:IsA("MaterialVariant") and clapboard.Name or ""
				piece.Color=siding
			end
		end
		local function detail(name,size,localFrame,color,material,collide)
			towerDetails+=1
			return part(home,name,size,frame*localFrame,color,material,collide)
		end
		for _,side in ipairs({-1,1}) do
			detail("TowerCottageCornerBoard",V(.36,height,.38),CF(side*(width/2-.18),height/2,-.52),C.white,nil,false)
		end
		if hasGable then
			towerGables+=1
			local y=height+width*.18
			detail("TowerCottageAtticFrame",V(3.5,3.2,.2),CF(0,y,-.55),C.white,nil,false)
			detail("TowerCottageAtticGlass",V(2.75,2.45,.22),CF(0,y,-.69),Color3.fromRGB(54,62,62),Enum.Material.Glass,false)
			detail("TowerCottageAtticMullion",V(.16,2.45,.25),CF(0,y,-.84),C.white,nil,false)
			detail("TowerCottageAtticSill",V(3.9,.25,.45),CF(0,y-1.7,-.58),C.white,nil,false)
		end
		if hasPorch then
			towerPorches+=1
			-- A shallow, open veranda leaves the central doorway and the raised
			-- promenade clear. These replace the bulky 27-instance old porches.
			local porchDepth=deepPorch and 7 or 4.5
			detail("TowerCottagePorchDeck",V(width+.4,.15,porchDepth),CF(0,.08,-porchDepth/2),C.pale,Enum.Material.WoodPlanks,false)
			local canopy=detail("TowerCottageFlatCanopy",V(width+1,.4,porchDepth+.8),CF(0,11.7,-(porchDepth+.8)/2),roofTint,Enum.Material.Slate,false)
			canopy.MaterialVariant="";canopy.Color=roofTint
			detail("TowerCottagePorchFascia",V(width+1,.6,.32),CF(0,11.35,-porchDepth-.75),C.white,nil,false)
			local railWidth=width/2-4.6
			for _,side in ipairs({-1,1}) do
				detail("TowerCottagePorchColumn",V(.72,10.9,.72),CF(side*(width/2-1),5.45,-porchDepth-.05),C.white,nil,false)
				detail("TowerCottagePorchRail",V(railWidth,.22,.2),CF(side*(4.6+railWidth/2),3.05,-porchDepth-.05),C.white,nil,false)
			end
		end
		towerHomes+=1
		home:SetAttribute("S04ReferenceCottage",true)
	end
	local terraceStone=Color3.fromRGB(167,164,145)
	local towerSlate=Color3.fromRGB(78,81,76)
	local towerCream=Color3.fromRGB(222,218,203)
	local towerTaupe=Color3.fromRGB(195,191,181)
	local towerGray=Color3.fromRGB(205,206,199)
	local towerSage=Color3.fromRGB(208,211,196)
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
			local clapboard=i==1 and (s<0 and towerCream or towerTaupe) or (i%2==0 and towerGray or towerSage)
			local nearHome=i==1
			local groundRoof=towerSlate
			if nearHome then groundRoof=nil end
			local home=house(S04,"FloralTowerHome_"..s.."_"..i.."_0",frame,30,26,13.8,clapboard,groundRoof,{open=true,backOpening=i==2,furniture=i==3 and (s<0 and 3 or 5) or nil})
			colorRoof(home,towerSlate);colorClapboard(home,clapboard)
			towerCottageFinish(home,frame,30,13.8,clapboard,towerSlate,not nearHome,true)
			if nearHome then
				local upper=house(S04,"FloralTowerUpperHome_"..s.."_"..i,frame*CF(0,14,0),30,26,13.8,clapboard,towerSlate,{open=false})
				colorRoof(upper,towerSlate);colorClapboard(upper,clapboard)
				towerCottageFinish(upper,frame*CF(0,14,0),30,13.8,clapboard,towerSlate,true,false)
			end
			if i==1 then K.registerWatcher(home,"FloralTerraceWindow_"..s,D.Name) end
		end
		for i,z in ipairs({1045,1170}) do
			local frame=CF(s*48,-12,z)*yaw(s*90)
			local siding=i==1 and towerGray or towerTaupe
			local lower=house(S04,"LowerFloralHome_"..s.."_"..i,frame,28,26,13.8,siding,nil,{open=true})
			local upper=house(S04,"UpperFloralHome_"..s.."_"..i,frame*CF(0,14,0),28,26,13.8,siding,towerSlate,{open=false})
			colorClapboard(lower,siding);colorClapboard(upper,siding)
			colorRoof(upper,towerSlate)
			towerCottageFinish(lower,frame,28,13.8,siding,towerSlate,false,true)
			towerCottageFinish(upper,frame*CF(0,14,0),28,13.8,siding,towerSlate,true,false)
		end
		for i,z in ipairs({1032,1158,1250}) do
			local p=part(D,"FloralPaperWallPanel",V(.06,34,34),CF(s*159.33,28,z),C.pale,nil,false)
			K.material(p,"Wallpaper")
		end
	end
	local function refaceSunkenPocketUpper(upper,siding)
		-- The closed scenic upper room presents divided windows, not a second-floor
		-- front door. Reuse its existing door trim and panels without new parts.
		local panes,panels,jambs={},{},{}
		for _,piece in ipairs(upper:GetChildren()) do
			if piece:IsA("BasePart") then
				if piece.Name=="WindowGlass" then table.insert(panes,piece)
				elseif piece.Name=="DoorRaisedPanel" then table.insert(panels,piece)
				elseif piece.Name=="DoorJamb" then table.insert(jambs,piece) end
			end
		end
		local door=assert(upper:FindFirstChild("ClosedPanelDoor"))
		local header=assert(upper:FindFirstChild("DoorHeader"))
		local knob=assert(upper:FindFirstChild("BrassDoorKnob"))
		assert(#panes==2 and #panels==6 and #jambs==2,"S04 upper window inventory changed")
		local doorFrame=door.CFrame
		local clapboard=game:GetService("MaterialService"):FindFirstChild("Level5CourtyardClapboard")
		door.Size=V(5.4,10.3,.65)
		door.CFrame=doorFrame*CF(0,0,-.05)
		door.Color=siding;door.Material=Enum.Material.WoodPlanks
		door.MaterialVariant=clapboard and clapboard:IsA("MaterialVariant") and clapboard.Name or ""
		for i,pane in ipairs(panes) do
			for j=1,3 do
				local bar=panels[(i-1)*3+j]
				bar.Size=j==3 and V(pane.Size.X,.14,.23) or V(.14,pane.Size.Y,.23)
				bar.CFrame=pane.CFrame*CF(j==1 and -pane.Size.X/4 or j==2 and pane.Size.X/4 or 0,0,-.09)
				bar.Color=C.white;bar.Material=Enum.Material.SmoothPlastic;bar.MaterialVariant=""
				bar.CanCollide=false;bar.CanQuery=false;bar.CanTouch=false;bar.CastShadow=false
			end
		end
		for i,side in ipairs({-1,1}) do
			local pier=jambs[i]
			pier.Size=V(.36,13.8,.4)
			pier.CFrame=doorFrame*CF(side*3.35,1.75,-.18)
			pier.CanCollide=false;pier.CanQuery=false;pier.CanTouch=false
		end
		header.Size=V(30.8,.4,.55)
		header.CFrame=doorFrame*CF(0,5.25,-.18)
		header.CanCollide=false;header.CanQuery=false;header.CanTouch=false
		knob:Destroy()
	end
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({1004,1220}) do
			local roofTint=Color3.fromRGB(87,88,82)
			local pocketClapboard=i==1 and (side<0 and towerCream or towerTaupe) or towerSage
			local frame=CF(side*26,-12,z)*yaw(side*90)
			local groundRoof=roofTint
			if i==1 then groundRoof=nil end -- the second storey owns this roofline
			local home=house(D,"SunkenPocketStack_"..side.."_"..i.."_0",frame,26,24,13.8,pocketClapboard,groundRoof,{open=true})
			colorRoof(home,roofTint)
			colorClapboard(home,pocketClapboard)
			towerCottageFinish(home,frame,26,13.8,pocketClapboard,roofTint,i~=1,true,i==1)
			if i==1 then
				-- These two near cottages are two storeys in the S04 reference:
				-- taupe on the arrival left and cream on the right.
				local upperFrame=CF(side*26,2,z)*yaw(side*90)
				local upper=house(S04,"SunkenPocketUpper_"..side.."_"..i,upperFrame,30,26,13.8,pocketClapboard,roofTint,{open=false})
				colorRoof(upper,roofTint);colorClapboard(upper,pocketClapboard)
				towerCottageFinish(upper,upperFrame,30,13.8,pocketClapboard,roofTint,true,false)
				refaceSunkenPocketUpper(upper,pocketClapboard)
			end
		end
	end
	-- Tall, restrained shafts sit behind the gabled street houses. The small
	-- asymmetric balcony banks and vertical windows have a different facade
	-- language from S03's broad, bright apartment landings.
	for _,side in ipairs({-1,1}) do
		local tower=model(side<0 and "WestRecessedTower" or "EastRecessedTower",S04)
		local outer=side*156
		for tier=0,5 do
			local tone=Color3.fromRGB(224,214,192):Lerp(Color3.fromRGB(193,192,181),tier/5*.82)
			local shaft=part(tower,"PaleTowerShaft",V(6,47.6,324),CF(outer,11.75+tier*47.5,1116),tone,Enum.Material.Plaster)
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
				local deckX=side*(142-(bay==2 and 2 or 0)-(level%3==0 and 1 or 0))
				part(tower,"InsetBalconyShadow",V(.25,10,narrow),CF(side*152.7,y+6,z+offsetZ),Color3.fromRGB(117,121,112):Lerp(tone,.42),nil,false)
				local deck=part(tower,"OffsetBalconyDeck",V(18,.55,narrow+2),CF(deckX,y-.3,z+offsetZ),tone,nil,level<=12)
				deck.Transparency=level>12 and (level-12)/7*.24 or 0
				-- The upper balconies dissolve into the mist. Full sash trim on
				-- every distant storey adds thousands of invisible tiny instances.
				if level<=9 then
					part(tower,"BalconyRecessDoor",V(.2,7.6,5.6),CF(side*152.7,y+5,z+offsetZ-5.5),Color3.fromRGB(66,76,72):Lerp(tone,haze*.38),Enum.Material.Glass,false)
					part(tower,"BalconyRecessWindow",V(.2,7.6,5.6),CF(side*152.7,y+5,z+offsetZ+5.5),Color3.fromRGB(66,76,72):Lerp(tone,haze*.38),Enum.Material.Glass,false)
					for _,windowZ in ipairs({z+offsetZ-5.5,z+offsetZ+5.5}) do
						for _,edge in ipairs({-1,1}) do
							part(tower,"BalconyOpeningJamb",V(.26,8,.23),CF(side*152.45,y+5,windowZ+edge*2.9),C.white,nil,false)
						end
						part(tower,"BalconyOpeningHeader",V(.3,.26,6),CF(side*152.45,y+9,windowZ),C.white,nil,false)
					end
				end
				local railX=deckX-side*9.2
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
				part(tower,"NarrowVerticalWindow",V(.2,8.4,3.2),CF(side*153,y+4.5,z),Color3.fromRGB(51,61,59):Lerp(tone,haze),Enum.Material.Glass,false)
				if level<=8 then
					for _,edge in ipairs({-1,1}) do
						part(tower,"NarrowWindowJamb",V(.25,8.8,.18),CF(side*152.78,y+4.5,z+edge*1.66),C.white,nil,false)
					end
					part(tower,"NarrowWindowSill",V(.32,.21,3.6),CF(side*152.76,y+.2,z),C.white,nil,false)
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
		part(middleTower,"ProjectingWhiteBalcony",V(20,.38,5),CF(-80,y-4.4,1121),C.pale,Enum.Material.Plaster,false)
		part(middleTower,"BalconyFrontRail",V(20,.25,.2),CF(-80,y-1.2,1118.4),C.white,nil,false)
		if level%3==0 then
			for _,x in ipairs({-88,-80,-72}) do
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
	-- Keep a light, distant apartment facade visible before the far 3D
	-- towers stream in. The plane is scenic and sits behind those towers.
	local farBackdrop=model("MistyFarImageBackdrop",S04)
	farBackdrop.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
	local backdropPanel=part(farBackdrop,"DistantApartmentFacade",V(340,340,.6),CF(0,150,1290.6),Color3.fromRGB(142,138,138),Enum.Material.SmoothPlastic,false)
	backdropPanel.CanTouch=false;backdropPanel.CanQuery=false;backdropPanel.CastShadow=false
	local backdropGui=Instance.new("SurfaceGui")
	backdropGui.Name="DistantApartmentFacadeImage";backdropGui.Face=Enum.NormalId.Front
	backdropGui.LightInfluence=0;backdropGui.Brightness=1;backdropGui.PixelsPerStud=4
	backdropGui.AlwaysOnTop=false;backdropGui.Parent=backdropPanel
	local facadeImage=Instance.new("ImageLabel")
	facadeImage.Name="FacadeImage";facadeImage.Size=UDim2.fromScale(1,1)
	facadeImage.BackgroundTransparency=1;facadeImage.Image="rbxassetid://70683122425519"
	facadeImage.Parent=backdropGui
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
	local cornerFrame=CF(0,-12,1132)
	local corner=house(D,"SunkenCornerResidence",cornerFrame,36,24,13.8,towerGray,towerSlate,{open=true,completeHome=true,furniture=8})
	colorRoof(corner,towerSlate)
	towerCottageFinish(corner,cornerFrame,36,13.8,towerGray,towerSlate,true,true)
	assert(towerHomes==23 and towerGables==15 and towerPorches==15 and towerDetails==211,"S04 cottage inventory changed")
	S04:SetAttribute("ReferenceCottageCount",towerHomes)
	S04:SetAttribute("ReferenceCottageDetailParts",towerDetails)
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
	-- S04ReferenceDarkWindowFinish: the photographed background tower panes
	-- read as charcoal beneath the warm indoor ceiling, not daylight blue.
	for _,pane in ipairs(D:GetDescendants()) do
		if pane:IsA("BasePart") and pane.Material==Enum.Material.Glass and pane:GetAttribute("Level5TintedWindow")~=true then
			pane.Color=Color3.fromRGB(50,55,51)
			pane.Transparency=.04
			pane.Material=Enum.Material.SmoothPlastic
		end
	end
	camera("FloralSunkenArrival",V(9,5,943),V(-73,66,1108))
	camera("FloralLowerStreet",V(-15,-6,1031),V(90,37,1195))
	camera("FloralHighPorches",V(-93,6,1130),V(116,32,1212))
	point(0,3,941);point(0,2.5,948);point(0,-9,980);point(0,-9,1040);point(0,-9,1112);point(0,-9,1175);point(0,-9,1230);point(0,3,1264);point(0,3,1290)

	-- E: several real rooms deep. Side routes return behind the houses, while
	-- a succession of through-houses forms an understandable central passage.
	local E=zone("E_DomesticLabyrinth",V(-160,0,1296),V(160,44,1596))
	local S10=model("S10_EmptyBalconyRoom",E)
	local warmBroadloom=Color3.fromRGB(185,176,160)
	local warmPlaster=Color3.fromRGB(211,203,185)
	local quietCeiling=Color3.fromRGB(201,199,184)
	local domesticHomes=0
	local function domesticRoomFinish(home,tint)
		-- These are connected interior rooms, so their old exterior siding
		-- becomes the same warm plaster as the S10 partitions. Keep the real
		-- openings, standard Watcher panes and puzzle marker in each room.
		local walls={SideWall=true,BackWall=true,BackWallWing=true,BackWallHeader=true,FacadeLintel=true,WindowApron=true,FacadePier=true}
		for _,piece in ipairs(home:GetChildren()) do
			if piece:IsA("BasePart") and walls[piece.Name] then
				piece.Material=Enum.Material.Plaster;piece.MaterialVariant="";piece.Color=tint
			elseif piece:IsA("BasePart") and piece.Name=="InteriorCeiling" then
				piece.Material=Enum.Material.Plaster;piece.MaterialVariant="";piece.Color=quietCeiling
			end
		end
		domesticHomes+=1
		home:SetAttribute("S10PlasterRoom",true)
	end
	local function smoothRoom(into,name,size,frame,color,collide)
		return part(into,name,size,frame,color,Enum.Material.SmoothPlastic,collide)
	end
	local broadloom=floor(E,"DomesticBroadloom",0,0,1446,320,300,warmBroadloom)
	-- The carpet variant normally resets its tint toward white. Give this
	-- district the subdued warm-beige broadloom visible in the reference.
	broadloom.MaterialVariant="";broadloom.Material=Enum.Material.Fabric;broadloom.Color=warmBroadloom
	for _,s in ipairs({-1,1}) do
		-- These two real ground rooms retain the existing supported Window
		-- Watcher panes; the repeated side-room array no longer hides the void.
		local homeX=s<0 and -54 or 88
		local home=house(E,"DomesticRoom_"..s.."_1_1",CF(homeX,0,1340)*yaw(s*90),36,28,13.8,C.cream,nil,{open=true,backOpening=true})
		domesticRoomFinish(home,warmPlaster)
		K.registerWatcher(home,"DomesticWindow_"..s,E.Name)
		-- Leave the upper balcony shaft visible beside S10's three windows.
		local ceilingStart=s<0 and 1296 or 1390
		local ceilingLength=1596-ceilingStart
		smoothRoom(E,"LowRoomCeilingBand",V(114,.6,ceilingLength),CF(s*103,16,ceilingStart+ceilingLength/2),quietCeiling)
	end
	for i,z in ipairs({1460,1540}) do
		local home=house(E,"NestedThroughHouse_"..i.."_0",CF(0,0,z),66,28,13.8,C.cream,nil,{open=true,backOpening=true})
		domesticRoomFinish(home,i==1 and Color3.fromRGB(217,209,193) or warmPlaster)
	end
	-- The gate-five clock candidate stays a true enterable home beyond the
	-- sparse front room, with the original HousePuzzleCandidate attributes.
	local endHome=house(E,"LabyrinthEndResidence_2_0",CF(0,0,1570),44,20,13.8,C.pale,nil,{open=true,completeHome=true,furniture=7})
	domesticRoomFinish(endHome,Color3.fromRGB(207,200,184))
	assert(domesticHomes==5,"S10 connected room inventory changed")
	S10:SetAttribute("PlasterRoomCount",domesticHomes)
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
	smoothRoom(S10,"RightRoomWall",V(.7,16,83),CF(-36,8,1348),warmPlaster)
	smoothRoom(S10,"LeftWindowApron",V(.7,3.4,83),CF(36,1.7,1348),warmPlaster)
	smoothRoom(S10,"LeftWindowHeader",V(.7,3.4,83),CF(36,14.3,1348),warmPlaster)
	for _,span in ipairs({{1306.5,1319},{1333,1339},{1353,1359},{1373,1389.5}}) do
		smoothRoom(S10,"LeftWindowPier",V(.7,9.2,span[2]-span[1]),CF(36,8,(span[1]+span[2])/2),warmPlaster)
	end
	for _,z in ipairs({1326,1346,1366}) do
		local glass=part(S10,"InteriorAtriumWindowGlass",V(.15,9.2,14),CF(35.5,8,z),Color3.fromRGB(151,156,147),Enum.Material.Glass)
		glass.Transparency=.8
		for _,y in ipairs({3.4,8,12.6}) do part(S10,"WindowCrossbar",V(.3,.17,14.5),CF(35.25,y,z),C.white,nil,false) end
		for _,zz in ipairs({z-7.1,z+7.1}) do part(S10,"WindowJamb",V(.3,9.6,.22),CF(35.25,8,zz),C.white,nil,false) end
		part(S10,"WindowCentreMullion",V(.3,9.2,.2),CF(35.25,8,z),C.white,nil,false)
	end
	-- The return is a shallow, nonblocking visual bay: two front-facing tall
	-- windows remain legible from arrival while the central x=0 line stays free.
	local windowReturn=model("S10_TwoTallWindowReturn",S10)
	smoothRoom(windowReturn,"LowPlasterApron",V(24,3.4,.48),CF(24,1.7,1332),warmPlaster,false)
	smoothRoom(windowReturn,"HighPlasterHeader",V(24,3.4,.48),CF(24,14.3,1332),warmPlaster,false)
	for _,span in ipairs({{12,13.55},{20.05,25.95},{32.45,36}}) do
		smoothRoom(windowReturn,"PlasterWindowPier",V(span[2]-span[1],9.2,.48),CF((span[1]+span[2])/2,8,1332),warmPlaster,false)
	end
	for _,wx in ipairs({16.8,29.2}) do
		local pane=part(windowReturn,"TallReturnWindowGlass",V(6.5,9.2,.12),CF(wx,8,1331.69),Color3.fromRGB(151,156,147),Enum.Material.Glass,false)
		pane.Transparency=.72
		for _,edge in ipairs({-1,1}) do part(windowReturn,"TallReturnJamb",V(.27,9.6,.2),CF(wx+edge*3.32,8,1331.55),C.white,nil,false) end
		for _,y in ipairs({3.35,8,12.65}) do part(windowReturn,"TallReturnCrossbar",V(6.8,.2,.2),CF(wx,y,1331.55),C.white,nil,false) end
		part(windowReturn,"TallReturnMullion",V(.18,9.5,.2),CF(wx,8,1331.53),C.white,nil,false)
	end
	part(S10,"BroadPortalHeader",V(76,1.4,.85),CF(0,15.3,1306.5),C.white,Enum.Material.Plaster)
	for _,s in ipairs({-1,1}) do part(S10,"BroadPortalJamb",V(.85,16,.85),CF(s*36.6,8,1306.5),C.white,Enum.Material.Plaster) end
	smoothRoom(S10,"CentralPartitionLeft",V(32.2,16,.7),CF(19.9,8,1358),warmPlaster)
	smoothRoom(S10,"CentralPartitionRight",V(14.2,16,.7),CF(-10.9,8,1358),warmPlaster)
	for _,span in ipairs({{19.9,32.2},{-10.9,14.2}}) do
		part(S10,"CentralPartitionBaseboard",V(span[2],.52,.2),CF(span[1],.26,1357.52),C.white,nil,false)
		part(S10,"CentralPartitionCrown",V(span[2],.38,.38),CF(span[1],15.7,1357.5),C.white,nil,false)
	end
	part(S10,"RoomSideBaseboard",V(.28,.58,83),CF(-35.48,.29,1348),C.white,nil,false)
	part(S10,"RoomSideCrown",V(.44,.38,83),CF(-35.44,15.65,1348),C.white,nil,false)
	part(S10,"CentralSixPanelDoor",V(7.6,10,.35),CF(0,5,1357.6),Color3.fromRGB(232,231,224),Enum.Material.SmoothPlastic)
	for _,s in ipairs({-1,1}) do
		for _,row in ipairs({1,2,3}) do
			local y=row==1 and 1.8 or row==2 and 5.3 or 8.2
			local h=row==2 and 2.9 or 1.55
			part(S10,"RaisedDoorPanel",V(2.4,h,.12),CF(s*1.75,y,1357.34),Color3.fromRGB(242,241,237),Enum.Material.SmoothPlastic,false)
		end
	end
	local knob=part(S10,"BrassDoorKnob",V(.35,.35,.35),CF(2.7,4.9,1357.1),Color3.fromRGB(147,130,80),Enum.Material.Metal,false)
	knob.Shape=Enum.PartType.Ball
	part(S10,"DoorFrameHeader",V(8.6,.42,.65),CF(0,10.2,1357.3),C.white)
	for _,s in ipairs({-1,1}) do part(S10,"DoorFrameJamb",V(.45,10.2,.65),CF(s*4,5.1,1357.3),C.white) end
	smoothRoom(S10,"PassageHeader",V(18,5.4,.75),CF(-27,13.3,1358),warmPlaster)
	for _,x in ipairs({-18.3,-35.7}) do part(S10,"PassageJamb",V(.45,10.7,.75),CF(x,5.35,1358),C.white) end
	smoothRoom(S10,"LowSuspendedCeiling",V(72,.45,83),CF(0,13,1348),quietCeiling)
	-- The low ceiling joins the side bands at x=46. These strips remove the
	-- accidental high atrium slit above the domestic room's window wall.
	for _,s in ipairs({-1,1}) do
		smoothRoom(S10,"WindowWallCeilingReturn",V(10,.45,83),CF(s*41,13,1348),quietCeiling,false)
	end
	for _,z in ipairs({1321,1343,1365,1382}) do part(S10,"CeilingGridCrossbeam",V(72,.13,.15),CF(0,12.7,z),C.white,nil,false) end
	for _,x in ipairs({-18,0,18}) do part(S10,"CeilingGridLongBeam",V(.15,.13,83),CF(x,12.7,1348),C.white,nil,false) end
	for _,z in ipairs({1324,1347,1372}) do
		local lamp=part(S10,"LongFluorescentPanel",V(10,.16,3.2),CF(0,12.65,z),Color3.fromRGB(224,226,214),Enum.Material.Neon,false)
		local light=Instance.new("SurfaceLight");light.Face=Enum.NormalId.Bottom;light.Range=24;light.Brightness=.55;light.Shadows=false;light.Parent=lamp
	end
	local balconies=model("ContainedOppositeBalconies",S10)
	-- Begin the shaft behind the arrival crossing so the route from gate four
	-- reaches the room portal before the first window starts at z=1319.
	part(balconies,"DarkShaftBacking",V(1,43,69.5),CF(119,21.5,1354.75),Color3.fromRGB(105,108,100),Enum.Material.Plaster)
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
