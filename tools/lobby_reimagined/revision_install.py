"""Generate a fresh-baseline guarded correction of this task's own preview only."""
import json
from pathlib import Path
from serve import load_package,sha
from install import long_string
ROOT=Path(__file__).resolve().parents[2]
TASK=ROOT/'artifacts/lobby-reimagined-20261001'
package=load_package(ROOT/'assets/models/lobby-reimagined-20261001',Path(__file__).with_name('source_module_manifest.json'))
plan=package['plan']
baseline=json.loads((TASK/'installed-source-manifest.json').read_text())
by_path={x['path']:x for x in baseline['scripts']}
expected=[by_path[x['path']] for x in plan['sources']]
code=r'''-- R2 correction: additive source payload + CAS on exactly four new preview Sources.
local HS=game:GetService("HttpService")
local E=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local SS=game:GetService("ServerStorage")
local PLAN=HS:JSONDecode(__PLAN__)
local EXPECTED=HS:JSONDecode(__EXPECTED__)
local BASE="http://127.0.0.1:8892"
assert(game.PlaceId==PLAN.placeId and game.GameId==PLAN.universeId and game.CreatorId==PLAN.groupId)
assert(not game:GetService("RunService"):IsRunning(),"Edit only")
assert(not SS:FindFirstChild(PLAN.sourceName),"R2 payload already exists; inspect it")
local function sha(raw)
    local b=E:ComputeBufferHash(raw,Enum.HashAlgorithm.Sha256);local t={}
    for i=0,buffer.len(b)-1 do t[i+1]=string.format("%02x",buffer.readu8(b,i))end
    return table.concat(t)
end
local function resolve(path)
    local cursor=game
    for token in path:gmatch("[^%.]+")do cursor=cursor and cursor:FindFirstChild(token)end
    return cursor
end
local baseline={}
for _,row in ipairs(EXPECTED)do
    local instance=assert(resolve(row.path),"Preview Source missing")
    assert(instance.ClassName==row.class and instance:GetAttribute("LobbyReimaginedOwned")==true)
    local source=instance.Source
    assert(sha(buffer.fromstring(source))==row.sourceSha256 and SES:GetEditorSource(instance)==source,"Fresh preview baseline/editor differs")
    baseline[row.path]={instance=instance,source=source}
end
local source=Instance.new("Folder");source.Name=PLAN.sourceName;source:SetAttribute("LobbyReimaginedOwned",true)
local function compressed(name,raw,parent,expected)
    assert(buffer.len(raw)==expected.bytes and sha(raw)==expected.sha256,"Wrong R2 payload "..name)
    local folder=Instance.new("Folder");folder.Name=name;folder.Parent=parent
    local packed=E:CompressBuffer(raw,Enum.CompressionAlgorithm.Zstd,3)
    local encoded=buffer.tostring(E:Base64Encode(packed))
    for offset=1,#encoded,60000 do
        local item=Instance.new("StringValue");item.Name=string.format("%05d",math.floor((offset-1)/60000));item.Value=encoded:sub(offset,offset+59999);item.Parent=folder
    end
    folder:SetAttribute("RawBytes",buffer.len(raw));folder:SetAttribute("RawSHA256",expected.sha256);folder:SetAttribute("CompressedBytes",buffer.len(packed))
end
local oldHttp=HS.HttpEnabled
local texts={}
local ok,err=pcall(function()
    HS.HttpEnabled=true
    local serverPlan=HS:JSONDecode(HS:GetAsync(BASE.."/source-module-manifest",true))
    assert(serverPlan.manifestSha256==PLAN.manifestSha256 and serverPlan.sourceName==PLAN.sourceName)
    local raw=buffer.fromstring(HS:GetAsync(BASE.."/manifest",true))
    compressed("ManifestJSON",raw,source,{bytes=PLAN.manifestBytes,sha256=PLAN.manifestSha256})
    local meshes=Instance.new("Folder");meshes.Name="Meshes";meshes.Parent=source
    for _,chunk in ipairs(PLAN.chunks)do
        compressed(tostring(chunk.id),E:Base64Decode(buffer.fromstring(HS:GetAsync(BASE.."/chunk/"..chunk.id,true))),meshes,chunk)
    end
    compressed("AtlasPixels",E:Base64Decode(buffer.fromstring(HS:GetAsync(BASE.."/atlas-pixels",true))),source,PLAN.atlas)
    for _,spec in ipairs(PLAN.sources)do
        local text=HS:GetAsync(BASE.."/script/"..spec.key,true)
        assert(#text==spec.bytes and sha(buffer.fromstring(text))==spec.sha256,"Candidate Source differs")
        texts[spec.path]=text
    end
    assert(not SS:FindFirstChild(PLAN.sourceName) and not game:GetService("RunService"):IsRunning())
    for path,row in pairs(baseline)do
        assert(resolve(path)==row.instance and row.instance.Source==row.source and SES:GetEditorSource(row.instance)==row.source,"Preview baseline changed during download")
    end
    source:SetAttribute("ManifestSHA256",PLAN.manifestSha256);source:SetAttribute("Ready",true);source.Parent=SS
    for _,spec in ipairs(PLAN.sources)do
        local row=baseline[spec.path]
        assert(resolve(spec.path)==row.instance and row.instance.Source==row.source and SES:GetEditorSource(row.instance)==row.source,"Fresh Source changed before scoped write")
        SES:UpdateSourceAsync(row.instance,function(editor)
            assert(editor==row.source and row.instance.Source==row.source,"Source changed inside CAS callback")
            return texts[spec.path]
        end)
        assert(row.instance.Source==texts[spec.path] and SES:GetEditorSource(row.instance)==texts[spec.path],"Post-write Source/editor conflict")
        row.instance:SetAttribute("InstalledSourceSHA256",spec.sha256)
    end
end)
HS.HttpEnabled=oldHttp
if not ok then
    if not source.Parent then source:Destroy()end -- Only our off-tree staging content.
    error(err) -- A partial correction is reported for fresh reconciliation, never reverted blindly.
end
return {Installed=true,Source=source:GetFullName(),ManifestSHA256=PLAN.manifestSha256,Sources=4,Chunks=#PLAN.chunks}
'''
code=code.replace('__PLAN__',long_string(json.dumps(plan,separators=(',',':')))).replace('__EXPECTED__',long_string(json.dumps(expected,separators=(',',':'))))
output=TASK/'install_revision_r2.luau'
assert not output.exists() or output.read_text()==code,'Refusing different revision installer'
output.write_text(code)
output.with_suffix('.receipt.json').write_text(json.dumps({'sha256':sha(code.encode()),'manifestSha256':plan['manifestSha256'],'sources':plan['sources'],'expected':expected,'scope':'R2 additive payload; only four owned preview Sources have explicit fresh Source/editor CAS'},indent=2)+'\n')
print('R2 installer generated',plan['manifestSha256'])
