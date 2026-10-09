
assert(game.PlaceId == 131311258779917, "Wrong place")
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local function fingerprint(text)
    local h = 5381
    for i=1,#text do h=(h*33+string.byte(text,i))%4294967296 end
    return h
end
local function resolve(segments)
    local inst=game
    for _,name in ipairs(segments) do
        local matched
        for _,child in ipairs(inst:GetChildren()) do
            if child.Name==name then
                assert(not matched,"Ambiguous instance name: "..name)
                matched=child
            end
        end
        inst=assert(matched,"Missing instance: "..name)
    end
    return inst
end
local function encoded(value)
    local kind=typeof(value)
    if kind=="nil" or kind=="boolean" or kind=="number" or kind=="string" then return value end
    if kind=="Vector3" then return {value.X,value.Y,value.Z} end
    if kind=="Vector2" then return {value.X,value.Y} end
    if kind=="Color3" then return {value.R,value.G,value.B} end
    if kind=="CFrame" then return {value:GetComponents()} end
    if kind=="EnumItem" then return tostring(value) end
    if kind=="Instance" then return value:GetFullName() end
    return {type=kind,value=tostring(value)}
end
local function attrs(inst)
    local out={}
    for key,value in pairs(inst:GetAttributes()) do out[key]=encoded(value) end
    return out
end
local function properties(inst,names)
    local out,errors={},{}
    for _,name in ipairs(names) do
        local ok,value=pcall(function() return inst[name] end)
        if ok then out[name]=encoded(value) else errors[#errors+1]=name end
    end
    return out,errors
end
local function scriptRecord(segments,expectedClass)
    local inst=resolve(segments)
    assert(inst.ClassName==expectedClass,"Changed script class")
    local source=inst.Source
    local ok,editor=pcall(SES.GetEditorSource,SES,inst)
    local names={"Archivable","SourceAssetId","LinkedSource"}
    if inst:IsA("BaseScript") then names[#names+1]="Disabled";names[#names+1]="RunContext" end
    local props,unsupported=properties(inst,names)
    return {segments=segments,class=inst.ClassName,sourceBytes=#source,sourceHash=fingerprint(source),
        editorReadSucceeded=ok,editorMatches=ok and editor==source,
        editorBytes=ok and #editor or nil,editorHash=ok and fingerprint(editor) or nil,
        properties=props,unsupportedProperties=unsupported,attributes=attrs(inst)}
end
-- Sorted keys make repeated JSON construction deterministic across reads.
local function canonical(value)
    if type(value)~="table" then return HS:JSONEncode(value) end
    local n=#value
    if n>0 then
        local parts={}
        for i=1,n do parts[i]=canonical(value[i]) end
        return "["..table.concat(parts,",").."]"
    end
    local keys,parts={},{}
    for key in pairs(value) do keys[#keys+1]=key end
    table.sort(keys)
    for i,key in ipairs(keys) do parts[i]=HS:JSONEncode(key)..":"..canonical(value[key]) end
    return "{"..table.concat(parts,",").."}"
end
local function hexChunk(text,first,last)
    -- A byte transfer avoids JSON corruption when a boundary splits UTF-8.
    return (string.gsub(string.sub(text,first,last),".",function(char)
        return string.format("%02x",string.byte(char))
    end))
end

local function kitJSON()
    local kit=resolve({"ServerStorage","Level1BlenderKitV2"})
    assert(kit:IsA("Folder"),"Changed kit class")
    local records={}
    local counts={instances=0,meshParts=0,surfaceAppearances=0,colliders=0,rooms=0,components=0}
    local meshIds,pbrIds={},{}
    local function visit(inst,segments,indices)
        local names={"Archivable"}
        if inst:IsA("BasePart") then
            for _,name in ipairs({"Size","CFrame","Anchored","CanCollide","CanQuery","CanTouch",
                "CastShadow","Color","Material","MaterialVariant","Transparency","Reflectance",
                "CollisionGroup","LocalTransparencyModifier"}) do names[#names+1]=name end
        end
        if inst:IsA("Part") then names[#names+1]="Shape" end
        if inst:IsA("MeshPart") then
            for _,name in ipairs({"MeshId","TextureID","CollisionFidelity","RenderFidelity","DoubleSided"}) do names[#names+1]=name end
            counts.meshParts+=1
            meshIds[inst.MeshId]=true
        elseif inst:IsA("SurfaceAppearance") then
            for _,name in ipairs({"ColorMap","NormalMap","RoughnessMap","MetalnessMap","Color","AlphaMode"}) do names[#names+1]=name end
            counts.surfaceAppearances+=1
            for _,name in ipairs({"ColorMap","NormalMap","RoughnessMap","MetalnessMap"}) do
                if inst[name]~="" then pbrIds[inst[name]]=true end
            end
        elseif inst:IsA("Model") then
            for _,name in ipairs({"WorldPivot","PrimaryPart","ModelStreamingMode","LevelOfDetail"}) do names[#names+1]=name end
        end
        if inst:GetAttribute("RoomRole")=="Collider" then counts.colliders+=1 end
        if inst.Parent==kit:FindFirstChild("Rooms") then counts.rooms+=1 end
        if inst.Parent==kit:FindFirstChild("Components") then counts.components+=1 end
        local props,unsupported=properties(inst,names)
        records[#records+1]={path=inst:GetFullName(),segments=segments,childIndexPath=indices,
            class=inst.ClassName,properties=props,unsupportedProperties=unsupported,attributes=attrs(inst)}
        counts.instances+=1
        for index,child in ipairs(inst:GetChildren()) do
            local childSegments=table.clone(segments);childSegments[#childSegments+1]=child.Name
            local childIndices=table.clone(indices);childIndices[#childIndices+1]=index
            visit(child,childSegments,childIndices)
        end
    end
    visit(kit,{"ServerStorage","Level1BlenderKitV2"},{})
    local uniqueMeshIds,uniquePbrIds={},{}
    for id in pairs(meshIds) do uniqueMeshIds[#uniqueMeshIds+1]=id end
    for id in pairs(pbrIds) do uniquePbrIds[#uniquePbrIds+1]=id end
    table.sort(uniqueMeshIds);table.sort(uniquePbrIds)
    return canonical({placeId=game.PlaceId,universeId=game.GameId,
        root="ServerStorage.Level1BlenderKitV2",counts=counts,
        meshAssetIds=uniqueMeshIds,pbrAssetIds=uniquePbrIds,instances=records})
end

return true
