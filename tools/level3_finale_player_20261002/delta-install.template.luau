-- Reviewed scoped Source delta installer; parent only, correct Studio Edit context.
-- No place restore, instance creation, external upload, or unrelated script writes.
local E, SES = game:GetService("EncodingService"), game:GetService("ScriptEditorService")
local R, H = game:GetService("RunService"), game:GetService("HttpService")
assert(not R:IsRunning(), "Edit only")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong place/universe")
local rows = __ROWS__
assert(#rows == 5, "Unexpected scope")
local function hash(source)
    local digest = E:ComputeBufferHash(buffer.fromstring(source), Enum.HashAlgorithm.Sha256)
    local bytes = {}
    for index=0,buffer.len(digest)-1 do bytes[index+1]=string.format("%02x",buffer.readu8(digest,index)) end
    return table.concat(bytes)
end
local function at(path)
    local object = game
    for name in path:gmatch("[^.]+") do object=assert(object:FindFirstChild(name),"Missing path: "..path) end
    return object
end
local targets, parents, expected, prepared = {}, {}, {}, {}
for _,row in ipairs(rows) do
    assert(row.className == "ModuleScript" or row.className == "LocalScript", "Unexpected class")
    assert(row.baselineSHA256 == row.editorSHA256, "Unresolved captured editor conflict")
    targets[row.path] = at(row.path)
    parents[row.path] = targets[row.path].Parent
    expected[row.path] = row.baselineSHA256
end
local function verifyAll()
    assert(not R:IsRunning() and game.PlaceId == 131311258779917 and game.GameId == 10559217407,
        "Context changed")
    for _,row in ipairs(rows) do
        local object = at(row.path)
        assert(object == targets[row.path] and object.Parent == parents[row.path]
            and object.ClassName == row.className, "Instance/class/parent changed: "..row.path)
        assert(hash(object.Source) == expected[row.path]
            and hash(SES:GetEditorSource(object)) == expected[row.path],
            "Fresh Source/editor changed: "..row.path)
    end
end
verifyAll() -- All five are checked before any candidate preparation or mutation.
local prewrite = {}
for _,row in ipairs(rows) do
    local current = targets[row.path].Source
    assert(#current == row.baselineBytes, "Baseline byte mismatch")
    table.insert(prewrite,{path=row.path,className=targets[row.path].ClassName,
        sourceSHA256=hash(current),editorSHA256=hash(SES:GetEditorSource(targets[row.path])),
        bytes=#current,editorMatch=current==SES:GetEditorSource(targets[row.path])})
    for _,patch in ipairs(row.patches) do
        local first,last = current:find(patch.before,1,true)
        assert(first and not current:find(patch.before,last+1,true),"Nonunique exact patch: "..row.path)
        current = current:sub(1,first-1)..patch.after..current:sub(last+1)
    end
    assert(#current == row.candidateBytes and hash(current) == row.candidateSHA256,
        "Prepared candidate mismatch: "..row.path)
    local compiled,problem = loadstring(current,"="..row.path)
    assert(compiled, "Candidate compile failed: "..row.path..": "..tostring(problem))
    prepared[row.path] = current
end
verifyAll() -- Compile/preparation may yield; all baselines must still match.
for _,row in ipairs(rows) do
    local object = targets[row.path]
    SES:UpdateSourceAsync(object,function(current)
        -- The whole set is rechecked, including already-written candidate hashes.
        verifyAll()
        assert(hash(current) == expected[row.path],"Callback baseline changed: "..row.path)
        return prepared[row.path]
    end)
    assert(object.Source == prepared[row.path] and SES:GetEditorSource(object) == prepared[row.path],
        "Post-write Source/editor conflict: "..row.path)
    expected[row.path] = row.candidateSHA256
    verifyAll()
end
verifyAll()
local receipt = {task="level3-finale-player-20261002",installedAtUTC=DateTime.now():ToIsoDate(),
    placeId=game.PlaceId,universeId=game.GameId,sourceCount=#rows,sceneChanged=false,
    nativeBeforeSHA256="bc32152e6fd668aab75108576c454ef84a3c914ec4e606f094e5599c5e34f378",
    prewrite=prewrite,sources={}}
for _,row in ipairs(rows) do
    local object = targets[row.path]
    assert(hash(object.Source)==row.candidateSHA256 and SES:GetEditorSource(object)==prepared[row.path],
        "Final Source/editor mismatch: "..row.path)
    table.insert(receipt.sources,{path=row.path,className=object.ClassName,
        sourceSHA256=hash(object.Source),editorSHA256=hash(SES:GetEditorSource(object)),
        candidateSHA256=row.candidateSHA256,bytes=#object.Source,editorMatch=true})
end
print("LEVEL3_FINALE_PLAYER_SCOPED_INSTALL_OK",H:JSONEncode(receipt))
return receipt
