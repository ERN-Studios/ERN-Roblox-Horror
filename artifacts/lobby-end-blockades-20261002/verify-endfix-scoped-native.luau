-- Local disk audit only. All normalization is confined to deserialized copies.
-- Never writes an input backup and never communicates with Studio.
local fs, process, serde, rbx = require("@lune/fs"), require("@lune/process"), require("@lune/serde"), require("@lune/roblox")
local beforeDir, afterDir, pinsPath, outputPath = assert(process.args[1]), assert(process.args[2]), assert(process.args[3]), assert(process.args[4])
local function read(path) return serde.decode("json", fs.readFile(path)) end
local function sha(bytes) return serde.hash("sha256", bytes) end
local before, after, pins = read(beforeDir.."/metadata.json"), read(afterDir.."/metadata.json"), read(pinsPath)
local errors, sourceRows, newRows, rootRows, serviceRows = {}, {}, {}, {}, {}
local function check(ok, label) if not ok then table.insert(errors, label) end; return ok end
local function same(a,b)
	if typeof(a)~=typeof(b) then return false end
	if typeof(a)~="table" then return a==b end
	for key,value in a do if not same(value,b[key]) then return false end end
	for key in b do if a[key]==nil then return false end end
	return true
end
local hardScope = {
	["ServerScriptService.LobbyReimaginedPreview.Builder"]={class="ModuleScript",kind="existing"},
	["ServerScriptService.LobbyReimaginedPreview.EndBlockades"]={class="ModuleScript",kind="new"},
	["StarterPlayer.StarterPlayerScripts.R4DevGateController"]={class="LocalScript",kind="new"},
}
assert(pins.schema=="lobby-endfix-exact-native-scope-v1" and #pins.sources==3, "Unexpected source scope")
assert(#pins.allowedExistingAttributeChanges==1
	and pins.allowedExistingAttributeChanges[1].path=="ServerScriptService.LobbyReimaginedPreview.Builder"
	and pins.allowedExistingAttributeChanges[1].attribute=="InstalledSourceSHA256", "Unexpected attribute scope")
local specs={}
for _,spec in pins.sources do
	local expected=assert(hardScope[spec.path], "Unexpected scoped Source "..spec.path)
	assert(spec.class==expected.class and spec.kind==expected.kind and not specs[spec.path], "Wrong source kind/class")
	local candidate=fs.readFile(spec.candidateFile)
	assert(sha(candidate)==spec.afterSHA256 and #candidate==spec.afterBytes, "Pinned candidate changed: "..spec.path)
	specs[spec.path]=spec
end
assert(before.placeId==131311258779917 and after.placeId==before.placeId
	and before.universeId==10559217407 and after.universeId==before.universeId
	and before.groupId==1039373905 and after.groupId==before.groupId, "Wrong experience/owner")
assert(before.nativeSHA256==pins.expectedBeforeNativeSHA256, "Wrong authoritative before forest")
check(before.rootCount==pins.expectedBeforeRootCount and after.rootCount==pins.expectedAfterRootCount, "Unexpected root counts")
check(before.scriptCount==pins.expectedBeforeSourceCount and after.scriptCount==pins.expectedAfterSourceCount, "Unexpected Source counts")
check(before.captureId and after.captureId and before.captureId~=after.captureId, "No distinct after capture ID")
check(#before.editorConflicts==0 and #after.editorConflicts==0 and #before.skipped==0 and #after.skipped==0, "Capture conflict or skipped root")
local function native(directory, metadata)
	local bytes=fs.readFile(directory.."/all-service-children.rbxm")
	assert(sha(bytes)==metadata.nativeSHA256 and #bytes==metadata.nativeBytes, "Native bytes differ from capture")
	local roots=rbx.deserializeModel(bytes)
	assert(#roots==metadata.rootCount and #roots==#metadata.roots, "Native root count mismatch")
	local game=rbx.Instance.new("DataModel")
	local services, lookup={},{}
	for _,row in metadata.services do local service=game:GetService(row.class); service.Name=row.name; services[row.class]=service end
	for i,root in roots do
		local row=metadata.roots[i]
		assert(root.Name==row.name and root.ClassName==row.class, "Native root identity mismatch")
		root.Parent=assert(services[row.service])
		local key=row.service.."|"..row.name.."|"..row.class
		assert(not lookup[key], "Ambiguous native root")
		lookup[key]={instance=root,row=row}
	end
	local function resolve(path)
		local best
		for _,row in metadata.roots do
			if path==row.path or path:sub(1,#row.path+1)==row.path.."." then
				if not best or #row.path>#best.path then best=row end
			end
		end
		if not best then return nil end
		local cursor=services[best.service]:FindFirstChild(best.name)
		for token in path:sub(#best.path+2):gmatch("[^%.]+") do cursor=cursor and cursor:FindFirstChild(token) end
		return cursor
	end
	return roots,lookup,resolve
end
local beforeRoots,beforeLookup,resolveBefore=native(beforeDir,before)
local afterRoots,afterLookup,resolveAfter=native(afterDir,after)
local function canonicalizeAttributeStorage(roots)
	-- Lune distinguishes absent and explicitly empty AttributesSerialize fields.
	-- Normalize that storage equally, asserting every actual attribute stays equal.
	local absent="__EndFixAuditAbsentAttributeStorageKey"
	for _,root in roots do
		local nodes=root:GetDescendants(); table.insert(nodes,root)
		for _,instance in nodes do
			assert(instance:GetAttribute(absent)==nil, "Unexpected audit attribute exists")
			local attributes=instance:GetAttributes(); instance:SetAttribute(absent,nil)
			assert(same(attributes,instance:GetAttributes()), "Attribute normalization changed a value")
		end
	end
end
canonicalizeAttributeStorage(beforeRoots)
canonicalizeAttributeStorage(afterRoots)
local beforeSources,afterSources=read(beforeDir.."/scripts.json"),read(afterDir.."/scripts.json")
local afterSourceLookup={}
for _,row in afterSources do assert(not afterSourceLookup[row.path]); afterSourceLookup[row.path]=row end
check(#beforeSources==213 and #afterSources==215, "Expected exactly 213 original plus two new Sources")
local existingChanged,newCount=0,0
for _,row in beforeSources do
	local found=afterSourceLookup[row.path]
	local beforeSHA=sha(row.source)
	local afterSHA=found and sha(found.source)
	local editorMatch=found and found.editorMatch==true and found.editorSourceSha256==afterSHA
	check(row.editorMatch==true and row.editorSourceSha256==beforeSHA, "Before Source/editor conflict: "..row.path)
	check(found and found.class==row.class and editorMatch, "After Source/class/editor conflict: "..row.path)
	local b,a=resolveBefore(row.path),resolveAfter(row.path)
	check(b and a and b.Source==row.source and found and a.Source==found.source, "Native Source differs from live export: "..row.path)
	local spec=specs[row.path]
	if spec then
		check(spec.kind=="existing" and spec.class==row.class and spec.beforeSHA256==beforeSHA
			and spec.afterSHA256==afterSHA and found and #found.source==spec.afterBytes, "Scoped existing Source pin differs: "..row.path)
		if a and b then
			check(a:GetAttribute("InstalledSourceSHA256")==afterSHA, "Builder installed hash differs")
			local oldInstalled=b:GetAttribute("InstalledSourceSHA256")
			b:SetAttribute("InstalledSourceSHA256",oldInstalled)
			a:SetAttribute("InstalledSourceSHA256",oldInstalled)
			a.Source=b.Source -- Deserialized comparison memory only.
		end
		existingChanged+=1
	else check(beforeSHA==afterSHA, "Unrelated Source changed: "..row.path) end
	table.insert(sourceRows,{path=row.path,class=row.class,beforeSHA256=beforeSHA,afterSHA256=afterSHA,
		ownedScopedChange=spec~=nil,sourceUnchanged=beforeSHA==afterSHA,editorMatch=editorMatch==true})
	afterSourceLookup[row.path]=nil
end
for path,row in afterSourceLookup do
	local spec=specs[path]
	check(spec and spec.kind=="new", "Unexpected new Source: "..path)
	if spec and spec.kind=="new" then
		local instance=resolveAfter(path)
		local digest=sha(row.source)
		check(row.class==spec.class and digest==spec.afterSHA256 and #row.source==spec.afterBytes
			and row.editorMatch==true and row.editorSourceSha256==digest, "New Source/class/editor pin differs: "..path)
		check(instance and instance.ClassName==spec.class and instance.Source==row.source
			and instance:GetAttribute("LobbyReimaginedOwned")==true
			and instance:GetAttribute("InstalledSourceSHA256")==digest
			and #instance:GetDescendants()==0, "New instance identity/ownership/hash/descendants differs: "..path)
		if instance then
			table.insert(newRows,{path=path,class=row.class,sha256=digest,bytes=#row.source,
				editorMatch=row.editorMatch,attributes=instance:GetAttributes(),descendants=#instance:GetDescendants()})
			instance.Parent=nil -- Only these two exact new source instances leave the local normalized forest.
		end
		newCount+=1
	end
end
check(existingChanged==1 and newCount==2, "Not exactly one existing Source and two owned Source additions")
for key,row in afterLookup do check(beforeLookup[key]~=nil, "Unexpected additive native root: "..row.row.path) end
local normalizedAfterRoots={}
for _,root in beforeRoots do
	local key,prior
	for candidate,row in beforeLookup do if row.instance==root then key=candidate;prior=row;break end end
	local match=afterLookup[key]
	check(match~=nil, "Existing native root missing: "..prior.row.path)
	if match then
		local beforeHash=sha(rbx.serializeModel({root}))
		local afterHash=sha(rbx.serializeModel({match.instance}))
		local equal=beforeHash==afterHash
		check(equal, "Native root properties/geometry changed outside exact scope: "..prior.row.path)
		table.insert(rootRows,{path=prior.row.path,class=prior.row.class,normalizedCanonicalEqual=equal,
			beforeCanonicalSHA256=beforeHash,afterNormalizedCanonicalSHA256=afterHash})
		table.insert(normalizedAfterRoots,match.instance)
	end
end
local beforeCanonical=sha(rbx.serializeModel(beforeRoots))
local afterCanonical=sha(rbx.serializeModel(normalizedAfterRoots))
check(beforeCanonical==afterCanonical, "Whole forest differs beyond exact scoped Source/attribute additions")
for _,field in ipairs({"services","collisionGroups","collisionMatrix","materialOverrides"})do
	local equal=same(before[field],after[field]);check(equal, "Saved settings changed: "..field)
	table.insert(serviceRows,{field=field,equal=equal})
end
local report={schema="lobby-endfix-scoped-native-preservation-v1",verified=#errors==0,
	scope="Independent local full before/after native forest comparison; no Studio actions or input edits",
	beforeCaptureId=before.captureId,afterCaptureId=after.captureId,beforeNativeSHA256=before.nativeSHA256,afterNativeSHA256=after.nativeSHA256,
	pinsSHA256=sha(fs.readFile(pinsPath)),beforeRootCount=#beforeRoots,afterRootCount=#afterRoots,
	beforeSourceCount=#beforeSources,afterSourceCount=#afterSources,existingScopedSources=existingChanged,newScopedSources=newCount,
	canonicalBeforeSHA256=beforeCanonical,canonicalAfterScopedNormalizationSHA256=afterCanonical,
	baselineForestCanonicalEqual=beforeCanonical==afterCanonical,sourceRows=sourceRows,newSourceRows=newRows,
	rootRows=rootRows,serviceRows=serviceRows,errors=errors,
	normalization="Only the pinned Builder Source and its InstalledSourceSHA256 are reset to before values, and only the two exact pinned owned new source instances are omitted, in deserialized memory. Absent/empty attribute serialization is normalized equally while every real attribute value is checked unchanged. No game, input backup, other Source, geometry, service setting or property is changed."}
fs.writeFile(outputPath,serde.encode("json",report,true).."\n")
print(serde.encode("json",{verified=report.verified,errors=errors,existingScopedSources=existingChanged,newScopedSources=newCount,
	baselineForestCanonicalEqual=report.baselineForestCanonicalEqual,output=outputPath},true))
assert(report.verified,"Unresolved native preservation differences; preserve current Studio, never restore an older snapshot")
