-- Local only: deserialize saved places, compare Sources/editor catalog, and
-- compare canonical native content after masking Source in memory. No Studio.
local fs, process = require("@lune/fs"), require("@lune/process")
local serde, rbx = require("@lune/serde"), require("@lune/roblox")
local beforePath = assert(process.args[1], "before.rbxl")
local afterPath = assert(process.args[2], "after.rbxl")
local manifestPath = assert(process.args[3], "frozen five-source install manifest")
local livePath = assert(process.args[4], "fresh all-231 live Source/editor catalog")
local out = assert(process.args[5], "existing output directory")
local receiptPath, payloadPath = out.."/native-five-verification.json", out.."/native-five-sources.json"
assert(not fs.isFile(receiptPath) and not fs.isFile(payloadPath), "Do not overwrite a verification")
local function sha(s) return serde.hash("sha256", s) end
local manifestBytes, liveBytes = fs.readFile(manifestPath), fs.readFile(livePath)
local manifest, live = serde.decode("json", manifestBytes), serde.decode("json", liveBytes)
assert(live.placeId == 131311258779917 and live.universeId == 10559217407, "Wrong live catalog identity")
assert(live.isRunning == false, "Require stopped Edit catalog")
assert(type(live.capturedAtUTC) == "string", "Require live capture time")
local expectedClasses = {
    ["ServerScriptService.Level 3 Systems.Level 3 Mall Manager AI Controller"]="ModuleScript",
    ["ServerScriptService.Level 3 Systems.Level 3 Objective Controller"]="ModuleScript",
    ["ServerScriptService.Level 3 Systems.Level 3 World Builder"]="ModuleScript",
    ["ServerScriptService.Level 3 Systems.Level 3 Worn Party Visual Adapter"]="ModuleScript",
    ["StarterPlayer.StarterPlayerScripts.Level 3 Reader Client"]="LocalScript",
}
local expected = {}
local targets = manifest.changes or manifest.rows
assert(type(targets) == "table" and #targets == 5, "Require exactly five frozen targets")
for _, row in targets do
    local class = row.class or row.className
    assert(expectedClasses[row.path] == class and not expected[row.path], "Unexpected/duplicate target "..tostring(row.path))
    local baseline = assert(row.baselineSHA256 or row.sourceHash or row.expectedSourceSHA256, "Missing baseline hash")
    local candidate = assert(row.candidateSHA256 or row.candidateHash, "Missing candidate hash")
    local candidateFile = assert(row.candidateFile or row.candidatePath, "Missing candidate file")
    assert(sha(fs.readFile(candidateFile)) == candidate, "Frozen candidate file changed "..row.path)
    expected[row.path] = {class=class,baselineSHA256=baseline,candidateSHA256=candidate}
end
local liveRows = live.sources or live.scripts or live.sourceRows
assert(type(liveRows) == "table" and #liveRows == 231, "Require all 231 live Sources")
local liveByPath = {}
for _, row in liveRows do
    assert(not liveByPath[row.path], "Duplicate live Source path "..row.path)
    local sourceHash = assert(row.sourceSHA256 or row.sourceSha256 or row.sourceHash or row.sha256, "Missing live Source hash")
    local editorHash = assert(row.editorSHA256 or row.editorSourceSha256 or row.editorHash, "Missing live editor hash")
    assert(row.editorMatch == true and sourceHash == editorHash, "Live Source/editor conflict "..row.path)
    liveByPath[row.path] = {class=row.class or row.className,sha256=sourceHash,bytes=row.sourceBytes or row.bytes}
end
local beforeBytes, afterBytes = fs.readFile(beforePath), fs.readFile(afterPath)
assert(#beforeBytes == 51826241
    and sha(beforeBytes) == "bc32152e6fd668aab75108576c454ef84a3c914ec4e606f094e5599c5e34f378",
    "Wrong authoritative before native backup")
local before, after = rbx.deserializePlace(beforeBytes), rbx.deserializePlace(afterBytes)
local function collect(game)
    local sources, count = {}, 0
    for _, instance in game:GetDescendants() do
        if instance:IsA("LuaSourceContainer") then
            local path = instance:GetFullName()
            assert(not sources[path], "Ambiguous native Source path "..path)
            sources[path] = {instance=instance,class=instance.ClassName,source=instance.Source}
            count += 1
        end
    end
    assert(count == 231, "Wrong native Source count "..count)
    return sources
end
local oldSources, newSources = collect(before), collect(after)
local sourceRows, changedRows, payload = {}, {}, {}
for path, prior in oldSources do
    local current = assert(newSources[path], "Native Source removed "..path)
    local observed = assert(liveByPath[path], "Native Source absent from live catalog "..path)
    assert(current.class == prior.class and current.class == observed.class, "Source class changed "..path)
    local oldHash, newHash = sha(prior.source), sha(current.source)
    assert(observed.sha256 == newHash, "Saved native after/live Source mismatch "..path)
    if observed.bytes then assert(observed.bytes == #current.source, "Live Source byte count mismatch "..path) end
    local changed = prior.source ~= current.source
    local target = expected[path]
    if target then
        assert(oldHash == target.baselineSHA256 and newHash == target.candidateSHA256, "Native baseline/candidate mismatch "..path)
        assert(changed, "Expected target did not change "..path)
        table.insert(payload,{path=path,class=current.class,source=current.source,sourceSHA256=newHash,sourceBytes=#current.source})
    else assert(not changed, "Unrelated native Source changed "..path) end
    local row = {path=path,class=current.class,beforeSHA256=oldHash,afterSHA256=newHash,
        beforeBytes=#prior.source,afterBytes=#current.source,changed=changed,liveEditorMatch=true}
    table.insert(sourceRows,row)
    if changed then table.insert(changedRows,row) end
end
assert(#changedRows == 5 and #payload == 5, "Changed Sources are not exactly the five targets")
table.sort(sourceRows,function(a,b) return a.path<b.path end)
table.sort(changedRows,function(a,b) return a.path<b.path end)
table.sort(payload,function(a,b) return a.path<b.path end)
-- Compare all properties, attributes, instance references and content supported
-- by Lune's native serializer. Mask only Source; raw native files stay untouched.
for _, row in oldSources do row.instance.Source = "" end
for _, row in newSources do row.instance.Source = "" end
local canonicalBefore = sha(rbx.serializePlace(before))
local canonicalAfter = sha(rbx.serializePlace(after))
local roots = {}
for _, root in before:GetChildren() do
    local matches = {}
    for _, other in after:GetChildren() do
        if other.Name == root.Name and other.ClassName == root.ClassName then table.insert(matches,other) end
    end
    assert(#matches == 1, "Ambiguous/missing native service root "..root.Name)
    local other = matches[1]
    table.insert(roots,{name=root.Name,class=root.ClassName,beforeDescendants=#root:GetDescendants(),
        afterDescendants=#other:GetDescendants(),sourceMaskedCanonicalBeforeSHA256=sha(rbx.serializeModel({root})),
        sourceMaskedCanonicalAfterSHA256=sha(rbx.serializeModel({other}))})
end
table.sort(roots,function(a,b) return a.name<b.name end)
local nativeEqual = canonicalBefore == canonicalAfter
local report = {schema="level3-finale-native-five-v1",verified=nativeEqual,
    placeId=live.placeId,universeId=live.universeId,liveCapturedAtUTC=live.capturedAtUTC,
    beforeNativePath=beforePath,afterNativePath=afterPath,beforeNativeBytes=#beforeBytes,afterNativeBytes=#afterBytes,
    beforeNativeSHA256=sha(beforeBytes),afterNativeSHA256=sha(afterBytes),
    beforeServiceRoots=#before:GetChildren(),afterServiceRoots=#after:GetChildren(),
    beforeDescendants=#before:GetDescendants(),afterDescendants=#after:GetDescendants(),
    sourceCount=231,changedSourceCount=#changedRows,unchangedSourceCount=231-#changedRows,
    allSourcePathsClassesEqual=true,onlyFiveExpectedSourcesChanged=true,all231SavedLiveSourceEditorMatch=true,
    sourceMaskedNativeCanonicalEqual=nativeEqual,sourceMaskedBeforeCanonicalSHA256=canonicalBefore,
    sourceMaskedAfterCanonicalSHA256=canonicalAfter,roots=roots,sources=sourceRows,changes=changedRows,
    installManifestPath=manifestPath,installManifestSHA256=sha(manifestBytes),
    liveCatalogPath=livePath,liveCatalogSHA256=sha(liveBytes),
    studioWrites=false,repositorySourceWrites=false,gitWrites=false,publicationClaim=false,
    limits="Raw full native files retained. All 231 exact native Source paths/classes and bytes compared; all fresh live Source/editor hashes matched saved after. Non-Source canonical comparison covers native content supported by Lune deserialize/serialize; unsupported native data remains retained in raw backups but has no semantic-equality claim. No gameplay/performance or publication claim."}
fs.writeFile(receiptPath,serde.encode("json",report,true).."\n")
assert(nativeEqual, "Source-masked native content differs; inspect per-root receipt. Export blocked.")
fs.writeFile(payloadPath,serde.encode("json",payload,true).."\n")
print(serde.encode("json",{verified=true,sourceCount=231,changedSources=5,unchangedSources=226,
    nativeContentEqual=true,beforeNativeSHA256=report.beforeNativeSHA256,afterNativeSHA256=report.afterNativeSHA256,
    receipt=receiptPath,payload=payloadPath},true))
