-- Extra engine boundaries only for actual RoomDressing authoring/interaction.
local typeof=function(value) return type(value)=="table" and value.kind or type(value) end
local oldCFNew=CFrame.new
CFrame.new=function(x,y,z)
    if type(x)=="table" and x.kind=="Vector3" then return oldCFNew(x.X,x.Y,x.Z) end
    return oldCFNew(x,y,z)
end
cf.__index=function(c,key)
    if key=="RightVector" then return Vector3.new(math.cos(c.Yaw),0,-math.sin(c.Yaw)) end
    if key=="UpVector" then return Vector3.new(0,1,0) end
    if key=="LookVector" then return Vector3.new(-math.sin(c.Yaw),0,-math.cos(c.Yaw)) end
    return cf[key]
end
CFrame.lookAt=function(position,target)
    local c=CFrame.new(position); local direction=target-position
    c.Yaw=math.atan2(-direction.X,-direction.Z); return c
end
Enum.RollOffMode={InverseTapered="InverseTapered"}
function Methods:FindFirstChildOfClass(class)
    for _,c in ipairs(self._children) do if c:IsA(class) then return c end end
end
function Methods:Play() self.Playing=true end
function Methods:Stop() self.Playing=false end
local originalStable=stable
stable=function(value)
    if type(value)=="table" and value.Signal then return "Signal" end
    return originalStable(value)
end
local function dressingEngine()
    local e=engine()
    e.signals={}
    local function signal()
        local s={Signal=true,Connections={}}
        function s:Connect(fn)
            local connection={Connected=true,Fn=fn}
            function connection:Disconnect() self.Connected=false end
            s.Connections[#s.Connections+1]=connection; return connection
        end
        function s:Fire(...)
            for _,connection in ipairs(self.Connections) do if connection.Connected then connection.Fn(...) end end
        end
        e.signals[#e.signals+1]=s; return s
    end
    local originalNew=e.Instance.new
    e.Instance.new=function(class)
        local object=originalNew(class); object.AncestryChanged=signal()
        if class=="ProximityPrompt" then object.Triggered=signal() end
        return object
    end
    e.Players={PlayerRemoving=signal()}
    function e.Players:GetPlayers() return {} end
    local originalService=e.game.GetService
    e.game.GetService=function(self,name)
        if name=="Players" then e.reads[#e.reads+1]="service:Players"; return e.Players end
        return originalService(self,name)
    end
    e.workspace.Attributes={RoundActive=true,SelectedLevel=3}
    function e.workspace:GetAttribute(key) return self.Attributes[key] end
    e.os={clock=function() return e.clock end}
    return e
end

local function planFixture(load)
    local e=dressingEngine(); local api=load(e)
    check(#e.allocated==0,"Room Dressing module load allocates no instances")
    local rows={}
    for _,variant in ipairs({"BudgetArcade","PartySupplyStore","MaintenanceWorkshop","Unknown"}) do
        for _,width in ipairs({30,42,60,80}) do
            for _,seed in ipairs({0,1,2,3,4,-3,10.75}) do
                for _,blocked in ipairs({{},{{x=20,z=17,hx=15,hz=15}},{{x=0,z=0,hx=100,hz=100}}}) do
                    local result=api.Plan({W=width,D=64,ServiceVariant=variant},blocked,seed)
                    check(result~=nil and type(result.Reason)=="string","Plan always returns explicit decision")
                    if variant=="Unknown" then check(result.Variant==nil and result.Reason=="not-service-room","nonservice room bypass") end
                    rows[#rows+1]=stable(result)
                end
            end
        end
    end
    local good=api.Plan({W=80,D=64,ServiceVariant="BudgetArcade"},{},0)
    check(good.Pocket and good.Pocket.sx==1 and good.Pocket.sz==1,"authoring seed0 chooses positive corner")
    local rotated=api.Plan({W=80,D=64,ServiceVariant="BudgetArcade"},{},1)
    check(rotated.Pocket and rotated.Pocket.sx==-1 and rotated.Pocket.sz==-1,"seed1 changes corner deterministically")
    local blocked=api.Plan({W=80,D=64,ServiceVariant="BudgetArcade"},{{x=0,z=0,hx=100,hz=100}},0)
    check(not blocked.Pocket and blocked.Reason=="no-free-18x24-corner","existing obstacle envelopes win over art target")
    local narrow=api.Plan({W=30,D=30,ServiceVariant="BudgetArcade"},{},0)
    check(not narrow.Pocket,"cardinal portal crossing rejected")
    local ok,problem=pcall(api.Plan,{W="invalid",D=64,ServiceVariant="BudgetArcade"},{},0)
    check(not ok and string.find(problem,"Room W/D required",1,true),"invalid dimensions fail explicitly")
    return {Reads=e.reads,Rows=rows}
end

local function dressingFixture(load,blockedAll,failAssets,noParticipant)
    local e=dressingEngine(); e.clock=10
    local api=load(e)
    local stage=e.new("Folder","Unparented Fixture")
    local world=e.new("Model","Dressing World",stage); world:SetAttribute("Level3_Generation",7)
    local manifest={World=world,Generation=7,Rooms={},Layout={Rooms={},ResolvedSeed=123}}
    for i,variant in ipairs({"BudgetArcade","PartySupplyStore","MaintenanceWorkshop"}) do
        local id="Room"..i
        local room={Id=id,Kind="Service",W=80,D=64,H=12,X=i*200,Z=17,ServiceVariant=variant}
        manifest.Layout.Rooms[#manifest.Layout.Rooms+1]=room
        local model=e.new("Model",id,world); manifest.Rooms[id]=model
        if blockedAll then
            local obstacle=e.new("Part","Authoritative Permanent Furniture",model)
            obstacle.CFrame=CFrame.new(14+room.X,2,4); obstacle.Size=Vector3.new(500,8,500); obstacle.CanCollide=true
            obstacle:SetAttribute("Level3_PermanentFurniture",true)
        end
    end
    local placements,noise={},{ }
    local helper={WorldOrigin=Vector3.new(14,2,-13),SoundIds={BreakerInspect="rbxassetid://11",ClawMotor=12,ArcadeInvaders=13}}
    helper.Place=function(asset,frame,parent,options)
        placements[#placements+1]={Asset=asset,Frame=frame,Options=options}
        if failAssets then error("fixture unavailable asset",0) end
        local model=e.new("Model",asset,parent)
        local part=e.new("Part",asset.." Mesh",model)
        part.CFrame=frame; part.Size=Vector3.new(2,4,2); part.CanCollide=options.Collidable
        return model
    end
    local participant={UserId=71,Parent=e.Players}
    local character=e.new("Model","Participant")
    participant.Character=character
    local humanoid=e.new("Humanoid","Humanoid",character); humanoid.Health=100
    local root=e.new("Part","HumanoidRootPart",character); root.Position=Vector3.zero
    if not noParticipant then helper.IsParticipant=function(p) return p==participant end end
    helper.OnNoise=function(p,position,amount) noise[#noise+1]={UserId=p.UserId,Position=position,Amount=amount} end
    local result=api.Apply(manifest,helper,{Seed=123})
    check(result.Report.Rooms==3,"all service rooms authoring result counted")
    if failAssets then
        check(result.Report.PropsPlaced==0 and result.Report.Interactions==0,"failed asset placement makes no interactive ghosts")
        check(next(result.Report.MissingAssets)~=nil,"missing assets reported")
    elseif blockedAll then
        check(result.Report.FullServicePockets==0 and result.Report.FallbackServiceRooms==3,"protected-space authoring fallback")
        check(#result.Report.Skipped==10 and result.Report.Interactions==0,"blocked fallback keeps colliders/prompts absent")
    else
        check(result.Report.FullServicePockets==3 and result.Report.Interactions==5,"three variants preserve arcade/claw/breaker interactions")
        local breaker=result.Owner:FindFirstChild("Room3 | Blender Dressing"):FindFirstChild("BreakerPanel")
        local anchor=breaker:FindFirstChild("Interaction Origin")
        local authored=placements
        local breakerCF
        for _,placement in ipairs(authored) do if placement.Asset=="BreakerPanel" then breakerCF=placement.Frame end end
        check((anchor.Position-breakerCF:PointToWorldSpace(Vector3.new(.98,2.15,.42))).Magnitude<1e-9,"breaker latch prompt uses mounted +2.15 position")
        local prompt=anchor:FindFirstChild("Level3_ServiceInteraction")
        check(prompt.ObjectText=="OLD CIRCUIT PANEL" and prompt.ActionText=="Inspect" and prompt.HoldDuration==.65,"breaker prompt authoring contract")
        check(anchor.Transparency==1 and not anchor.CanCollide and not anchor.CanTouch and not anchor.CanQuery,"invisible carrier remains intact")
        check(prompt.Enabled==not noParticipant,"participant workflow fails closed")
        root.Position=anchor.Position
        prompt.Triggered:Fire(participant)
        if noParticipant then check(breaker:GetAttribute("Level3_InteractionSerial")==nil,"disabled workflow no interaction")
        else
            check(breaker:GetAttribute("Level3_InteractionSerial")==1 and #noise==1 and noise[1].Amount==.15,"validated breaker inspection remains active")
            prompt.Triggered:Fire(participant)
            check(breaker:GetAttribute("Level3_InteractionSerial")==1,"duplicate request stays busy")
            e.runTo(13.51)
            check(prompt.ActionText=="Inspect" and breaker:GetAttribute("Level3_ServiceActive")==false,"delayed lifecycle restores prompt")
            world:SetAttribute("Level3_Generation",8)
            prompt.Triggered:Fire(participant)
            check(breaker:GetAttribute("Level3_InteractionSerial")==1,"old generation cannot activate")
        end
    end
    local signature=e.signature(world)
    local report=stable(result.Report); local placementTrace=stable(placements); local noiseTrace=stable(noise)
    result.Cleanup(); result.Cleanup(); e.runTo(20)
    check(result.Owner.Parent==nil,"repeat cleanup removes owner and delayed work")
    for _,s in ipairs(e.signals) do
        for _,connection in ipairs(s.Connections) do check(not connection.Connected,"owner connections disconnected") end
    end
    stage:Destroy(); character:Destroy()
    for _,o in ipairs(e.allocated) do check(o.Parent==nil,"authoring fixture cleans all allocated objects") end
    return {Graph=signature,Report=report,Placements=placementTrace,Noise=noiseTrace}
end
