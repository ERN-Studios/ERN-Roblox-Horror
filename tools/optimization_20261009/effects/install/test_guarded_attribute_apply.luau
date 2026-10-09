-- Offline guard/rollback contracts; no Studio objects are touched.
local Apply=require("./guarded_attribute_apply")
local checks=0
local function check(condition,message) checks+=1;assert(condition,message)end
local function vector(x,y,z)return {X=x or 0,Y=y or 0,Z=z or 0}end
local function fixture(enabled,oldInfluence)
	local storage={Name="ServerStorage"};local world={Name="Workspace"}
	local root={Name="Level 4 Cinema Blender",Parent=storage};function root:GetDebugId()return "40071"end
	local mount={Parent=root,Position=vector(),Size=vector(1,1,1),Anchored=true};function mount:GetDebugId()return "mount"end
	local light={ClassName="PointLight",Parent=mount,Enabled=enabled,Range=20,attrs={SceneBudgetInfluenceRadius=oldInfluence}}
	function light:GetDebugId()return "effect"end
	function light:GetAttribute(name)return self.attrs[name]end
	function light:SetAttribute(name,value)self.attrs[name]=value end
	local director={Source="fresh",editor="fresh"};function director:IsA(class)return class=="ModuleScript"end;function director:GetDebugId()return "42773"end
	local services={Workspace=world,ServerStorage=storage,RunService={IsRunning=function()return false end},
		ServerScriptService={["Level 4 Systems"]={["Level 4 Light Director"]=director}},
		ScriptEditorService={GetEditorSource=function(_,d)return d.editor end}}
	local model={PlaceId=131311258779917,GameId=10559217407};function model:GetService(name)return services[name]end
	local counts={["Level 4 Cinema Blender"]=1}
	local selector={Collect=function()return {{Instance=light}},counts end}
	local row={id="effect",map=root.Name,rootId="40071",rootService="ServerStorage",holderId="mount",
		class="PointLight",enabled=enabled,hasWanted=false,hasInfluence=oldInfluence~=nil,
		influence=oldInfluence,newWanted=enabled,range=20,position={0,0,0},size={1,1,1},anchored=true}
	local plan={placeId=model.PlaceId,universeId=model.GameId,counts=counts,offset=1,total=1,records={row}}
	return model,plan,selector,light,director,mount
end

do
	local model,plan,selector,light=fixture(false)
	local result=Apply(model,plan,selector,"fresh","apply")
	check(result.Changed==1 and light:GetAttribute("SceneBudgetWantedEnabled")==false,"Authored false preserved in postcheck")
	Apply(model,plan,selector,"fresh","rollback")
	check(light:GetAttribute("SceneBudgetWantedEnabled")==nil and not light.Enabled,"Nil baseline restored")
end

do
	local model,plan,selector,light=fixture(true,7)
	Apply(model,plan,selector,"fresh","apply")
	check(light:GetAttribute("SceneBudgetInfluenceRadius")==7,"Unchanged existing influence preserved")
	Apply(model,plan,selector,"fresh","rollback")
	check(light:GetAttribute("SceneBudgetInfluenceRadius")==7,"Rollback preserves existing influence")
end

do
	local model,plan,selector,light,_,mount=fixture(true)
	mount.Position=vector(1)
	check(not pcall(Apply,model,plan,selector,"fresh","apply"),"Moved mount aborts before writes")
	check(light:GetAttribute("SceneBudgetWantedEnabled")==nil,"Preflight failure leaves original attributes")
end

do
	local model,plan,selector,light,director=fixture(true)
	director.editor="concurrent edit"
	check(not pcall(Apply,model,plan,selector,"fresh","apply"),"Editor conflict aborts")
	check(light:GetAttribute("SceneBudgetWantedEnabled")==nil,"Editor conflict does not become metadata write")
end

do
	local model,plan,selector,light=fixture(true)
	local failOnce=true
	function light:SetAttribute(name,value)
		if failOnce and name=="SceneBudgetWantedEnabled"then failOnce=false;self.attrs[name]=value;error("synthetic callback failure")end
		self.attrs[name]=value
	end
	check(not pcall(Apply,model,plan,selector,"fresh","apply"),"Attribute callback failure propagated")
	check(light:GetAttribute("SceneBudgetWantedEnabled")==nil,"Partial metadata write rolled back")
end

print("Guarded metadata offline contracts passed: "..checks)
