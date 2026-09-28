-- Level 5: The Indoor Suburbs. Geometry only; deliberately independent of Level 4.
-- All authored coordinates are relative to origin. No Lighting, entity or quest mutation.
local Architecture = {}
local DEFAULT_TEXTURES={Plaster="rbxassetid://108985650994325",Wallpaper="rbxassetid://102299936573476",Siding="rbxassetid://115748401620318",Grass="rbxassetid://126776492995543",Wood="rbxassetid://118880038763227",Roof="rbxassetid://118077370167392",Carpet="rbxassetid://113909496202267"}
local DEFAULT_VARIANTS={Plaster="Level5AgedPlaster",Wallpaper="Level5FloralWallpaper",Siding="Level5PaintedSiding",Grass="Level5LawnGrass",Wood="Level5VeneerWood",Roof="Level5RoofShingles",Carpet="Level5LoopCarpet"}

function Architecture.Build(parent, origin, config)
	config = table.clone(config or {})
	config.ExitArrowTexture = config.ExitArrowTexture or "rbxassetid://136557095207787"
	config.ExitArrowLeftTexture = config.ExitArrowLeftTexture or "rbxassetid://119578216618152"
	config.FurnitureUpholsteryTexture = config.FurnitureUpholsteryTexture or "rbxassetid://132119936960491"
	config.FurnitureTVTexture = config.FurnitureTVTexture or "rbxassetid://129933596500815"
	config.TexturePalette = setmetatable(table.clone(config.TexturePalette or {}),{__index=DEFAULT_TEXTURES})
	config.MaterialVariants = setmetatable(table.clone(config.MaterialVariants or {}),{__index=DEFAULT_VARIANTS})
	local Furniture = require(script.Parent:WaitForChild("Level 5 Furniture"))
	local furnitureKit
	origin = origin or Vector3.zero
	local root = Instance.new("Model")
	root.Name = "Level5_IndoorSuburbs"
	root:SetAttribute("ArchitectureVersion", "2026-09-28.s01-balcony-depth.4")
	root:SetAttribute("GeometryOnly", true)
	root.Parent = parent
	local offset = CFrame.new(origin)
	local V, CF = Vector3.new, CFrame.new
	local C = {
		cream=Color3.fromRGB(214,205,174), pale=Color3.fromRGB(232,225,205), white=Color3.fromRGB(241,238,220),
		carpet=Color3.fromRGB(162,150,125), green=Color3.fromRGB(48,86,67), pink=Color3.fromRGB(211,165,163),
		yellow=Color3.fromRGB(216,184,99), rose=Color3.fromRGB(205,154,159), blue=Color3.fromRGB(144,166,182),
		lavender=Color3.fromRGB(173,155,179), glass=Color3.fromRGB(87,102,102), dark=Color3.fromRGB(24,30,29),
		ceiling=Color3.fromRGB(181,179,157), grid=Color3.fromRGB(136,138,126), red=Color3.fromRGB(133,38,32),
	}
	local partCount, lightCount = 0, 0
	local floorSurfaces,sideWalls={},{}
	local materials=game:GetService("MaterialService")
	local trimTemplates=game:GetService("ServerStorage"):FindFirstChild("Level5GeometryTemplates")
	local bases={Plaster=Enum.Material.Plaster,Wallpaper=Enum.Material.Plaster,Siding=Enum.Material.WoodPlanks,Grass=Enum.Material.Grass,Wood=Enum.Material.Wood,Roof=Enum.Material.Slate,Carpet=Enum.Material.Fabric}
	local function material(p,key,tint)
		local base=bases[key];if not base then return p end
		p.Material=base
		local variantName=config.MaterialVariants[key]
		local variant=variantName and materials:FindFirstChild(variantName)
		if variant and variant:IsA("MaterialVariant") then
			p.MaterialVariant=variantName;p.Color=tint or Color3.new(1,1,1)
		else p.MaterialVariant="";if tint then p.Color=tint end end
		p:SetAttribute("Level5SurfaceMaterial",key)
		return p
	end
	local function model(name, into)
		local m=Instance.new("Model"); m.Name=name; m.Parent=into or root; return m
	end
	local function part(into, name, size, cf, color, material, collide, className)
		if name=="CarpetLedgePlasterSoffit" or name=="CrossingPlasterSoffit" then
			-- A small plaster reveal covers the slab edge instead of sharing its
			-- vertical face. Crossings have a deeper underside than side galleries.
			size+=V(.24,0,.24)
			if name=="CrossingPlasterSoffit" then size+=V(0,.26,0);cf-=V(0,.13,0) end
		elseif name=="PitEndWall" then
			local minimum,maximum=into:GetAttribute("PitMin"),into:GetAttribute("PitMax")
			if typeof(minimum)=="Vector3" and typeof(maximum)=="Vector3" then
				-- The pit wall is the visible face; the full solid gallery backing
				-- stays behind it rather than ending on the same plaster plane.
				cf+=V(0,0,cf.Position.Z<(minimum.Z+maximum.Z)/2 and .24 or -.24)
			end
		elseif name=="TerraceFoundationEnd" then
			-- End infill stops at the inner faces of the existing side walls.
			size-=V(2,0,0)
		end
		local p=Instance.new(className or "Part")
		p.Name=name; p.Size=size; p.CFrame=offset*cf; p.Anchored=true
		p.Color=color or C.cream; p.Material=material or Enum.Material.SmoothPlastic
		p.CanCollide=collide~=false; p.CanQuery=collide~=false; p.CanTouch=false; p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
		p.CastShadow=collide~=false and math.min(size.X,size.Y,size.Z)>.4
		p.Parent=into; partCount+=1
		if material==Enum.Material.Plaster then p.MaterialVariant=config.MaterialVariants.Plaster or ""
		elseif material==Enum.Material.WoodPlanks then p.MaterialVariant=config.MaterialVariants.Siding or ""
		elseif material==Enum.Material.Slate and materials:FindFirstChild(config.MaterialVariants.Roof) then p.MaterialVariant=config.MaterialVariants.Roof;p.Color=Color3.new(1,1,1)
		elseif material==Enum.Material.Fabric and materials:FindFirstChild(config.MaterialVariants.Carpet) then
			p.MaterialVariant=config.MaterialVariants.Carpet;p.Color=color and Color3.new(1,1,1):Lerp(color,.3) or Color3.new(1,1,1)
		end
		-- Scenic houses use the direct part path rather than floor(). Keep both
		-- in the same surface-ownership pass without touching furniture or stairs.
		if name=="InteriorCarpet" then floorSurfaces[p]=true end
		if name=="SideWall" then table.insert(sideWalls,p) end
		return p
	end
	local function texture(p, asset, face, tile)
		if not asset or asset=="" then return end
		local t=Instance.new("Texture"); t.Name="MaterialDetail"; t.Texture=tostring(asset)
		t.Face=face or Enum.NormalId.Top; t.StudsPerTileU=tile or 8; t.StudsPerTileV=tile or 8
		t.Transparency=.12; t.Parent=p; return t
	end
	local function floor(into, name, x,y,z,w,d,color,frame)
		local lawn=color==C.green
		local p=part(into,name,V(w,1.2,d),(frame or CF())*CF(x,y-.6,z),color or C.carpet,lawn and Enum.Material.Grass or Enum.Material.Fabric)
		if lawn then
			material(p,"Grass");p:SetAttribute("LawnSurface",true)
		elseif materials:FindFirstChild(config.MaterialVariants.Carpet) then
			material(p,"Carpet",color and color~=C.carpet and Color3.new(1,1,1):Lerp(color,.32) or nil)
		else
			local surface=texture(p,config.CarpetTexture,Enum.NormalId.Top,8)
			if surface and color and color~=C.carpet then surface.Color3=color end
		end
		floorSurfaces[p]=true
		return p
	end
	local function resolveSharedSideWalls()
		-- Touching homes share one physical partition. On continuous F facades,
		-- neighbouring houses previously emitted the same plaster wall twice.
		-- Subtract only redundant intervals on the exact same plane and height;
		-- preserve outer walls and the exposed ends of differently recessed rooms.
		local groups={}
		for _,p in ipairs(sideWalls) do
			if p.Parent and p.CFrame.UpVector.Y>.99999 then
				local nx=math.abs(p.CFrame.RightVector.X)>.99999
				local nz=math.abs(p.CFrame.RightVector.Z)>.99999
				if nx or nz then
					local f,s=p.CFrame,p.Size
					local tangent=nx and V(0,0,1) or V(1,0,0)
					local plane=nx and f.Position.X or f.Position.Z
					local key=string.format("%s:%.3f:%.3f:%.3f:%.3f",nx and "X" or "Z",plane,f.Position.Y,s.Y,s.X)
					local g=groups[key] or {};groups[key]=g
					local center=f.Position:Dot(tangent)
					table.insert(g,{part=p,key=p:GetFullName(),tangent=tangent,center=center,a=center-s.Z/2,b=center+s.Z/2})
				end
			end
		end
		local removed,trimmed,extra=0,0,0
		for _,g in pairs(groups) do
			table.sort(g,function(a,b) if a.key~=b.key then return a.key<b.key end;return a.a<b.a end)
			local owned={}
			for _,r in ipairs(g) do
				local spans={{r.a,r.b}}
				for _,o in ipairs(owned) do
					local nextSpans={}
					for _,s in ipairs(spans) do
						if o[2]<=s[1]+.001 or o[1]>=s[2]-.001 then table.insert(nextSpans,s)
						else
							if o[1]>s[1]+.01 then table.insert(nextSpans,{s[1],math.min(o[1],s[2])}) end
							if o[2]<s[2]-.01 then table.insert(nextSpans,{math.max(o[2],s[1]),s[2]}) end
						end
					end
					spans=nextSpans
				end
				if #spans==0 then r.part:Destroy();removed+=1
				elseif #spans~=1 or math.abs(spans[1][1]-r.a)>.001 or math.abs(spans[1][2]-r.b)>.001 then
					local originalFrame,originalSize=r.part.CFrame,r.part.Size
					for i,s in ipairs(spans) do
						local p=i==1 and r.part or r.part:Clone()
						p.Size=V(originalSize.X,originalSize.Y,s[2]-s[1])
						p.CFrame=originalFrame+r.tangent*((s[1]+s[2])/2-r.center)
						p:SetAttribute("SharedWallTrimmed",true)
						if i>1 then p.Parent=r.part.Parent;extra+=1 end
					end
					trimmed+=1
				end
				table.insert(owned,{r.a,r.b})
			end
		end
		root:SetAttribute("SharedWallDuplicatesRemoved",removed)
		root:SetAttribute("SharedWallIntervalsTrimmed",trimmed)
		root:SetAttribute("SharedWallRemaindersAdded",extra)
	end
	local function resolveFloorSurfaces()
		-- Adjacent slabs may meet at the same grade, but overlapping textured
		-- faces must have one visible owner. Work only on horizontal floor slabs:
		-- authored stairs, sloping chute, furniture and tilted houses stay exact.
		local separation,maxLift=.12,.48
		local groups={}
		local function rectangle(p)
			if not p:IsA("Part") or p.Shape~=Enum.PartType.Block or p.CFrame.UpVector.Y<.99999 then return nil end
			local f,s=p.CFrame,p.Size
			return {part=p,x=f.Position.X,z=f.Position.Z,u=f.RightVector,v=f.ZVector,hx=s.X/2,hz=s.Z/2,top=f.Position.Y+s.Y/2}
		end
		local function overlaps(a,b)
			local dx,dz=b.x-a.x,b.z-a.z
			for _,axis in ipairs({a.u,a.v,b.u,b.v}) do
				local rA=a.hx*math.abs(a.u:Dot(axis))+a.hz*math.abs(a.v:Dot(axis))
				local rB=b.hx*math.abs(b.u:Dot(axis))+b.hz*math.abs(b.v:Dot(axis))
				-- Shared edges, including the tiny stair tread overlap, are seams
				-- rather than competing surfaces and do not need a height change.
				if math.abs(dx*axis.X+dz*axis.Z)>=rA+rB-.02 then return false end
			end
			return true
		end
		local function grade(y) return math.floor(y*10+.5)/10 end
		for p in pairs(floorSurfaces) do
			if p.Parent then
				local r=rectangle(p)
				if r then
					local y=grade(r.top)
					local g=groups[y] or {floors={},fixed={}};groups[y]=g
					r.authoredTop=r.top;r.room=p.Name=="InteriorCarpet"
					r.key=p:GetFullName();table.insert(g.floors,r)
				end
			end
		end
		-- Foundations finish inside the existing 1.2-stud floor slab, not on its
		-- visible top. This removes their competing face without lifting a whole
		-- district merely because a small gate foundation reaches the same grade.
		local trimmedFoundations=0
		-- Lower-house ceilings can also terminate on a floor grade. Their tops
		-- stay fixed; the floor above must cover them cleanly.
		for _,p in ipairs(root:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide and p.Transparency==0 and not floorSurfaces[p] then
				local r=rectangle(p)
				if r then
					local y=grade(r.top)
					local foundationGroup=groups[y]
					if foundationGroup and p.Name:find("Foundation",1,true) and p.Size.Y>separation then
						for _,f in ipairs(foundationGroup.floors) do
							if math.abs(f.authoredTop-r.top)<.04 and overlaps(r,f) then
								p.Size-=V(0,separation,0);p.CFrame-=V(0,separation/2,0)
								p:SetAttribute("FoundationSurfaceInset",separation)
								r.top-=separation;trimmedFoundations+=1;break
							end
						end
					end
					for _,key in ipairs({y-.1,y,y+.1}) do
						local g=groups[grade(key)]
						if g and math.abs(r.top-grade(key))<.081 then table.insert(g.fixed,r) end
					end
				end
			end
		end
		local adjusted,highest,checked,exposedUndersides,plasterCeilingsRevealed=0,0,0,0,0
		local districtBottom={A_BalconyAtrium=0,B_LowEavesArcade=0,C_PastelVillage=0,D_FloralTerraces=-12,E_DomesticLabyrinth=0,F_BayWindowCanyon=-42,G_TiltedSubdivision=0,H_LastHouse=0}
		for y,g in pairs(groups) do
			-- Large ground/court supports first, then smaller overlay slabs; room
			-- carpets resolve last so gardens never show through house interiors.
			table.sort(g.floors,function(a,b)
				if a.room~=b.room then return not a.room end
				local aa,ba=a.hx*a.hz,b.hx*b.hz
				if math.abs(aa-ba)>.001 then return aa>ba end
				if a.key~=b.key then return a.key<b.key end
				if math.abs(a.x-b.x)>.001 then return a.x<b.x end
				if math.abs(a.z-b.z)>.001 then return a.z<b.z end
				return a.authoredTop<b.authoredTop
			end)
			local placed={}
			for _,r in ipairs(g.floors) do
				local candidates={}
				for _,q in ipairs(g.fixed) do if overlaps(r,q) then table.insert(candidates,q) end end
				for _,q in ipairs(placed) do if overlaps(r,q) then table.insert(candidates,q) end end
				local chosen
				for layer=0,4 do
					local top=y+layer*separation
					if top>=r.authoredTop-.002 and top-r.authoredTop<=maxLift+.002 then
						local clear=true
						for _,q in ipairs(candidates) do
							if top-q.top<separation-.002 then clear=false;break end
						end
						if clear then chosen=math.max(top,r.authoredTop);break end
					end
				end
				assert(chosen,"Level 5 floor surface layers exceed 0.48 studs: "..r.key)
				local lift=chosen-r.authoredTop
				if lift>.002 then
					local p=r.part
					p.Size+=V(0,lift,0);p.CFrame+=V(0,lift/2,0)
					local ancestor=p.Parent;local lowestFloor
					while ancestor and ancestor~=root do
						lowestFloor=districtBottom[ancestor.Name]
						if lowestFloor~=nil then break end
						ancestor=ancestor.Parent
					end
					-- Above playable space, an overlay slab also needs a distinct
					-- underside. Lift that underside by the already-approved top
					-- offset: the slab keeps its original thickness, headroom grows,
					-- and the walking top stays exactly where the first pass put it.
					-- F's dedicated plaster soffits own its visible undersides.
					if not r.room and lowestFloor~=nil and r.authoredTop-origin.Y>lowestFloor+.1
						and p.Name~="CrossingCarpet" and not p.Name:find("CarpetLedge_",1,true) then
						p.Size-=V(0,lift,0);p.CFrame+=V(0,lift/2,0)
						p:SetAttribute("ExposedUndersideLift",lift);exposedUndersides+=1
					end
					p:SetAttribute("SurfaceLift",lift)
					p:SetAttribute("AuthoredFloorTopY",r.authoredTop-origin.Y)
					adjusted+=1;highest=math.max(highest,lift)
				end
				if r.room then
					for _,q in ipairs(candidates) do
						if q.part.Name=="InteriorCeiling" and math.abs(q.top-r.authoredTop)<.081 then
							-- A stacked room's old 1.2-thick carpet slab extended below
							-- the lower room's plaster ceiling, making its roof carpet.
							-- Keep the walking top, and finish this slab .10 below its
							-- authored grade: the plaster ceiling still overlaps it by
							-- .125, so the enclosure remains physically opaque.
							local p=r.part
							local trim=r.authoredTop-.10-(p.Position.Y-p.Size.Y/2)
							if trim>.002 then
								assert(p.Size.Y-trim>.09,"Stacked room floor lost thickness: "..r.key)
								p.Size-=V(0,trim,0);p.CFrame+=V(0,trim/2,0)
								p:SetAttribute("PlasterCeilingUnderlap",.10);plasterCeilingsRevealed+=1
							end
							break
						end
					end
				end
				r.top=chosen;checked+=1;table.insert(placed,r)
			end
		end
		root:SetAttribute("SurfaceOwnershipVersion","2026-09-26.3")
		root:SetAttribute("FloorSurfacesChecked",checked)
		root:SetAttribute("FloorSurfacesSeparated",adjusted)
		root:SetAttribute("MaximumFloorSurfaceLift",highest)
		root:SetAttribute("FloorSurfaceSeparation",separation)
		root:SetAttribute("FoundationSurfacesInset",trimmedFoundations)
		root:SetAttribute("ExposedUndersidesSeparated",exposedUndersides)
		root:SetAttribute("StackedPlasterCeilingsRevealed",plasterCeilingsRevealed)
	end
	local function beam(into,name,a,b,width,color)
		local mid=(a+b)/2
		return part(into,name,V(width,width,(b-a).Magnitude),CFrame.lookAt(mid,b),color or C.white,Enum.Material.SmoothPlastic)
	end
	local function rail(into,frame,width)
		part(into,"RailingTop",V(width,.24,.24),frame*CF(0,3.35,0),C.white)
		part(into,"RailingBottom",V(width,.16,.18),frame*CF(0,.45,0),C.white)
		local n=math.max(1,math.ceil(width/2.15))
		for i=0,n do part(into,"RailingSpindle",V(.13,3,.13),frame*CF(-width/2+width*i/n,1.88,0),C.white) end
	end
	local function stairs(into,name,frame,width,rise,run,steps,color,withRails)
		local m=model(name,into)
		local dh,dd=rise/steps,run/steps
		for i=1,steps do
			local top=dh*i
			-- Each tread is a shallow slab: descending flights never create inverted/negative blocks.
			part(m,"CarpetTread",V(width,.65,dd+.035),frame*CF(0,top-.325,dd*(i-.5)),color or C.carpet,Enum.Material.Fabric)
			part(m,"Riser",V(width,math.abs(dh)+.15,.14),frame*CF(0,top-dh/2-.08,dd*(i-1)),color or C.carpet,Enum.Material.Fabric)
		end
		if withRails then
			for _,s in ipairs({-1,1}) do
				local a=frame:PointToWorldSpace(V(s*(width/2-.18),3,0))
				local b=frame:PointToWorldSpace(V(s*(width/2-.18),rise+3,run))
				beam(m,"StairHandrail",a,b,.24,C.white)
				for i=0,steps,3 do part(m,"StairSpindle",V(.15,3,.15),frame*CF(s*(width/2-.18),rise*i/steps+1.5,run*i/steps),C.white) end
			end
		end
		return m
	end
	local function window(into,frame,w,h,lit,simple)
		local glass=part(into,"WindowGlass",V(w,h,.14),frame,C.glass,Enum.Material.Glass)
		glass.Transparency=.2
		glass.Reflectance=0
		glass:SetAttribute("Level5TintedWindow",true)
		local compactTrim
		if trimTemplates and math.abs(w-10)<.001 and math.abs(h-7.2)<.001
			and into:FindFirstAncestor("F_BayWindowCanyon") then
			local template=trimTemplates:FindFirstChild(simple and "WindowTrimSimple" or "WindowTrimStandard")
			if template and template:IsA("UnionOperation") and template:GetAttribute("Level5WindowTrimTemplate")==true
				and template:GetAttribute("WindowWidth")==10 and template:GetAttribute("WindowHeight")==7.2 then
				compactTrim=template:Clone()
				compactTrim.Name="WindowTrimUnion"
				compactTrim.CFrame=offset*frame*template.CFrame
				compactTrim.Parent=into
				partCount+=1
			end
		end
		if not compactTrim then
			for _,s in ipairs({-1,1}) do
				part(into,"WindowJamb",V(.25,h+.45,.34),frame*CF(s*(w/2+.08),0,-.08),C.white)
				part(into,"WindowSill",V(w+.65,.25,.4),frame*CF(0,s*(h/2+.08),-.12),C.white)
			end
			part(into,"WindowMullion",V(.12,h,.23),frame*CF(0,0,-.09),C.white)
			for _,s in ipairs(simple and {0} or {-.22,.22}) do part(into,"WindowCrossbar",V(w,.12,.23),frame*CF(0,h*s,-.09),C.white) end
		end
		return glass
	end
	local function doorframe(into,frame,width,height)
		-- The white reveal projects .12 into the opening, hiding the plaster
		-- return face rather than sharing its plane. Even the narrowest opening
		-- retains 5.16 studs of clear passage.
		for _,s in ipairs({-1,1}) do part(into,"DoorJamb",V(.4,height+.3,.55),frame*CF(s*(width/2+.08),height/2,-.13),C.white) end
		part(into,"DoorHeader",V(width+.8,.45,.55),frame*CF(0,height+.15,-.13),C.white)
	end
	local function facade(into,frame,w,h,color,openDoor,lit,simple,frontDoorNear)
		local dw,dh=5.4,10.3
		if frontDoorNear then
			-- Only the first +X corridor home uses this frontage. Its real entry
			-- precedes the windows from the S02 approach; the far Watcher pane
			-- stays at virtually the same position as on the standard facade.
			assert(openDoor,"near corridor entry must remain passable")
			local doorX=9
			local farEdge,windowEdge,nearEdge=-w/2,doorX-dw/2,doorX+dw/2
			local windowWidth,endWidth=windowEdge-farEdge,w/2-nearEdge
			local watcherPaneWidth,smallPaneWidth=7.2,3.6
			local middleStart=farEdge+1.15+watcherPaneWidth
			local middleEnd=windowEdge-1.15-smallPaneWidth
			assert(middleEnd-middleStart>=1.15 and endWidth>=1.15,"near corridor entry needs supported windows and wall")
			part(into,"FacadeLintel",V(w,h-dh,.65),frame*CF(0,dh+(h-dh)/2,0),color)
			part(into,"WindowApron",V(windowWidth,2.8,.65),frame*CF((farEdge+windowEdge)/2,1.4,0),color)
			for _,x in ipairs({farEdge+.575,windowEdge-.575}) do
				part(into,"FacadePier",V(1.15,dh-2.8,.65),frame*CF(x,(dh+2.8)/2,0),color)
			end
			part(into,"FacadePier",V(endWidth,dh,.65),frame*CF((nearEdge+w/2)/2,dh/2,0),color)
			local watcherPaneX=farEdge+1.15+watcherPaneWidth/2
			local watcherGlass=window(into,frame*CF(watcherPaneX,6.55,-.18),watcherPaneWidth,7.2,lit,simple)
			watcherGlass.Color=Color3.fromRGB(70,76,72)
			part(into,"FacadePier",V(middleEnd-middleStart,dh-2.8,.65),
				frame*CF((middleStart+middleEnd)/2,(dh+2.8)/2,0),color)
			local smallPaneX=windowEdge-1.15-smallPaneWidth/2
			local smallGlass=window(into,frame*CF(smallPaneX,6.55,-.18),smallPaneWidth,7.2,lit,simple)
			smallGlass.Color=Color3.fromRGB(70,76,72)
			doorframe(into,frame*CF(doorX,0,0),dw,dh)
			part(into,"SplitSkirting",V(windowWidth,.35,.8),frame*CF((farEdge+windowEdge)/2,.18,.08),C.white)
			part(into,"SplitSkirting",V(endWidth,.35,.8),frame*CF((nearEdge+w/2)/2,.18,.08),C.white)
			return
		end
		local sw=(w-dw)/2
		part(into,"FacadeLintel",V(w,h-dh,.65),frame*CF(0,dh+(h-dh)/2,0),color)
		for _,s in ipairs({-1,1}) do
			local x=s*(dw/2+sw/2)
			part(into,"WindowApron",V(sw,2.8,.65),frame*CF(x,1.4,0),color)
			-- The apron already fills y0..2.8. Piers start above it so their
			-- independently tiled front faces never occupy the same wall plane.
			for _,j in ipairs({-1,1}) do part(into,"FacadePier",V(1.15,dh-2.8,.65),frame*CF(x+j*(sw/2-.575),(dh+2.8)/2,0),color) end
			-- Broad houses retain domestic window proportions rather than one
			-- shopfront-length ribbon. Narrow curated Watcher homes stay exact.
			local clearWidth=sw-2.3
			local count=sw>16 and math.clamp(math.ceil(clearWidth/11),2,3) or 1
			local pier=.85
			local paneWidth=(clearWidth-(count-1)*pier)/count
			for i=1,count do
				local px=x-clearWidth/2+paneWidth/2+(i-1)*(paneWidth+pier)
				window(into,frame*CF(px,6.55,-.18),paneWidth,7.2,lit,simple)
				if i<count then part(into,"FacadePier",V(pier,dh-2.8,.65),frame*CF(px+paneWidth/2+pier/2,(dh+2.8)/2,0),color) end
			end
		end
		doorframe(into,frame,dw,dh)
		if not openDoor then
			part(into,"ClosedPanelDoor",V(dw,dh,.32),frame*CF(0,dh/2,.05),C.white,Enum.Material.Wood)
			if simple then
				part(into,"ScenicDoorInset",V(dw-.9,dh-1.3,.13),frame*CF(0,dh/2,-.18),C.pale,Enum.Material.Wood)
			else
				for _,y in ipairs({2.4,6.6,8.7}) do for _,x in ipairs({-1.25,1.25}) do part(into,"DoorRaisedPanel",V(1.85,y==6.6 and 2.8 or 1.25,.13),frame*CF(x,y,-.18),C.pale,Enum.Material.Wood) end end
				local knob=part(into,"BrassDoorKnob",V(.27,.27,.4),frame*CF(2,4.6,-.4),Color3.fromRGB(137,119,65),Enum.Material.Metal); knob.Shape=Enum.PartType.Ball
			end
		end
		part(into,"FacadeSkirting",V(w,.42,.8),frame*CF(0,.25,.08),C.white)
		-- Split the skirting at an open doorway so there is no trip-sized threshold.
		if openDoor then
			local last=into:FindFirstChild("FacadeSkirting")
			if last then last:Destroy(); partCount-=1 end
			for _,sign in ipairs({-1,1}) do part(into,"SplitSkirting",V(sw,.35,.8),frame*CF(sign*(dw/2+sw/2),.18,.08),C.white) end
		end
	end
	local function wallLamp(_into,_frame)
		-- Individual homes have no exterior/interior lamps or luminous fixtures.
		-- Shared room ceilings provide the architectural light.
	end
	local function house(into,name,frame,w,d,h,color,roofColor,options)
		options=options or {}; local m=model(name,into)
		m:SetAttribute("Enterable",options.open~=false)
		m:SetAttribute("HouseFloorFrame",offset*frame)
		m:SetAttribute("HouseRoomSize",V(w,h,d))
		m:SetAttribute("HouseWindowFloorY",(offset*frame).Position.Y)
		-- Unreachable upper houses retain the full silhouette, glass, floor and
		-- enclosure; only tiny or invisible details use a cheaper static variant.
		local scenic=options.open==false and frame.Position.Y>=13
		m:SetAttribute("ScenicUpperDetail",scenic)
		if scenic then part(m,"InteriorCarpet",V(w,1.2,d),frame*CF(0,-.6,d/2),C.carpet,Enum.Material.Fabric)
		else floor(m,"InteriorCarpet",0,0,d/2,w,d,C.carpet,frame) end
		if options.cutaway then
			-- A few upper rooms have exposed wall sections, as in the reference.
			-- These are fixed architectural cuts rather than destructible objects.
			if options.open then
				-- Walkable cutaway rooms retain broken wall edges around a clear entrance.
				local wing=(w-7)/2
				for _,sign in ipairs({-1,1}) do part(m,"CutawayWallApron",V(wing,2.4,.7),frame*CF(sign*(3.5+wing/2),1.2,0),color,Enum.Material.Plaster) end
			else
				part(m,"CutawayWallApron",V(w,2.4,.7),frame*CF(0,1.2,0),color,Enum.Material.Plaster)
			end
			part(m,"CutawayHeader",V(w,1,.7),frame*CF(0,h-.5,0),color,Enum.Material.Plaster)
			part(m,"CutawayTallPier",V(1.3,h,.9),frame*CF(-w/2+.65,h/2,0),color,Enum.Material.Plaster)
			part(m,"CutawayShortPier",V(1.3,5.3,.9),frame*CF(w/2-.65,2.65,0),color,Enum.Material.Plaster)
			for i=0,3 do
				part(m,"ExposedPlasterEdge",V(.38,1.15,.95),frame*CF(-w/2+1.35,3.5+i*2.3,-.05)*CFrame.Angles(0,0,math.rad(i%2==0 and 12 or -9)),C.white,Enum.Material.Plaster)
			end
		else facade(m,frame,w,h,color,options.open~=false,options.lit,scenic,options.frontDoorNear) end
		for _,s in ipairs({-1,1}) do
			part(m,"SideWall",V(.65,h,d),frame*CF(s*w/2,h/2,d/2),color)
			if not scenic then part(m,"InteriorBaseboard",V(.18,.5,d),frame*CF(s*(w/2-.4),.25,d/2),C.white) end
		end
		if options.backOpening then
			local wing=(w-7)/2
			for _,s in ipairs({-1,1}) do part(m,"BackWallWing",V(wing,h,.65),frame*CF(s*(3.5+wing/2),h/2,d),color) end
			part(m,"BackWallHeader",V(7,h-10,.65),frame*CF(0,10+(h-10)/2,d),color)
			doorframe(m,frame*CF(0,0,d),7,10)
		else part(m,"BackWall",V(w,h,.65),frame*CF(0,h/2,d),color) end
		-- Ceiling edges terminate inside the .65-thick walls, overlapping them
		-- by .205 studs while avoiding the upper floor's exposed perimeter plane.
		local conjoinedSide=into.Name=="C_PastelVillage" and name:match("^CrossStreetCottage_([%-]?1)_3_0$")
		if conjoinedSide then
			-- These two cottages meet the rear court houses at a right angle.
			-- Their court-side ceiling corner already belongs to the neighbouring
			-- CourtHouse ceiling. Keep the exact solid union with two L-shaped
			-- remainder panels, rather than drawing two broadloom/plaster planes
			-- over each other inside the joined rooms.
			local side=tonumber(conjoinedSide)
			local splitZ=11.12;local rearLength=d-.12-splitZ
			part(m,"InteriorCeiling",V(w-.24,.45,splitZ-.12),frame*CF(0,h,(splitZ+.12)/2),C.ceiling)
			part(m,"InteriorCeiling",V(w/2,.45,rearLength),frame*CF(side*(w/4-.12),h,(splitZ+d-.12)/2),C.ceiling)
			m:SetAttribute("SharedCourtCeilingOwner",false)
		else
			part(m,"InteriorCeiling",V(w-.24,.45,d-.24),frame*CF(0,h,d/2),C.ceiling)
		end
		m:SetAttribute("HouseLighting","None")
		part(m,"CrownMoulding",V(w+.6,.5,.85),frame*CF(0,h-.15,-.08),C.white)
		for _,s in ipairs({-1,1}) do wallLamp(m,frame*CF(s*(w/2-1.2),10.8,-.55)) end
		if roofColor then
			local pitch=math.rad(32); local half=w/2+1.1; local slant=half/math.cos(pitch)
			local gableRise=(w/2)*math.tan(pitch)
			local gableBase=.5+1.1*math.tan(pitch)
			part(m,"GableBaseBand",V(w,gableBase,.6),frame*CF(0,h+gableBase/2,-.03),color)
			for _,s in ipairs({-1,1}) do
				local roofFrame=frame*CF(s*half/2,h+half*math.tan(pitch)/2+.5,d/2)*CFrame.Angles(0,0,-s*pitch)
				part(m,"PitchedRoof",V(slant,.48,d+2),roofFrame,roofColor,Enum.Material.Slate)
				part(m,"RoofCladdingSeam",V(.08,.065,d+1.9),roofFrame*CF(0,.27,0),Color3.fromRGB(112,117,129),Enum.Material.Slate,false)
				part(m,"WhiteGableTrim",V(slant,.3,.45),frame*CF(s*half/2,h+half*math.tan(pitch)/2+.6,-1.1)*CFrame.Angles(0,0,-s*pitch),C.white)
				part(m,"ClosedGableTriangle",V(.6,gableRise,w/2),frame*CF(s*w/4,h+gableBase+gableRise/2,-.03)*CFrame.Angles(0,-s*math.pi/2,0),color,Enum.Material.SmoothPlastic,true,"WedgePart")
			end
			part(m,"RoofRidge",V(.35,.35,d+2.4),frame*CF(0,h+half*math.tan(pitch)+.5,d/2),roofColor)
		end
		-- Selected houses have a genuine central hall and two separate side rooms.
		-- The hall and rear clue wall stay clear; room furniture lives beside the
		-- exterior walls. All internal doorways are full human height.
		if options.completeHome and options.open~=false and w>=30 and d>=22 then
			m:SetAttribute("CompleteHome",true);m:SetAttribute("RoomCount",3)
			for _,side in ipairs({-1,1}) do
				material(part(m,"InteriorPlasterLining",V(.025,h-.2,d-.65),frame*CF(side*(w/2-.345),h/2,d/2),C.pale,Enum.Material.Plaster),"Plaster")
			end
			if not options.backOpening then material(part(m,"InteriorBackPlasterLining",V(w-.7,h-.2,.025),frame*CF(0,h/2,d-.345),C.pale,Enum.Material.Plaster),"Plaster") end
			local doorZ=d*.48;local opening=6.5;local front=3;local rear=d-.65
			for _,side in ipairs({-1,1}) do
				for _,span in ipairs({{front,doorZ-opening/2},{doorZ+opening/2,rear}}) do
					if span[2]>span[1] then
						local p=part(m,"WallpaperRoomPartition",V(.4,h,span[2]-span[1]),frame*CF(side*5.5,h/2,(span[1]+span[2])/2),C.pale,Enum.Material.Plaster)
						material(p,"Wallpaper")
					end
				end
				material(part(m,"RoomDoorLintel",V(.4,h-10,opening),frame*CF(side*5.5,10+(h-10)/2,doorZ),C.pale,Enum.Material.Plaster),"Wallpaper")
				doorframe(m,frame*CF(side*5.5,0,doorZ)*CFrame.Angles(0,math.pi/2,0),opening,10)
			end
		end
		if options.open~=false and math.abs(frame.Position.Y)<.1 and not options.backOpening then
			m:SetAttribute("HousePuzzleCandidate",true)
			local hint=part(m,"PuzzleHintSurface",V(6,5,.03),frame*CF(0,6,d-.38),C.white,nil,false)
			hint.Transparency=1;hint.CastShadow=false;hint:SetAttribute("ReservedBlankClueArea",true)
		end
		local colorful=color==C.rose or color==C.pink or color==C.blue or color==C.lavender or color==C.yellow
		local pastel=Color3.new(1,1,1):Lerp(color or C.cream,colorful and .55 or .3)
		for _,surface in ipairs(m:GetChildren()) do
			if surface:IsA("BasePart") then
				local n=surface.Name
				if n=="SideWall" or n=="BackWall" or n=="BackWallWing" or n=="BackWallHeader" or n=="FacadeLintel" or n=="WindowApron" or n=="FacadePier" or n=="GableBaseBand" or n=="ClosedGableTriangle" then material(surface,"Siding",pastel)
				elseif n=="InteriorCeiling" then material(surface,"Plaster") end
			end
		end
		local variant=options.furniture
		if furnitureKit and variant and options.open~=false then
			Furniture.FurnishHome(furnitureKit,m,frame,w,d,h,{variant=variant,open=true,backOpening=options.backOpening,glitchedTable=options.glitchedTable==true})
			m:SetAttribute("FurnitureRoomFrame",offset*frame)
			m:SetAttribute("FurnitureRoomSize",V(w,h,d))
		end
		return m
	end
	local function ceiling(into,name,x,z,w,d,y,style)
		local m=model(name,into)
		local tint=style=="courtyard" and Color3.fromRGB(139,135,132)
			or (style=="domestic" and C.pale or (style=="low" and Color3.fromRGB(177,172,145) or C.ceiling))
		local plane=material(part(m,"CeilingPlane",V(w+12,8,d+12),CF(x,y+3.7,z),tint,Enum.Material.Plaster),"Plaster")
		if style=="courtyard" then plane.Color=tint end
		if name=="Pastel Carpet VillagesCeiling" then
			plane.MaterialVariant=""
			plane.Color=Color3.fromRGB(236,233,225)
		end
		local tile=y>70 and 24 or style=="domestic" and 12 or 18
		for xx=-w/2,w/2,tile do part(m,"CeilingGrid",V(.08,.08,d),CF(x+xx,y-.34,z),C.grid,nil,false) end
		for zz=-d/2,d/2,tile do part(m,"CeilingGrid",V(w,.08,.08),CF(x,y-.34,z+zz),C.grid,nil,false) end
		local sx,sz=y>70 and 56 or 40,y>70 and 56 or 40
		local ix=0
		for xx=-w/2+sx/2,w/2-8,sx do for zz=-d/2+sz/2,d/2-7,sz do
			ix+=1
			-- Static tube wear: different colour temperatures, weak ballast output
			-- and truly dead panels. No strobing or per-frame light loops.
			local pattern=ix+math.floor(z/40)
			local failed=pattern%7==0
			local dim=not failed and pattern%5==0
			local warmth=(pattern+math.floor(x/20))%3
			local fixtureColor=warmth==0 and Color3.fromRGB(223,208,167)
				or warmth==1 and Color3.fromRGB(185,211,219) or Color3.fromRGB(214,222,202)
			local lightColor=warmth==0 and Color3.fromRGB(250,223,178)
				or warmth==1 and Color3.fromRGB(212,231,245) or Color3.fromRGB(232,236,211)
			if style=="low" and warmth~=1 then fixtureColor=Color3.fromRGB(207,195,153) end
			if dim then fixtureColor=fixtureColor:Lerp(Color3.fromRGB(80,83,69),.48) end
			if failed then fixtureColor=Color3.fromRGB(67,65,56) end
				local villageSquare=name=="Pastel Carpet VillagesCeiling"
				local p=part(m,"FluorescentPanel",V(style=="courtyard" and 3 or (style=="domestic" and 4 or 8),.13,villageSquare and 8 or (style=="courtyard" and 3 or 2.6)),CF(x+xx,y-.46,z+zz),fixtureColor,failed and Enum.Material.SmoothPlastic or Enum.Material.Neon,false)
			p:SetAttribute("FailedTube",failed)
			p:SetAttribute("TubeState",failed and "Off" or dim and "Dim" or "On")
			p:SetAttribute("ColourTemperature",warmth==0 and "Warm" or warmth==1 and "Cool" or "Neutral")
				part(m,"LightPanelFrame",V(p.Size.X+.4,.12,villageSquare and 8.4 or (style=="courtyard" and 3.4 or 3)),CF(x+xx,y-.34,z+zz),C.white,nil,false)
			if y<=60 and ix%4==1 and not failed then
				local light=Instance.new("SurfaceLight");light.Face=Enum.NormalId.Bottom;light.Color=lightColor
				light.Brightness=dim and .3 or warmth==1 and .72 or .95
				light.Range=math.min(y+8,60);light.Angle=160;light.Shadows=false;light.Parent=p;lightCount+=1
			end
		end end
		if style=="warehouse" then
			for zz=-d/2+10,d/2,36 do
				part(m,"ExposedCeilingBeam",V(w,.8,.6),CF(x,y-1.3,z+zz),C.white,nil,false)
				for xx=-w/2+25,w/2-5,50 do
					beam(m,"WarehouseTrussDiagonal",V(x+xx-18,y-1.6,z+zz),V(x+xx+18,y-5.7,z+zz),.22,C.pale)
				end
			end
		end
	end

	local function boundary(into,x,z,w,d,height)
		for _,s in ipairs({-1,1}) do part(into,"EnclosureWall",V(1.2,height,d),CF(x+s*w/2,height/2,z),C.cream) end
	end
	local function bay(into,frame,w,h,lit)
		local center=w*.52; local side=w*.31
		part(into,"BayBase",V(w,2.6,4.4),frame*CF(0,1.3,-1.8),C.pale)
		window(into,frame*CF(0,2.6+h/2,-4),center,h,lit)
		for _,s in ipairs({-1,1}) do
			window(into,frame*CF(s*(center/2+side*.32),2.6+h/2,-2.5)*CFrame.Angles(0,s*math.rad(42),0),side,h,lit)
		end
		part(into,"BayCornice",V(w+.8,.55,4.9),frame*CF(0,h+2.95,-1.8),C.white)
	end

	local K={root=root,config=config,C=C,V=V,CF=CF,model=model,part=part,floor=floor,
		beam=beam,rail=rail,stairs=stairs,window=window,doorframe=doorframe,facade=facade,
		house=house,texture=texture,wallLamp=wallLamp,bay=bay,ceiling=ceiling,material=material}
	furnitureKit=K

	-- Curated panes use real supporting rooms. The origin remains private to this
	-- module; exposed floor frames are world-space for puzzle/Watcher consumers.
	local anchors=Instance.new("Folder");anchors.Name="WindowWatcherAnchors";anchors.Parent=parent
	local function registerWatcher(home,name,district,index)
		local panes={}
		for _,v in ipairs(home:GetDescendants()) do
			-- Vector3 dimensions round through float32: authored 7.2 becomes 7.1999998.
			if v:IsA("BasePart") and v:GetAttribute("Level5TintedWindow")==true and v.Size.X>=6.79 and v.Size.Y>=7.19 then table.insert(panes,v) end
		end
		local pane=panes[index or 1]
		assert(pane,"Watcher home requires a full-height standard pane: "..home.Name)
		local a=Instance.new("Part");a.Name=name;a.Size=V(.2,.2,.2);a.CFrame=pane.CFrame
		a.Anchored=true;a.Transparency=1;a.CanCollide=false;a.CanQuery=false;a.CanTouch=false;a.CastShadow=false
		a:SetAttribute("District",district);a:SetAttribute("FloorCFrame",pane.CFrame*CF(0,-6.55,0))
		a:SetAttribute("PawnDepth",1.90);a:SetAttribute("InteriorClearanceDepth",home:GetAttribute("HouseRoomSize").Z)
		a:SetAttribute("Level5WindowWatcherAnchor",true);a.Parent=anchors
		local v=Instance.new("ObjectValue");v.Name="WindowGlass";v.Value=pane;v.Parent=a
		local h=Instance.new("ObjectValue");h.Name="SupportingHouse";h.Value=home;h.Parent=a
		return a
	end
	local function edgeRail(into,x,y,z0,z1,gaps)
		local cursor=z0
		for _,gap in ipairs(gaps or {}) do
			if gap[1]>cursor then rail(into,CF(x,y,(cursor+gap[1])/2)*CFrame.Angles(0,math.pi/2,0),gap[1]-cursor) end
			cursor=math.max(cursor,gap[2])
		end
		if cursor<z1 then rail(into,CF(x,y,(cursor+z1)/2)*CFrame.Angles(0,math.pi/2,0),z1-cursor) end
	end
	K.registerWatcher=registerWatcher;K.edgeRail=edgeRail
	local yaw=function(a) return CFrame.Angles(0,math.rad(a),0) end
	local A=model("A_BalconyAtrium")
	local courtyardLawn=floor(A,"PlantedCourtyardLawn",0,0,96,320,200,C.green)
	courtyardLawn.Color=Color3.fromRGB(88,108,72)
	courtyardLawn.MaterialVariant=""
	local lawnDetail=texture(courtyardLawn,"rbxassetid://108216315862080",Enum.NormalId.Top,8)
	if lawnDetail then lawnDetail.Transparency=.52 end
	local clueIndex=0
	for _,side in ipairs({-1,1}) do
		for i,z in ipairs({42,99,156}) do
			local stack=model("ResidentialAtriumStack_"..side.."_"..i,A)
			local storeys=(side<0 and {5,7,4} or {6,4,7})[i]
			stack:SetAttribute("StoreyCount",1)
			stack:SetAttribute("OriginalStoreyCount",storeys)
			-- Only the ground room remains. Its four numbered clues and two
			-- Watcher panes are real; the upper two levels are rebuilt as continuous
			-- apartment frontage against the balcony core below.
			for level=0,0 do
				local x=side*(110+(level>=3 and (i%2)*3 or 0))
				local f=CF(x,level*14,z)*yaw(side*90)
				local home=house(stack,"AtriumHome_"..level,f,30,24,13.8,(level+i)%3==0 and C.pale or C.cream,level==storeys-1 and C.blue or nil,{open=level<=2,furniture=level==0 and i==2 and (side<0 and 2 or 4) or nil})
				if level==0 and i~=2 then
					clueIndex+=1;home.Name="ClueHouse_"..clueIndex;home:SetAttribute("PuzzleClueIndex",clueIndex)
					local clue=part(home,"PuzzleClueSurface",V(4,5,.03),f*CF(0,6,23.62),C.white,nil,false)
					clue.Transparency=1;clue:SetAttribute("ClueIndex",clueIndex)
				end
				if level==0 and i==1 then registerWatcher(home,"AtriumWindow_"..side,A.Name) end
			end
		end
		for _,y in ipairs({14,28}) do
			floor(A,"ContinuousBalcony",side*96,y,99,28,168)
			-- The old upper room carpets filled this 24-stud band between the
			-- playable gallery and the apartment core. A continuous collidable
			-- extension keeps the gallery usable after those boxes are retired.
			-- A thin slab keeps its underside above the ground rooms' plaster
			-- ceilings, unlike a full-depth house carpet in this same footprint.
			part(A,"LowerReferenceBalconyExtension",V(24,.24,168),CF(side*122,y-.08,99),C.carpet,Enum.Material.Fabric)
			local gaps=y==14 and (side<0 and {{48,59},{92,106}} or {{92,108}}) or {{136,150},{155,169}}
			edgeRail(A,side*82,y,15,183,gaps)
			rail(A,CF(side*96,y,15),28);rail(A,CF(side*96,y,183),28)
		end
		for _,z in ipairs({20,178}) do part(A,"StackSupportColumn",V(2.5,42,2.5),CF(side*82,21,z),C.pale) end
	end
	floor(A,"FirstCrossBridge",0,14,99,194,14)
	rail(A,CF(0,14,92),164)
	-- The upper-flight entrance crosses the rear edge at X65. Retain the
	-- protective rail except for its sixteen-stud stair approach opening.
	rail(A,CF(-12.5,14,106),139) -- -82..57
	rail(A,CF(77.5,14,106),9) -- 73..82
	floor(A,"UpperCrossBridge",0,28,162,194,14)
	for _,z in ipairs({155,169}) do rail(A,CF(0,28,z),164) end
	stairs(A,"GroundToFirstBalcony",CF(-65,0,18),12,14,30,28,C.carpet,true)
	floor(A,"FirstBalconyLanding",-80.5,14,53,43,10)
	stairs(A,"FirstToUpperBalcony",CF(65,14,108),12,14,30,28,C.carpet,true)
	floor(A,"UpperFlightBase",80.5,14,103,43,10)
	floor(A,"UpperFlightLanding",80.5,28,143,43,10)
	local courtyard=model("S01_PlantedCourtyard",A)
	courtyard:SetAttribute("ReferenceViewId",1)
	-- The existing ground slab remains the support. Thin scenic paving and soil
	-- sit above it without entering the floor-ownership pass or obstructing feet.
	local walkPoints={V(-48,0,5),V(-40,0,39),V(-9,0,59),V(35,0,77),V(35,0,104),V(0,0,108),V(8,0,137),V(-6,0,166),V(0,0,184),V(0,0,196)}
	for i=1,#walkPoints-1 do
		local a,b=walkPoints[i],walkPoints[i+1]
		local midpoint=(a+b)/2
		part(courtyard,"CurvedPaleWalk",V(8.5,.12,(b-a).Magnitude+1),CFrame.lookAt(midpoint+V(0,.07,0),b+V(0,.07,0)),Color3.fromRGB(145,143,127),Enum.Material.Concrete,false)
	end
	-- The photographed courtyard receives a low, diffuse bounce from the
	-- balcony and cottage lighting. Without it the dark lawn texture disappears
	-- into black in the actual round while the ceiling panels remain visible.
	for _,z in ipairs({35,105,175}) do
		for _,x in ipairs({-72,72}) do
			local emitter=part(courtyard,"CourtyardDiffuseBounce",V(.2,.2,.2),CF(x,24,z),C.white,nil,false)
			emitter.Transparency=1
			local light=Instance.new("PointLight")
			light.Brightness=.85;light.Range=56;light.Shadows=false
			light.Color=Color3.fromRGB(218,211,184);light.Parent=emitter
		end
	end
	for bedIndex,bed in ipairs({{-25,19,20,12},{-27,56,18,14},{-31,96,20,13},{-27,138,18,16},{25,17,15,12},{56,58,19,13},{63,111,18,11},{51,175,17,11}}) do
		part(courtyard,"PlantedSoil",V(bed[3],.16,bed[4]),CF(bed[1],.08,bed[2]),Color3.fromRGB(61,54,45),Enum.Material.Ground,false)
		local height=5.5+(bedIndex%3)*.45
		local texture=bedIndex%3==0 and "rbxassetid://114091435155355" or "rbxassetid://96127727672974"
		for plane=0,1 do
			local card=part(courtyard,"PlantedShrubCutout",V(height*2,height,.12),CF(bed[1],height/2,bed[2])*CFrame.Angles(0,math.rad(25+bedIndex*11+plane*90),0),C.white,Enum.Material.SmoothPlastic,false)
			card.Transparency=1;card.CanQuery=false;card.CanTouch=false;card.CastShadow=false
			for _,face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back}) do
				local decal=Instance.new("Decal")
				decal.Name="GeneratedGardenCutout";decal.Face=face;decal.Texture=texture;decal.Parent=card
			end
		end
	end
	for _,tree in ipairs({{58,35,9},{69,143,8},{-57,134,7}}) do
		part(courtyard,"BareTreeTrunk",V(.55,tree[3],.55),CF(tree[1],tree[3]/2,tree[2]),Color3.fromRGB(83,72,56),Enum.Material.Wood,false)
		for branch=1,3 do
			beam(courtyard,"BareTreeBranch",V(tree[1],tree[3]*.62,tree[2]),V(tree[1]+(branch-2)*3,tree[3]+branch*.7,tree[2]+(branch%2==0 and 2 or -2)),.18,Color3.fromRGB(83,72,56))
		end
	end

	-- A close cream wall, deep tiered balconies and exposed switchback flights
	-- replace the closed upper houses. The central non-clue hall also gives
	-- way to an open garden path. Clue homes, Watcher supports, lower galleries,
	-- and their playable stairs/crossings remain intact beneath these tiers.
	local towers=model("ReferenceApartmentCanyon",courtyard)
	local leftWall=part(towers,"NearCreamWindowWall",V(2,210,63),CF(-147,105,28),Color3.fromRGB(220,211,190),Enum.Material.Plaster,false)
	leftWall.CastShadow=false
	for level=0,14 do
		for _,z in ipairs({6,22,39,56}) do
			part(towers,"NearNarrowDarkWindow",V(.18,6,3.5),CF(-145.84,8+level*14,z),C.glass,Enum.Material.Glass,false)
			part(towers,"NearWindowCrossbar",V(.22,.13,3.6),CF(-145.72,8+level*14,z),C.white,nil,false)
		end
	end
	for _,side in ipairs({-1,1}) do
		local core=part(towers,"RecessedApartmentCore",V(3,211,179),CF(side*136,105.5,99),Color3.fromRGB(219,211,190),Enum.Material.Plaster)
		core.CastShadow=false
		for _,z in ipairs({15,70,127,183}) do
			part(towers,"VerticalBalconyPier",V(3.4,211,2.2),CF(side*134,105.5,z),C.white,Enum.Material.Plaster,false)
		end
		for level=1,14 do
			local y=level*14
			for bay,z in ipairs({42,99,156}) do
				-- The narrow left window wall has plaster behind its windows;
				-- charcoal recesses belong to the deep balconies opposite it.
				local recessTint=side>0 and Color3.fromRGB(125,123,115) or Color3.fromRGB(111,109,103)
				part(towers,"DarkBalconyRecess",V(.22,8.3,39),CF(side*134.25,y+5,z),recessTint,nil,false)
				for _,dz in ipairs({-10,10}) do
					part(towers,"UpperApartmentWindow",V(.24,6.8,6),CF(side*134.02,y+5,z+dz),C.glass,Enum.Material.Glass,false)
					part(towers,"UpperWindowMullion",V(.28,.16,6),CF(side*133.82,y+5,z+dz),C.white,nil,false)
				end
				-- The reference has a close, narrow window wall on the left and
				-- deep apartment balconies predominantly on the right. Keep the
				-- playable lower galleries untouched beneath these scenic tiers.
				if level<=2 then
					-- Real lower floors and rails already run continuously in front
					-- of these windows; adding a second scenic slab here would overlap
					-- their walking surface and recreate the legacy stacked-house seam.
					part(towers,"LowerApartmentDoorPanel",V(.25,9,5),CF(side*134.01,y+4.6,z),Color3.fromRGB(76,83,79),Enum.Material.Wood,false)
					for _,dz in ipairs({-2.7,2.7}) do
						part(towers,"LowerApartmentDoorJamb",V(.34,9.5,.3),CF(side*133.82,y+4.6,z+dz),C.white,nil,false)
					end
				elseif side>0 or (level%3==0 and bay==2) then
					local slabDepth=side>0 and 10 or 16
					local slabX=side>0 and 128 or 125
					local railX=side>0 and 122.7 or 116.7
					part(towers,"ProjectingBalconySlab",V(slabDepth,.65,43),CF(side*slabX,y-.25,z),C.pale,Enum.Material.Plaster,false)
					part(towers,"BalconyFrontTop",V(.35,.3,41),CF(side*railX,y+3.2,z),C.white,nil,false)
					part(towers,"BalconyFrontBottom",V(.3,.2,41),CF(side*railX,y+.55,z),C.white,nil,false)
					if level<=7 or bay==2 then
						for post=1,5 do part(towers,"BalconySpindle",V(.16,2.6,.16),CF(side*railX,y+1.85,z-20.5+post*41/6),C.white,nil,false) end
					end
				end
			end
		end
	end
	local flights=model("UpperSwitchbackSilhouette",towers)
	for level=3,11 do
		local y=level*14
		local sign=level%2==0 and 1 or -1
		part(flights,"ZigzagStairLanding",V(9,.6,6),CF(-76,y,125),C.pale,Enum.Material.Plaster,false)
		local slant=CF(-76-sign*7,y+7,125)*CFrame.Angles(0,0,-sign*math.rad(45))
		part(flights,"VisibleStairFlight",V(19.8,.55,5),slant,C.pale,Enum.Material.Concrete,false)
		for _,edge in ipairs({-1,1}) do
			part(flights,"VisibleStairRail",V(19.8,.2,.2),slant*CF(0,2.8,edge*2.5),C.white,nil,false)
		end
	end

	local function porch(home,frame,width,depth)
		part(home,"ReferencePorchDeck",V(width-1,.35,depth),frame*CF(0,.18,-depth/2),C.pale,Enum.Material.Concrete,false)
		for _,sign in ipairs({-1,1}) do
			part(home,"ReferencePorchRoof",V(width*.55,.45,depth+1),frame*CF(sign*width/4,11.6,-depth/2)*CFrame.Angles(0,0,-sign*math.rad(16)),C.dark,Enum.Material.Slate,false)
			part(home,"WhitePorchColumn",V(.55,10.8,.55),frame*CF(sign*(width/2-1),5.4,-depth+.35),C.white,nil,false)
		end
		local lamp=part(home,"WarmEntryLamp",V(.6,.8,.35),frame*CF(width*.28,7,-.45),Color3.fromRGB(255,210,145),Enum.Material.Neon,false)
		local light=Instance.new("PointLight");light.Brightness=.5;light.Range=13;light.Color=Color3.fromRGB(255,212,153);light.Parent=lamp
	end
	local function referenceClapboard(home,siding,roofTint)
		local exterior={SideWall=true,BackWall=true,BackWallWing=true,BackWallHeader=true,
			FacadeLintel=true,WindowApron=true,FacadePier=true,GableBaseBand=true,ClosedGableTriangle=true}
		for _,piece in ipairs(home:GetDescendants()) do
			if piece:IsA("BasePart") then
				if exterior[piece.Name] then
					-- The dedicated Studio MaterialVariant keeps the photographed
					-- horizontal clapboard on the courtyard and corridor homes.
					piece.Material=Enum.Material.WoodPlanks
					piece.MaterialVariant="Level5CourtyardClapboard"
					piece.Color=siding
				elseif piece.Name=="PitchedRoof" or piece.Name=="RoofRidge" or piece.Name=="RoofCladdingSeam" then
					piece.MaterialVariant="";piece.Material=Enum.Material.Slate;piece.Color=roofTint
				end
			end
		end
	end
	for _,side in ipairs({-1,1}) do
		local waitingFrame=CF(side*42,0,128)
		local waitingTint=side<0 and Color3.fromRGB(184,177,159) or Color3.fromRGB(137,151,127)
		local waiting=house(A,"GroundWaitingCottage_"..side,waitingFrame,26,24,13.8,waitingTint,C.dark,{open=true})
		referenceClapboard(waiting,waitingTint,Color3.fromRGB(54,59,56))
		porch(waiting,waitingFrame,26,6)
		local innerFrame=CF(side*44,0,76)*yaw(side*90)
		local innerTint=side>0 and Color3.fromRGB(163,170,147) or Color3.fromRGB(138,151,129)
		local inner=house(A,"AtriumInnerStack_"..side.."_0",innerFrame,28,24,13.8,innerTint,C.dark,{open=true})
		referenceClapboard(inner,innerTint,Color3.fromRGB(59,63,59))
		if side>0 then porch(inner,innerFrame,28,5) end
		local rearFrame=CF(side*26,0,163)
		local rearTint=side<0 and Color3.fromRGB(177,173,156) or Color3.fromRGB(182,180,163)
		local rear=house(A,"AtriumRearCottage_"..side,rearFrame,26,22,13.8,rearTint,C.dark,{open=true})
		referenceClapboard(rear,rearTint,Color3.fromRGB(66,68,60))
		if side>0 then porch(rear,rearFrame,26,5) end
	end
	local nearFrame=CF(56,0,28)
	local near=house(courtyard,"SageNearPorchHouse",nearFrame,28,24,13.8,Color3.fromRGB(184,177,159),C.dark,{open=true})
	referenceClapboard(near,Color3.fromRGB(184,177,159),Color3.fromRGB(47,54,53))
	porch(near,nearFrame,28,7)
	-- This courtyard is inside the vast residential shell. Close the upper
	-- envelope before the next zone; otherwise the playable route exposes the
	-- outdoor sky even though the reference has a continuous fluorescent roof.
	local roof=model("S01_EnclosedAtriumRoof",A)
	part(roof,"SuspendedTilePlane",V(336,2,218),CF(0,214,95),Color3.fromRGB(143,142,148),Enum.Material.SmoothPlastic)
	for x=-162,162,18 do
		local grid=part(roof,"LongCeilingGrid",V(.13,.12,216),CF(x,212.91,95),Color3.fromRGB(105,105,110),nil,false)
		grid.Transparency=.18
	end
	for z=-12,202,18 do
		local grid=part(roof,"CrossCeilingGrid",V(334,.12,.13),CF(0,212.91,z),Color3.fromRGB(105,105,110),nil,false)
		grid.Transparency=.18
	end
	for _,x in ipairs({-108,-36,36,108}) do
		for _,z in ipairs({8,35,62,89,116,143,170,197}) do
			local panel=part(roof,"FluorescentRoofPanel",V(3,.13,2.4),CF(x,212.78,z),Color3.fromRGB(210,212,205),Enum.Material.Neon,false)
			local light=Instance.new("SurfaceLight");light.Face=Enum.NormalId.Bottom;light.Brightness=.65
			light.Range=28;light.Angle=150;light.Shadows=false;light.Parent=panel
		end
	end
	for _,x in ipairs({-81,81}) do
		part(roof,"LongRoofCoveBeam",V(2.2,1.6,218),CF(x,212.2,95),C.pale,Enum.Material.Plaster,false)
	end
	for _,z in ipairs({53,107,161}) do
		part(roof,"CrossRoofCoveBeam",V(336,1.3,2),CF(0,212.35,z),C.pale,Enum.Material.Plaster,false)
	end
	-- The structural gate-1 shell is centred at Z=196 and faces the courtyard
	-- at Z=192. Dress that actual visible face, not a wall behind the shell.
	local farFacade=model("S01_DistantApartmentFront",A)
	for _,x in ipairs({-147,-105,-63,-21,21,63,105,147}) do
		part(farFacade,"DistantVerticalPier",V(1.8,198,.45),CF(x,114,191.55),C.pale,Enum.Material.Plaster,false)
	end
	for row=1,13 do
		local y=14+row*14
		part(farFacade,"DistantFloorBand",V(314,.65,1.5),CF(0,y-5,191.2),C.pale,Enum.Material.Plaster,false)
		for col,x in ipairs({-126,-84,-42,0,42,84,126}) do
			local lit=(row*3+col)%5==0
			-- The gate shell is the real end of the court. Give that surface
			-- recessed rooms and projecting balcony edges, rather than relying
			-- on a translucent wall-sized veil to suggest distant apartments.
			part(farFacade,"DistantApartmentRecess",V(32,9.7,.14),CF(x,y+.15,191.82),
				Color3.fromRGB(98,101,91),Enum.Material.SmoothPlastic,false)
			part(farFacade,"DistantApartmentWindow",V(8,7,.3),CF(x,y,191.53),
				lit and Color3.fromRGB(178,155,111) or Color3.fromRGB(72,78,75),Enum.Material.SmoothPlastic,false)
			part(farFacade,"DistantWindowHead",V(8.8,.3,.52),CF(x,y+3.65,191.31),C.white,nil,false)
			part(farFacade,"DistantWindowSill",V(8.8,.3,.52),CF(x,y-3.65,191.31),C.white,nil,false)
			part(farFacade,"DistantWindowMullion",V(.2,7,.55),CF(x,y,191.24),C.white,nil,false)
			if row>=3 and row%2==col%2 then
				part(farFacade,"DistantBalconyDeck",V(32,.43,6.9),CF(x,y-4.9,188.4),C.pale,Enum.Material.Plaster,false)
				part(farFacade,"DistantBalconyFront",V(31,.23,.23),CF(x,y-1.65,184.9),C.white,nil,false)
				for post=-1,1 do
					part(farFacade,"DistantBalconyPost",V(.18,3.1,.18),CF(x+post*14.7,y-3.3,184.9),C.white,nil,false)
				end
			end
		end
	end
	-- In front of the end cap, two offset facades and their exposed flights
	-- give the view the same receding residential canyon as the side balconies.
	-- They are high, scenic layers: the gate corridor stays unobstructed below.
	local rearCanyon=model("S01_RecedingResidentialLayers",A)
	for _,info in ipairs({{-88,151,52},{68,166,50}}) do
		local cx,z,width=info[1],info[2],info[3]
		local tint=cx<0 and Color3.fromRGB(188,187,173) or Color3.fromRGB(200,195,180)
		local height=cx<0 and 145 or 168
		part(rearCanyon,"RecessedTowerFacade",V(width,height,.7),CF(cx,128,z),tint,Enum.Material.Plaster,false)
		for level=0,10 do
			local y=56+level*13.5
			part(rearCanyon,"MouldedFloorCourse",V(width+.5,.35,7.5),CF(cx,y-5,z-3.65),C.pale,Enum.Material.Plaster,false)
			for _,dx in ipairs({-width*.28,0,width*.28}) do
				local wx=cx+dx
				part(rearCanyon,"DeepApartmentRecess",V(9.4,9,.12),CF(wx,y,z-.39),
					Color3.fromRGB(93,96,87),Enum.Material.SmoothPlastic,false)
				part(rearCanyon,"DeepApartmentWindow",V(6.8,7.4,.18),CF(wx,y,z-.52),
					level%4==2 and Color3.fromRGB(155,136,101) or Color3.fromRGB(61,70,67),Enum.Material.Glass,false)
				part(rearCanyon,"WhiteSashHead",V(7.2,.22,.26),CF(wx,y+3.8,z-.67),C.white,nil,false)
				part(rearCanyon,"WhiteSashSill",V(7.2,.22,.26),CF(wx,y-3.8,z-.67),C.white,nil,false)
				part(rearCanyon,"WhiteSashMullion",V(.18,7.4,.26),CF(wx,y,z-.68),C.white,nil,false)
			end
			if level%2==0 then
				part(rearCanyon,"SetbackBalconyDeck",V(width*.78,.4,7.2),CF(cx,y-5.1,z-3.9),C.pale,Enum.Material.Plaster,false)
				part(rearCanyon,"SetbackBalconyRail",V(width*.78,.18,.18),CF(cx,y-1.95,z-7.55),C.white,nil,false)
				for _,dx in ipairs({-width*.38,0,width*.38}) do
					part(rearCanyon,"SetbackRailPost",V(.17,3,.17),CF(cx+dx,y-3.5,z-7.55),C.white,nil,false)
				end
			end
		end
	end
	for level=0,6 do
		local y=52+level*16
		local sign=level%2==0 and 1 or -1
		part(rearCanyon,"ExposedZigzagLanding",V(13,.55,4),CF(0,y,160),C.pale,Enum.Material.Concrete,false)
		local flight=CF(sign*7,y+7,160)*CFrame.Angles(0,0,-sign*math.rad(43))
		part(rearCanyon,"ExposedZigzagFlight",V(19,.48,3),flight,C.pale,Enum.Material.Concrete,false)
		for _,edge in ipairs({-1,1}) do
			part(rearCanyon,"ExposedZigzagRail",V(19,.16,.16),flight*CF(0,2.5,edge*1.5),C.white,nil,false)
		end
	end
	-- Staggered, nonblocking high floors break up the flat gate-wall silhouette.
	-- Their ground clearance preserves the gate and the existing clue cottages.
	local farStacks=model("S01_StaggeredFarApartmentStacks",A)
	for _,spec in ipairs({{-43,173,39},{27,183,55}}) do
		local cx,z,width=spec[1],spec[2],spec[3]
		local height=cx<0 and 126 or 158
		local face=part(farStacks,"SetbackCreamFacade",V(width,height,2.8),CF(cx,132,z),Color3.fromRGB(188,188,174),Enum.Material.Plaster,false)
		face.MaterialVariant=""
		for _,side in ipairs({-1,1}) do
			local returnWall=part(farStacks,"DeepSideReturn",V(2.1,height,13.5),CF(cx+side*(width/2-1),132,z-6.75),Color3.fromRGB(164,165,155),Enum.Material.Plaster,false)
			returnWall.MaterialVariant=""
		end
		for level=0,8 do
			local y=66+level*15
			part(farStacks,"WhiteFloorCourse",V(width+.8,.32,8.8),CF(cx,y-5,z-4.4),C.pale,nil,false)
			for _,flank in ipairs({-1,1}) do
				part(farStacks,"DeepWindowRecess",V(12.5,9.7,.13),CF(cx+flank*width*.23,y,z-1.42),
					Color3.fromRGB(91,95,87),Enum.Material.SmoothPlastic,false)
				part(farStacks,"DeepWindowPair",V(7.4,8,.2),CF(cx+flank*width*.23,y,z-1.55),
					(level+flank)%5==0 and Color3.fromRGB(173,154,119) or Color3.fromRGB(63,72,70),Enum.Material.Glass,false)
			end
			if level%2==0 then
				part(farStacks,"NarrowBalconyDeck",V(width*.75,.4,8.3),CF(cx,y-5.1,z-4.65),C.pale,Enum.Material.Plaster,false)
				part(farStacks,"NarrowBalconyRail",V(width*.75,.23,.2),CF(cx,y-1.8,z-8.9),C.white,nil,false)
				for _,dx in ipairs({-width*.37,0,width*.37}) do
					part(farStacks,"NarrowBalconyPost",V(.17,3.1,.17),CF(cx+dx,y-3.5,z-8.9),C.white,nil,false)
				end
			end
		end
	end
	-- The former 310-by-190 stud scrim covered the shell in the gaps between
	-- towers. Removing it keeps the separate setback faces legible at a distance.

	-- B is a long interior townhouse hall. All ground rooms survive behind its
	-- two frontages; only their closed upper scenery and porch canopy repetition
	-- give way to the low fluorescent corridor seen from the gate-1 approach.
	local B=model("B_LowEavesArcade")
	local arcadeBase=floor(B,"OchreArcadeCarpet",0,0,326,280,260,Color3.fromRGB(205,201,190))
	arcadeBase.Color=Color3.fromRGB(205,201,190)
	arcadeBase.MaterialVariant=""
	local corridor=model("S02_TownhouseCorridor",B)
	corridor:SetAttribute("ReferenceViewId",2)
	corridor:SetAttribute("GeometryIsEstimate",true)
	local corridorCarpet=model("SquareCarpetTiles",corridor)
	for row=0,41 do
		for col=0,1 do
			local alt=(row+col)%2==1
			local tile=part(corridorCarpet,alt and "CrossGrainTile" or "LengthGrainTile",V(5.95,.06,5.95),
				CF(86+col*6,.035,203+row*6)*CFrame.Angles(0,alt and math.pi/2 or 0,0),
				alt and Color3.fromRGB(209,205,192) or Color3.fromRGB(221,216,202),Enum.Material.Fabric,false)
			tile.MaterialVariant=""
			tile.Color=alt and Color3.fromRGB(209,205,192) or Color3.fromRGB(221,216,202)
			local weave=texture(tile,"rbxassetid://136282007145831",Enum.NormalId.Top,6)
			if weave then weave.Color3=Color3.fromRGB(247,245,236);weave.Transparency=.55 end
		end
	end
	local corridorCeiling=model("FluorescentTileCeiling",corridor)
	local suspendedPlane=part(corridorCeiling,"LowSuspendedPlane",V(17,.5,238),CF(89,14.55,335),Color3.fromRGB(210,207,197),Enum.Material.Plaster)
	suspendedPlane.MaterialVariant=""
	for _,x in ipairs({85,93}) do part(corridorCeiling,"CeilingTBarLong",V(.15,.09,236),CF(x,14.26,334),C.white,nil,false) end
	for z=216,452,8 do part(corridorCeiling,"CeilingTBarCross",V(14,.09,.15),CF(89,14.26,z),C.white,nil,false) end
	for i=0,12 do
		local z=232+i*17
		local failed=i==3 or i==9
		local panel=part(corridorCeiling,"FluorescentPanel",V(3.2,.1,3.5),CF(89,14.2,z),
			failed and Color3.fromRGB(94,92,86) or Color3.fromRGB(226,231,225),
			failed and Enum.Material.SmoothPlastic or Enum.Material.Neon,false)
		part(corridorCeiling,"LightPanelFrame",V(3.55,.1,3.85),CF(89,14.27,z),C.white,nil,false)
		if not failed then
			local light=Instance.new("SurfaceLight");light.Face=Enum.NormalId.Bottom;light.Range=26
			light.Brightness=1.15;light.Angle=150;light.Shadows=false
			light.Color=Color3.fromRGB(246,244,234);light.Parent=panel
		end
	end
	for _,z in ipairs({286,376}) do
		part(corridorCeiling,"UnevenDarkCeilingBay",V(4,.08,4),CF(84,14.21,z),Color3.fromRGB(116,112,105),nil,false)
	end
	local rightWall=model("CreamRightWallAndRecesses",corridor)
	local function rightPier(z0,z1)
		if z1<=z0 then return end
		local pier=part(rightWall,"CreamWallPier",V(.6,14.3,z1-z0),CF(82.7,7.15,(z0+z1)/2),Color3.fromRGB(222,217,204),Enum.Material.Plaster)
		pier.MaterialVariant=""
		part(rightWall,"WhiteBaseboard",V(.25,.6,z1-z0),CF(83.12,.3,(z0+z1)/2),C.white,nil,false)
		-- The photographed right side is a quiet cream corridor between real
		-- repeated door recesses. Keep the pier unbroken instead of hanging
		-- near-black framed panels on its visible face.
	end
	local rightCursor=216
	for _,z in ipairs({254,292,330,368,406}) do
		local first,last=z-2.5,z+2.5
		rightPier(rightCursor,first)
		local lintel=part(rightWall,"RecessLintel",V(.6,6.3,5),CF(82.7,11.15,z),Color3.fromRGB(222,217,204),Enum.Material.Plaster)
		lintel.MaterialVariant=""
		for _,side in ipairs({-1,1}) do
			part(rightWall,"WhiteOpeningReturn",V(5.3,8,.25),CF(80.05,4,z+side*2.5),C.white,Enum.Material.Plaster)
		end
		part(rightWall,"DarkRoomBacking",V(.4,9,5.2),CF(77.2,4.5,z),Color3.fromRGB(151,146,134),Enum.Material.Plaster)
		part(rightWall,"WhiteOpeningHead",V(.3,.28,5.5),CF(83.13,8,z),C.white,nil,false)
		rightCursor=last
	end
	rightPier(rightCursor,448)
	local leftDetails=model("LeftTownhouseFrontage",corridor)
	for _,s in ipairs({-1,1}) do
		for i,z in ipairs({232,286,348,418}) do
			local frame=CF(s*96,0,z)*yaw(s*90)
			local home=house(B,"ArcadeResidence_"..s.."_"..i.."_0",frame,28,28,13.8,i%2==0 and C.pale or C.yellow,nil,
				{open=true,backOpening=i%2==0,furniture=i==2 and (s<0 and 1 or 3) or nil,frontDoorNear=s>0 and i==1})
			-- The first +X home has the real entry on the reference corridor.
			-- Keep the gate-2 clue there rather than selecting an unrelated
			-- detached room by the global median-candidate rule.
			if not (s>0 and i==1) then home:SetAttribute("HousePuzzleCandidate",false) end
			if i==1 then registerWatcher(home,"ArcadeWindow_"..s,B.Name) end
			if s>0 then
				local tint=({Color3.fromRGB(190,179,161),Color3.fromRGB(108,125,139),Color3.fromRGB(163,153,143),Color3.fromRGB(191,183,166)})[i]
				referenceClapboard(home,tint,Color3.fromRGB(54,59,56))
				if i==1 then
					-- The first hall home is pale lavender-taupe in reference view 2.
					for _,piece in ipairs(home:GetDescendants()) do
						if piece:IsA("BasePart") and piece.MaterialVariant=="Level5CourtyardClapboard" then
							piece.MaterialVariant="Level5PaintedSiding"
							piece.Color=Color3.fromRGB(218,207,208)
						end
					end
				end
				local canopyCenter=i==1 and 9 or 0
				for _,side in ipairs({-1,1}) do
					part(leftDetails,"DarkGabledDoorCanopy",V(4.1,.36,3.5),frame*CF(canopyCenter+side*1.7,11.2,-2)*CFrame.Angles(0,0,-side*math.rad(24)),Color3.fromRGB(51,53,54),Enum.Material.Slate,false)
				end
				local lamp=part(leftDetails,"WarmWallSconce",V(.45,.7,.35),frame*CF(3.35,7.2,-.58),Color3.fromRGB(255,209,148),Enum.Material.Neon,false)
				local light=Instance.new("PointLight");light.Range=9;light.Brightness=.52;light.Shadows=false
				light.Color=Color3.fromRGB(255,213,155);light.Parent=lamp
			end
		end
	end
	local function infillTownhouse(z0,z1,tint)
		local bay=(z0+z1)/2
		local windowZ=bay-(z1-z0)*.23
		local doorZ=bay+(z1-z0)*.23
		local w0,w1=windowZ-2.2,windowZ+2.2
		local d0,d1=doorZ-1.8,doorZ+1.8
		local function wallSpan(a,b,low,high)
			if b>a then part(leftDetails,"ClapboardWallSpan",V(.6,high-low,b-a),CF(96,(low+high)/2,(a+b)/2),tint,Enum.Material.WoodPlanks) end
		end
		wallSpan(z0,w0,0,14.3);wallSpan(w0,w1,0,3.1);wallSpan(w0,w1,8.7,14.3)
		wallSpan(w1,d0,0,14.3);wallSpan(d0,d1,8.7,14.3);wallSpan(d1,z1,0,14.3)
		part(leftDetails,"RecessedMultiPaneWindow",V(.16,5.6,4.4),CF(96.05,5.9,windowZ),C.glass,Enum.Material.Glass)
		part(leftDetails,"WindowVerticalMullion",V(.2,5.6,.13),CF(95.73,5.9,windowZ),C.white,nil,false)
		for _,y in ipairs({4.5,7.3}) do part(leftDetails,"WindowHorizontalMullion",V(.2,.15,4.4),CF(95.73,y,windowZ),C.white,nil,false) end
		for _,z in ipairs({w0,w1}) do part(leftDetails,"WhiteWindowJamb",V(.33,6,.24),CF(95.66,5.9,z),C.white,nil,false) end
		part(leftDetails,"WhiteWindowHead",V(.34,.27,5),CF(95.65,8.8,windowZ),C.white,nil,false)
		part(leftDetails,"WhiteWindowSill",V(.34,.3,5),CF(95.65,3,windowZ),C.white,nil,false)
		part(leftDetails,"RecessedPanelDoor",V(.22,8.5,3.6),CF(96.32,4.25,doorZ),Color3.fromRGB(57,61,61),Enum.Material.Wood)
		for _,z in ipairs({d0,d1}) do part(leftDetails,"WhiteDoorJamb",V(.4,8.8,.24),CF(95.66,4.4,z),C.white,nil,false) end
		part(leftDetails,"WhiteDoorHead",V(.4,.35,4.2),CF(95.66,8.72,doorZ),C.white,nil,false)
	end
	infillTownhouse(246,272,Color3.fromRGB(216,208,207))
	infillTownhouse(300,334,Color3.fromRGB(144,155,164))
	infillTownhouse(362,404,Color3.fromRGB(183,170,159))
	part(leftDetails,"EndTownhouseWall",V(.6,14.3,20),CF(96,7.15,442),Color3.fromRGB(191,183,166),Enum.Material.WoodPlanks)
	local function exitSign(z)
		local sign=part(corridor,"RedExitHousing",V(3,.95,.35),CF(89,12.9,z),C.white,nil,false)
		local gui=Instance.new("SurfaceGui");gui.Name="ExitSignGui";gui.Face=Enum.NormalId.Front
		gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;gui.PixelsPerStud=48;gui.LightInfluence=0
		local label=Instance.new("TextLabel");label.Name="ExitText";label.Size=UDim2.fromScale(1,1)
		label.BackgroundTransparency=1;label.Text="EXIT";label.TextColor3=Color3.fromRGB(218,42,36)
		label.TextScaled=true;label.Font=Enum.Font.GothamBold;label.Parent=gui;gui.Parent=sign
	end
	exitSign(344);exitSign(438)
	-- Gate 1 opens at X=0 while the photographed long hall begins at X=89.
	-- Retire the six disconnected legacy houses and join the two positions with
	-- a low, enclosed carpeted turn. Its 16-stud clear width reaches the actual
	-- corridor without changing either gate, its doorway or the Watcher rooms.
	local entryTurn=model("S02_EnclosedEntryTurn",B)
	entryTurn:SetAttribute("ReferenceViewId",2)
	for col=0,14 do
		local x=-7+col*6
		for row,z in ipairs({204,210}) do
			local alternate=(col+row)%2==0
			local tile=part(entryTurn,alternate and "CrossGrainTile" or "LengthGrainTile",V(5.95,.06,5.95),
				CF(x,.035,z)*CFrame.Angles(0,alternate and math.pi/2 or 0,0),
				alternate and Color3.fromRGB(209,205,192) or Color3.fromRGB(221,216,202),Enum.Material.Fabric,false)
			tile.MaterialVariant=""
			tile.Color=alternate and Color3.fromRGB(209,205,192) or Color3.fromRGB(221,216,202)
			local weave=texture(tile,"rbxassetid://136282007145831",Enum.NormalId.Top,6)
			if weave then weave.Color3=Color3.fromRGB(247,245,236);weave.Transparency=.55 end
		end
	end
	local entryCeiling=part(entryTurn,"SuspendedEntryCeiling",V(93.5,.5,19),CF(33.75,14.55,206.5),Color3.fromRGB(210,207,197),Enum.Material.Plaster)
	entryCeiling.MaterialVariant=""
	local cornerCeiling=part(entryTurn,"SuspendedTurnCeiling",V(17,.5,19),CF(89,14.55,206.5),Color3.fromRGB(210,207,197),Enum.Material.Plaster)
	cornerCeiling.MaterialVariant=""
	for _,z in ipairs({202,210}) do
		part(entryTurn,"EntryCeilingTBar",V(93,.09,.15),CF(33.75,14.26,z),C.white,nil,false)
	end
	for x=-4,76,16 do
		local lit=x~=44
		local panel=part(entryTurn,"EntryFluorescentPanel",V(3.5,.1,3.2),CF(x,14.2,207),
			lit and Color3.fromRGB(226,231,225) or Color3.fromRGB(94,92,86),
			lit and Enum.Material.Neon or Enum.Material.SmoothPlastic,false)
		if lit then
			local light=Instance.new("SurfaceLight");light.Face=Enum.NormalId.Bottom
			light.Range=24;light.Brightness=.9;light.Angle=150;light.Shadows=false
			light.Color=Color3.fromRGB(246,244,234);light.Parent=panel
		end
	end
	local cornerPanel=part(entryTurn,"TurnFluorescentPanel",V(3.2,.1,3.5),CF(89,14.2,207),Color3.fromRGB(226,231,225),Enum.Material.Neon,false)
	local cornerLight=Instance.new("SurfaceLight");cornerLight.Face=Enum.NormalId.Bottom
	cornerLight.Range=24;cornerLight.Brightness=.9;cornerLight.Angle=150;cornerLight.Shadows=false
	cornerLight.Color=Color3.fromRGB(246,244,234);cornerLight.Parent=cornerPanel
	for _,span in ipairs({{12,97.5,199.7},{-13,82.4,216.3}}) do
		local x0,x1,z=span[1],span[2],span[3]
		local wall=part(entryTurn,"CreamTransitionWall",V(x1-x0,14.3,.6),CF((x0+x1)/2,7.15,z),Color3.fromRGB(222,217,204),Enum.Material.Plaster)
		wall.MaterialVariant=""
		part(entryTurn,"WhiteTransitionBaseboard",V(x1-x0,.58,.24),CF((x0+x1)/2,.3,z+(z>208 and -.43 or .43)),C.white,nil,false)
	end
	local westEnd=part(entryTurn,"WestTransitionReturn",V(.6,14.3,16.6),CF(-13.3,7.15,208),Color3.fromRGB(222,217,204),Enum.Material.Plaster)
	westEnd.MaterialVariant=""
	local eastEnd=part(entryTurn,"EastTransitionReturn",V(.6,14.3,18),CF(97.8,7.15,208.7),Color3.fromRGB(222,217,204),Enum.Material.Plaster)
	eastEnd.MaterialVariant=""

	local N=require(script.Parent:WaitForChild("Level 5 Neighbourhood Districts")).Build(K)
	local L=require(script.Parent:WaitForChild("Level 5 Landmark Districts")).Build(K)
	local zones={
		{Name="A_BalconyAtrium",Title="Planted Indoor Courtyard",Width=320,Z0=-4,Z1=196,CeilingHeight=215,Style="courtyard"},
		{Name="B_LowEavesArcade",Title="Townhouse Corridor",Width=280,Z0=196,Z1=456,CeilingHeight=50,Style="low"},
		{Name="C_PastelVillage",Title="Pastel Carpet Villages",Width=560,Z0=456,Z1=936,CeilingHeight=100,Style="office"},
		{Name="D_FloralTerraces",Title="Sunken Floral Terraces",Width=320,Z0=936,Z1=1296,CeilingHeight=320,Style="office",Bottom=-14},
		{Name="E_DomesticLabyrinth",Title="Domestic Room Labyrinth",Width=320,Z0=1296,Z1=1596,CeilingHeight=44,Style="domestic"},
		{Name="F_BayWindowCanyon",Title="Deep Residential Atrium",Width=500,Z0=1596,Z1=2076,CeilingHeight=84,Style="office",Bottom=-42},
		{Name="G_TiltedSubdivision",Title="Impossible Tilted Subdivision",Width=480,Z0=2076,Z1=2456,CeilingHeight=180,Style="warehouse"},
		{Name="H_LastHouse",Title="Last House",Width=220,Z0=2456,Z1=2636,CeilingHeight=70,Style="domestic"},
	}
	local gateLocal={V(0,0,196),V(88,0,456),V(-120,0,936),V(120,0,1296),V(-120,0,1596),V(178,0,2076),V(-65,0,2456)}
	local sectionGates={}
	for i,p in ipairs(gateLocal) do sectionGates[i]={Frame=offset*CF(p),Approach=origin+p+V(0,3,-12),Departure=origin+p+V(0,3,12),WallThickness=8} end
	local totalFootprint=0
	for index,z in ipairs(zones) do
		local m=root:FindFirstChild(z.Name);assert(m,"Missing district "..z.Name)
		z.Model=m;z.Min=V(-z.Width/2,z.Bottom or 0,z.Z0);z.Max=V(z.Width/2,z.CeilingHeight,z.Z1)
		-- Retain lower-case metadata for older diagnostics; runtime contracts use
		-- Name/Model/Min/Max/CeilingHeight and never derive geometry by scaling.
		z.model=z.Name;z.name=z.Title;z.width=z.Width;z.z0=z.Z0;z.z1=z.Z1;z.height=z.CeilingHeight
		m:SetAttribute("BiomeName",z.Title);m:SetAttribute("CeilingY",z.CeilingHeight)
		m:SetAttribute("DistrictMin",z.Min);m:SetAttribute("DistrictMax",z.Max)
		m:SetAttribute("ZoneMin",z.Min);m:SetAttribute("ZoneMax",z.Max);m:SetAttribute("CeilingHeight",z.CeilingHeight)
		local enclosure=model("Enclosure",m)
		local bottom=z.Bottom or 0
		-- A physically opaque shell: the interior faces stay on the existing
		-- envelope, while thick outward walls overlap the roof and corner caps.
		local top=z.CeilingHeight+6;local deep=bottom-6
		for _,side in ipairs({-1,1}) do
			material(part(enclosure,"DistrictSideWall",V(6,top-deep,z.Z1-z.Z0+12),CF(side*(z.Width/2+2.4),(top+deep)/2,(z.Z0+z.Z1)/2),C.cream,Enum.Material.Plaster),"Plaster")
			part(enclosure,"ContinuousBaseboard",V(.45,.8,z.Z1-z.Z0),CF(side*(z.Width/2-.65),.4,(z.Z0+z.Z1)/2),C.white,nil,false)
			for _,edge in ipairs({z.Z0,z.Z1}) do material(part(enclosure,"OverlappingCornerColumn",V(4,top-deep,4),CF(side*(z.Width/2+1), (top+deep)/2,edge),C.cream,Enum.Material.Plaster),"Plaster") end
		end
		for _,isBack in ipairs({false,true}) do
			-- A shared boundary belongs to the preceding district. Its one opaque
			-- shell covers both envelopes; generating it again on the next district
			-- produces identical visible plaster faces at every gate.
			if index==1 or isBack then
			local edge=isBack and z.Z1 or z.Z0
			local entrance=index==1 and not isBack
			local chute=index==8 and isBack
			local neighbour=isBack and zones[index+1] or nil
			local wallWidth=math.max(z.Width,neighbour and neighbour.Width or z.Width)
			local wallTop=math.max(top,neighbour and neighbour.CeilingHeight+6 or top)
			local sharedBottom=math.min(bottom,neighbour and neighbour.Bottom or 0)
			local wallDeep=math.min(deep,sharedBottom-6)
			local opening=chute and 9.3 or 22;local openingHeight=chute and 11 or 14
			local wallBottom=chute and -35 or wallDeep
			local gate=not entrance and not chute and gateLocal[isBack and index or index-1] or nil
			local gx=gate and gate.X or 0
			if entrance then
				material(part(enclosure,"ArrivalBackWall",V(z.Width+12,top-deep,8),CF(0,(top+deep)/2,edge-3.3),C.cream,Enum.Material.Plaster),"Plaster")
			else
				for _,span in ipairs({{-wallWidth/2-6,gx-opening/2},{gx+opening/2,wallWidth/2+6}}) do
					material(part(enclosure,"ThresholdSideWall",V(span[2]-span[1],wallTop-wallBottom,8),CF((span[1]+span[2])/2,(wallTop+wallBottom)/2,edge),C.cream,Enum.Material.Plaster),"Plaster")
				end
				material(part(enclosure,"ThresholdHighClosure",V(opening,wallTop-openingHeight,8),CF(gx,(wallTop+openingHeight)/2,edge),C.cream,Enum.Material.Plaster),"Plaster")
				if sharedBottom<0 and not chute then material(part(enclosure,"ThresholdFoundation",V(opening,-wallDeep,8),CF(gx,wallDeep/2,edge),C.cream,Enum.Material.Plaster),"Plaster") end
			end
			end
		end
		ceiling(enclosure,z.Title.."Ceiling",0,(z.Z0+z.Z1)/2,z.Width,z.Z1-z.Z0,z.CeilingHeight,z.Style)
		-- A limited shared suspended-light grid keeps human-height paths legible
		-- beneath tall rooms. These are room fixtures, never house-mounted lights.
		if z.CeilingHeight>60 then
			for i,zz in ipairs({z.Z0+35,(z.Z0+z.Z1)/2,z.Z1-35}) do
				for _,xx in ipairs({-34,34}) do
					local y=index==1 and 212 or (index==6 and 82 or (index==8 and 24 or 37))
					local p=part(enclosure,"SuspendedSharedFluorescent",V(7,.18,3),CF(xx,y,zz),i==2 and C.ceiling or Color3.fromRGB(221,218,187),i==2 and Enum.Material.SmoothPlastic or Enum.Material.Neon,false)
					p:SetAttribute("TubeState",i==2 and "Off" or "On")
					for _,dx in ipairs({-2.6,2.6}) do part(enclosure,"CeilingSuspension",V(.055,z.CeilingHeight-y,.055),CF(xx+dx,(z.CeilingHeight+y)/2,zz),C.grid,nil,false) end
						if i~=2 then local l=Instance.new("SurfaceLight");l.Face=Enum.NormalId.Bottom;l.Range=index==6 and 60 or 52;l.Angle=160;l.Brightness=.85;l.Shadows=false;l.Color=Color3.fromRGB(244,233,204);l.Parent=p end
				end
			end
		end
		totalFootprint+=z.Width*(z.Z1-z.Z0)
	end

	-- The final court has an irregular congregation of eyes, not another
	-- fluorescent grid. The client may turn each four-part rig toward nearby
	-- researchers; geometry, safe rotation bounds and the home pose live here.
	local exitEyes=model("ExitCeilingEyes",assert(root:FindFirstChild("H_LastHouse")))
	exitEyes:SetAttribute("CeilingEyesVersion","2026-09-26.3")
	exitEyes:SetAttribute("PairCount",48)
	exitEyes:SetAttribute("GeometryPartCount",192)
	exitEyes:SetAttribute("EllipsoidMeshCount",192)
	exitEyes:SetAttribute("TrackingBoundsMin",origin+V(-110,-36,2432))
	exitEyes:SetAttribute("TrackingBoundsMax",origin+V(110,90,2680))
	exitEyes:SetAttribute("NoDynamicLights",true)
	local eyePositions={}
	local function radicalInverse(index,base)
		local result,fraction=0,1/base
		while index>0 do result+=(index%base)*fraction;index=math.floor(index/base);fraction/=base end
		return result
	end
	local function ellipsoid(p)
		-- Native Ball parts render as a uniform sphere, collapsing thin lenses
		-- to their smallest axis. A Sphere SpecialMesh on a Block uses all three
		-- parent Size axes, retaining the authored elliptical eye silhouette.
		p.Shape=Enum.PartType.Block
		local mesh=Instance.new("SpecialMesh")
		mesh.Name="EyeEllipsoid";mesh.MeshType=Enum.MeshType.Sphere;mesh.Scale=V(1,1,1)
		mesh.Parent=p
	end
	-- Low-discrepancy candidates plus a clearance test give a stable scattered
	-- layout without random seeds or rows of identically spaced fixtures.
	for candidate=1,512 do
		local p=V(-96+192*radicalInverse(candidate+17,2),0,2469+154*radicalInverse(candidate+31,3))
		local clear=true
		for _,other in ipairs(eyePositions) do if (p-other).Magnitude<14 then clear=false;break end end
		if clear then table.insert(eyePositions,p) end
		if #eyePositions==48 then break end
	end
	assert(#eyePositions==48,"Final court requires 48 separated ceiling eye pairs")
	for index,p in ipairs(eyePositions) do
		local scale=.82+.44*((index*13)%47)/46
		local rotationRadius=4.5*scale
		local drop=math.max(rotationRadius+.8,1+13*((index*11)%47)/46)
		-- The tallest nested hall roof reaches approximately56.2. These few
		-- mounts stay above it even through the entire permitted pivot rotation.
		if math.abs(p.X)<29 and p.Z>2490 and p.Z<2537 then drop=math.min(drop,7) end
		local position=V(p.X,70-drop,p.Z)
		local target=V(p.X*.35+((index*7)%13-6),4,2545+((index*17)%71-35))
		local home= CFrame.lookAt(position,target,V(0,0,-1))*CFrame.Angles(0,0,math.rad((index*19)%47-23))
		local worldHome=offset*home
		local rig=model(string.format("EyePair_%02d",index),exitEyes)
		rig.ModelStreamingMode=Enum.ModelStreamingMode.Atomic
		rig:SetAttribute("Level5CeilingEye",true)
		rig:SetAttribute("EyeIndex",index)
		rig:SetAttribute("ExpectedPartCount",4)
		rig:SetAttribute("ExpectedMeshCount",4)
		rig:SetAttribute("HomeCFrame",worldHome)
		rig:SetAttribute("CeilingMountPosition",origin+V(p.X,69.7,p.Z))
		rig:SetAttribute("RotationRadius",rotationRadius)
		rig:SetAttribute("CeilingClearance",drop-rotationRadius-.3)
		rig:SetAttribute("EyeScale",scale)
		local spacing=(1.95+.2*(index%3)/2)*scale
		local slant=math.rad(7+(index*3)%10)
		local firstLens
		for _,side in ipairs({-1,1}) do
			local suffix=side<0 and "Left" or "Right"
			local eye=home*CF(side*spacing,side*.055*scale,0)*CFrame.Angles(0,0,-side*slant)
			local lens=part(rig,"LuminousLens"..suffix,V(2.85,1.03,.48)*scale,eye*CF(0,-.04*scale,-.37*scale),Color3.fromRGB(246,241,222),Enum.Material.Neon,false)
			ellipsoid(lens)
			local pupil=part(rig,"Pupil"..suffix,V(.43,.74,.13)*scale,eye*CF(0,-.04*scale,-.655*scale),Color3.fromRGB(3,5,5),Enum.Material.SmoothPlastic,false)
			ellipsoid(pupil)
			firstLens=firstLens or lens
		end
		-- A replicated PrimaryPart pivot avoids an extra invisible fifth part.
		firstLens.PivotOffset=firstLens.CFrame:ToObjectSpace(worldHome)
		rig.PrimaryPart=firstLens
		for _,p in ipairs(rig:GetChildren()) do
			if p:IsA("BasePart") then
				p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
				p:SetAttribute("Level5CeilingEyePart",true)
				p:SetAttribute("HomeLocalCFrame",worldHome:ToObjectSpace(p.CFrame))
			end
		end
		game:GetService("CollectionService"):AddTag(rig,"Level5CeilingEye")
	end

	local growth=model("MyceliumWallGrowth")
	local moldAssets={"rbxassetid://111130507669211","rbxassetid://84997095468417","rbxassetid://119550867817499"}
	for i,z in ipairs(zones) do
		local side=i%2==0 and 1 or -1
		local pos=V(side*(z.Width/2-.68),i==4 and 16 or 20,(z.Z0+z.Z1)/2)
		local surface=part(growth,"WallColony_"..i,V(38,32,.015),CFrame.lookAt(pos,pos+V(-side,0,0)),C.white,nil,false)
		surface.Transparency=1;surface.CastShadow=false;surface:SetAttribute("Level5WallMold",true);surface:SetAttribute("AlphaBackground",true)
		surface:SetAttribute("MoldVariant",({"rising","corner","seam"})[(i-1)%3+1]);surface:SetAttribute("GrowthOrigin","Outer structural wall")
		local decal=Instance.new("Decal");decal.Name="DarkMyceliumOnPlaster";decal.Texture=moldAssets[(i-1)%3+1];decal.Face=Enum.NormalId.Front;decal.Color3=Color3.fromRGB(168,164,150);decal.Transparency=.04;decal.Parent=surface
	end
	root:SetAttribute("TallWallDrawingCount",0);root:SetAttribute("WallMoldCount",8);root:SetAttribute("WallMoldVariantCount",3)
	local cameras={
		{name="ExpandedAtriumArrival",position=V(-10,6,6),lookAt=V(15,96,146)},
		{name="ExpandedAtriumBalconies",position=V(-91,33,165),lookAt=V(95,45,55)},
		{name="ExpandedArcade",position=V(89,5.5,218),lookAt=V(89,5.4,440),fov=70},
		{name="ExpandedArcadeFarGate",position=V(89,5.5,414),lookAt=V(88,5.5,456),fov=70},
	}
	local waypoints={V(0,3,5),V(0,3,45),V(35,3,50),V(35,3,104),V(0,3,108),V(0,3,184),V(0,3,208),V(0,3,263),V(58,3,264),V(58,3,329),V(-55,3,329),V(-55,3,397),V(60,3,400),V(60,3,444),V(88,3,444),V(88,3,468),V(110,3,468),V(110,3,513),V(145,3,513),V(145,3,565),V(90,3,592),V(25,3,592),V(25,3,650),V(-25,3,700),V(-25,3,740),V(-25,3,778),V(-90,3,778),V(-145,3,800),V(-145,3,865),V(-100,3,875),V(-100,3,924),V(-120,3,924),V(-120,3,948),V(-120,3,965),V(-101,3,965),V(-101,3,1087),V(-101,3,1109),V(-86,3,1109),V(-86,3,1094),V(-86,3,1089),V(-86,-3,1073),V(-86,-9,1057),V(-86,-9,1024),V(15,-9,1024),V(15,-9,1106),V(30,-9,1122),V(30,-9,1195),V(0,-9,1228),V(0,-3,1246),V(0,3,1265),V(120,3,1278),V(120,3,1284),V(120,3,1308),V(90,3,1310),V(90,3,1373),V(60,3,1373),V(60,3,1406),V(-90,3,1406),V(-90,3,1458),V(-60,3,1458),V(-60,3,1495),V(-90,3,1495),V(-90,3,1550),V(-120,3,1584),V(-120,3,1608),V(-125,3,1689),V(-80,3,1690),V(-80,3,1755),V(15,3,1755),V(75,3,1790),V(75,3,1840),V(75,3,1910),V(40,3,1955),V(0,3,1955),V(0,3,2028),V(80,3,2028),V(178,3,2048),V(178,3,2064),V(178,3,2088),V(135,3,2100),V(95,3,2140),V(0,3,2140),V(-54,3,2173),V(-54,7,2188),V(-54,11,2204),V(-90,11,2208),V(-90,11,2270),V(-60,11,2270),V(-10,11,2270),V(6,11,2270),V(18,15,2270),V(30,19,2270),V(36,19,2270),V(92,19,2270),V(92,19,2332),V(54,19,2332),V(54,19,2340),V(54,11,2360),V(54,3,2380),V(54,3,2383),V(0,3,2400),V(0,3,2444),V(-65,3,2444),V(-65,3,2468),V(-65,3,2538),V(-30,3,2548),V(0,3,2555),V(0,3,2578),V(0,3,2588),V(0,3,2597.5),V(9,3,2597.5),V(9,3,2610.9),V(0,3,2610.9),V(0,3,2613),V(0,3,2615),V(0,-2.5,2631),V(0,-8,2647),V(0,-17,2658.5),V(0,-26,2670),V(0,-26,2676)}
	-- The B guide route follows the actual hall. The former zigzag crossed
	-- through the sealed cross-lane scenery and did not reveal reference 02.
	local hallRoute={V(0,3,208),V(44,3,208),V(89,3,212),V(89,3,224),V(89,3,263),V(89,3,329),V(89,3,397),V(89,3,438),V(88,3,444)}
	local hallwayWaypoints={};local hallInserted=false
	for _,point in ipairs(waypoints) do
		if point.Z>=208 and point.Z<=444 then
			if not hallInserted then
				for _,hallPoint in ipairs(hallRoute) do table.insert(hallwayWaypoints,hallPoint) end
				hallInserted=true
			end
		else table.insert(hallwayWaypoints,point) end
	end
	assert(hallInserted,"Missing B corridor route span");waypoints=hallwayWaypoints
	-- E's reference room has a central door and a separate right-hand passage.
	-- The old route stayed on the outer carpet at X=90 and crossed the new
	-- apartment-shaft backing; guide the traversal through the actual portal.
	local domesticRoute={V(120,3,1308),V(0,3,1302),V(0,3,1347),
		V(-27,3,1354),V(-27,3,1366),V(0,3,1399),V(0,3,1440),
		V(0,3,1461),V(0,3,1489),V(-45,3,1518),V(-45,3,1560),
		V(-45,3,1590),V(-120,3,1590),V(-120,3,1608)}
	local domesticWaypoints={};local domesticInserted=false
	for _,point in ipairs(waypoints) do
		if point.Z>=1308 and point.Z<=1608 then
			if not domesticInserted then
				for _,homePoint in ipairs(domesticRoute) do table.insert(domesticWaypoints,homePoint) end
				domesticInserted=true
			end
		else table.insert(domesticWaypoints,point) end
	end
	assert(domesticInserted,"Missing E domestic route span");waypoints=domesticWaypoints
	-- Replace only the F traversal: the domestic atrium now crosses a deep
	-- void at several heights while retaining both authored gate thresholds.
	local atriumRoute=assert(L.FRouteWaypoints,"Missing residential atrium route")
	local revisedRoute={};local inserted=false
	for _,point in ipairs(waypoints) do
		if point.Z>1596 and point.Z<2076 then
			if not inserted then
				for _,p in ipairs(atriumRoute) do table.insert(revisedRoute,p) end
				inserted=true
			end
		else table.insert(revisedRoute,point) end
	end
	assert(inserted,"Missing F route replacement span");waypoints=revisedRoute
	-- Follow the clear side of the planted incline and turn before the rear
	-- cottages. Both detours retain continuous lawn support at ground level.
	local pierDetour,rearDetour=false,false
	for i=#waypoints,2,-1 do
		if waypoints[i-1]==V(0,3,2140) and waypoints[i]==V(-54,3,2173) then
			table.insert(waypoints,i,V(-54,3,2155));pierDetour=true
		elseif waypoints[i-1]==V(0,3,2400) and waypoints[i]==V(0,3,2444) then
			waypoints[i]=V(-65,3,2400);rearDetour=true
		end
	end
	assert(pierDetour and rearDetour,"Missing Level 5 lawn route detour")
	local function worldRoute(localPoints)
		local points={};for _,p in ipairs(localPoints or {}) do table.insert(points,origin+p) end;return points
	end
	for _,r in ipairs({N,L}) do for _,v in ipairs(r.PreviewCameras or {}) do table.insert(cameras,v) end end
	for _,v in ipairs(cameras) do v.position+=origin;v.lookAt+=origin end
	for i,v in ipairs(waypoints) do waypoints[i]=origin+v end
	resolveSharedSideWalls()
	resolveFloorSurfaces()
	for p in pairs(floorSurfaces) do
		if p.Parent and p.Name=="InteriorCarpet" and p.CFrame.UpVector.Y>.99999 then
			local top=p.Position.Y+p.Size.Y/2
			p.Parent:SetAttribute("ActualFloorTopY",top)
			p.Parent:SetAttribute("HouseWindowFloorY",top)
		end
	end
	for _,anchor in ipairs(anchors:GetChildren()) do
		local ref=anchor:FindFirstChild("SupportingHouse")
		local home=ref and ref.Value
		local frame=anchor:GetAttribute("FloorCFrame")
		local top=home and home:GetAttribute("ActualFloorTopY")
		if typeof(frame)=="CFrame" and typeof(top)=="number" then
			local lift=top-frame.Position.Y
			assert(lift>=-.002 and lift<=.482,"Watcher floor adjustment exceeds surface policy: "..anchor.Name)
			anchor:SetAttribute("SurfaceLift",math.clamp(lift,0,.48))
			anchor:SetAttribute("FloorCFrame",frame+V(0,math.max(0,lift),0))
		end
	end
	local actualParts,actualLights,windows=0,0,0
	for _,v in ipairs(root:GetDescendants()) do if v:IsA("BasePart") then actualParts+=1 end;if v:IsA("Light") then actualLights+=1 end;if v:GetAttribute("Level5TintedWindow")==true then windows+=1 end end
	root:SetAttribute("PartCount",actualParts);root:SetAttribute("LightCount",actualLights);root:SetAttribute("TintedWindowCount",windows)
	root:SetAttribute("BiomeCount",8);root:SetAttribute("GroundEnvelopeArea",totalFootprint);root:SetAttribute("PreviousGroundEnvelopeArea",331600)
	root:SetAttribute("GroundEnvelopeExpansionFactor",totalFootprint/331600)
	root:SetAttribute("WindowStandard","Glass RGB(87,102,102), transparency 0.2; no luminous panes")
	root:SetAttribute("Design","Unknown-origin Backrooms. The researchers did not create this place.")
	root:SetAttribute("SpawnCFrame",CFrame.lookAt(origin+V(0,3,5),origin+V(0,3,70)))
	return {Model=root,SpawnCFrame=CFrame.lookAt(origin+V(-18,3,5),origin+V(20,3,100)),PreviewCameras=cameras,Waypoints=waypoints,RouteWaypoints=waypoints,SectionGates=sectionGates,Zones=zones,
		FinalHouse=L.FinalHouse,ChuteStart=CF(origin+L.ChuteStart),ChuteEnd=CF(origin+L.ChuteEnd),
		FRouteWaypoints=worldRoute(L.FRouteWaypoints),FRescueRouteWaypoints=worldRoute(L.FRescueRouteWaypoints),FClueRouteWaypoints=worldRoute(L.FClueRouteWaypoints),FAtriumPitBounds=L.FAtriumPitBounds,
		Bounds={Min=origin+V(-287,-50,-12),Max=origin+V(287,330,2680)},GroundEnvelopeArea=totalFootprint,PreviousGroundEnvelopeArea=331600}
end
return Architecture
