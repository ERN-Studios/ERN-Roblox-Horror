from pathlib import Path
import difflib, hashlib, json, subprocess

ROOT=Path(__file__).resolve().parent
TASK=ROOT.parent
BASE=TASK/'baseline'/'sources'
LUAU=TASK.parent/'level5-build'/'tools'/'luau'

def sha(text):return hashlib.sha256(text.encode()).hexdigest()
def djb(text):
    value=5381
    for b in text.encode():value=(value*33+b)%4294967296
    return value
def quoted(text):
    value=json.dumps(text,ensure_ascii=False)
    assert '\\u00' not in value, 'Unexpected control character requires Luau decimal escaping'
    return value

# The only additional clue change requested by the root: keep the complete
# authored answer/layout/title; reduce dependence on dim lighting for B only.
clue_rel='ServerScriptService/Level 5 Systems/Level 5 Section Progression.ModuleScript.lua'
clue_old=(BASE/clue_rel).read_text()
needle='\t\t\t\tlocal gui,oldLabel=surface(board,"",Vector2.new(900,720));oldLabel:Destroy();gui.Name="PuzzleClueGui"\n'
assert clue_old.count(needle)==1
clue_new=clue_old.replace(needle,needle+'\t\t\t\tif gateIndex==2 then gui.LightInfluence=.25 end -- Keep the indoor B clue readable in dim light.\n',1)
clue_path=TASK/'clue-drafts'/'sources'/clue_rel
clue_path.parent.mkdir(parents=True,exist_ok=True);clue_path.write_text(clue_new)
(TASK/'clue-drafts'/'manifest.json').write_text(json.dumps({'file':clue_rel,'baselineSha256':sha(clue_old),'draftSha256':sha(clue_new),'liveApplied':False},indent=2)+'\n')
(TASK/'clue-drafts'/'clue.patch').write_text(''.join(difflib.unified_diff(clue_old.splitlines(keepends=True),clue_new.splitlines(keepends=True),fromfile='baseline/'+clue_rel,tofile='draft/'+clue_rel)))

meta={row['file']:row for row in json.loads((TASK/'baseline'/'source-index.json').read_text())}
items=[]
for row in json.loads((TASK/'access-drafts'/'manifest.json').read_text()):
    items.append((row['file'],TASK/'access-drafts'/'sources'/row['file'],row))
lobby=json.loads((TASK/'lobby-drafts'/'draft-manifest.json').read_text())
items.append(('ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua',TASK/'lobby-drafts'/'TunnelLobbyBuilder.ModuleScript.lua',lobby))
outage=json.loads((TASK/'outage-drafts'/'manifest.json').read_text())
items.append((outage['file'],TASK/'outage-drafts'/'sources'/outage['file'],outage))
items.append((clue_rel,clue_path,{'baselineSha256':sha(clue_old),'draftSha256':sha(clue_new)}))

template='''-- Single existing script only. Generated from verified baseline; DO NOT RUN AS A BATCH.
-- No new Instances, source buffers, runtime rebuilds, attributes or property edits.
local HttpService=game:GetService("HttpService")
local ScriptEditorService=game:GetService("ScriptEditorService")
local names=__NAMES__
local wantedClass=__CLASS__
local baselineLength,baselineDjb=__OLDLEN__,__OLDHASH__
local expectedLength,expectedDjb=__NEWLEN__,__NEWHASH__
local invoked,accepted=false,false
local function djb2(text)
 local h=5381
 for i=1,#text do h=(h*33+string.byte(text,i))%4294967296 end
 return h
end
local function finish(status,detail)
 return HttpService:JSONEncode({status=status,detail=detail or "",path=table.concat(names,"."),class=wantedClass,
  updateInvoked=invoked,callbackAccepted=accepted,baselineLength=baselineLength,baselineDjb2=baselineDjb,
  expectedLength=expectedLength,expectedDjb2=expectedDjb})
end
if game.PlaceId~=131311258779917 or game.GameId~=10559217407 then return finish("WRONG_PLACE") end
if game:GetService("RunService"):IsRunning() then return finish("EDIT_MODE_REQUIRED") end
local function resolve()
 local parent=game
 for _,name in ipairs(names) do
  local found=nil
  for _,child in ipairs(parent:GetChildren()) do
   if child.Name==name then
    if found then return nil,"AMBIGUOUS_PATH" end
    found=child
   end
  end
  if not found then return nil,"MISSING_PATH" end
  parent=found
 end
 if parent.ClassName~=wantedClass then return nil,"WRONG_CLASS" end
 return parent,nil
end
local target,resolveError=resolve()
if not target then return finish(resolveError) end
local ok,current,editor=pcall(function()return target.Source,ScriptEditorService:GetEditorSource(target)end)
if not ok then return finish("READ_FAILED",tostring(current)) end
if current~=editor then return finish("SOURCE_EDITOR_CONFLICT") end
if #current~=baselineLength or djb2(current)~=baselineDjb then return finish("BASELINE_CHANGED") end
local edits={
__EDITS__
}
local ranges={}
for index,edit in ipairs(edits) do
 local a,b=string.find(current,edit.old,1,true)
 if not a then return finish("FRAGMENT_MISSING",tostring(index)) end
 if string.find(current,edit.old,a+1,true) then return finish("FRAGMENT_NOT_UNIQUE",tostring(index)) end
 if index>1 and a<=ranges[index-1].last then return finish("OVERLAPPING_FRAGMENTS",tostring(index)) end
 ranges[index]={first=a,last=b,replacement=edit.new}
end
local newSource=current
for index=#ranges,1,-1 do
 local span=ranges[index]
 newSource=string.sub(newSource,1,span.first-1)..span.replacement..string.sub(newSource,span.last+1)
end
if #newSource~=expectedLength or djb2(newSource)~=expectedDjb then return finish("PATCH_FINGERPRINT_MISMATCH") end
if newSource==current then return finish("NO_CHANGE") end
local callbackProblem=nil
local writeOK,writeError=pcall(function()
 invoked=true
 ScriptEditorService:UpdateSourceAsync(target,function(old)
  -- Roblox may call again if an editor changes while the update is in flight.
  -- Returning nil cancels the update, including on a later retry.
  if callbackProblem then return nil end
  if old~=current then callbackProblem="CALLBACK_BASELINE_CHANGED";return nil end
  local stillTarget=resolve()
  if stillTarget~=target then callbackProblem="INSTANCE_PATH_CHANGED";return nil end
  if target.Source~=current then callbackProblem="SOURCE_CHANGED_DURING_UPDATE";return nil end
  accepted=true
  return newSource
 end)
end)
if callbackProblem then return finish(callbackProblem,"Cancelled; reread authoritative Source/editor before preparing another patch.") end
if not writeOK then return finish("UPDATE_FAILED",tostring(writeError)) end
if not accepted then return finish("UPDATE_CANCELLED") end
local readOK,sourceAfter,editorAfter=pcall(function()return target.Source,ScriptEditorService:GetEditorSource(target)end)
if not readOK then return finish("POSTWRITE_READ_FAILED",tostring(sourceAfter)) end
if sourceAfter==newSource and editorAfter==newSource then return finish("APPLIED_VERIFIED") end
return finish("POSTWRITE_PARITY_NOT_VERIFIED",HttpService:JSONEncode({sourceLength=#sourceAfter,sourceDjb2=djb2(sourceAfter),editorLength=#editorAfter,editorDjb2=djb2(editorAfter),equal=sourceAfter==editorAfter}))
'''

verification_template='''-- Read-only verification for a separately executed single-script payload.
local H=game:GetService("HttpService");local E=game:GetService("ScriptEditorService")
local names=__NAMES__;local target=game
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
assert(not game:GetService("RunService"):IsRunning(),"Edit mode required")
for _,name in ipairs(names) do
 local found=nil
 for _,child in ipairs(target:GetChildren()) do if child.Name==name then assert(not found,"Ambiguous path");found=child end end
 assert(found,"Missing path");target=found
end
assert(target.ClassName==__CLASS__,"Wrong class")
local function djb(s)local h=5381;for i=1,#s do h=(h*33+string.byte(s,i))%4294967296 end;return h end
local s,e=target.Source,E:GetEditorSource(target)
return H:JSONEncode({path=target:GetFullName(),version=game.PlaceVersion,sourceLength=#s,editorLength=#e,sourceDjb2=djb(s),editorDjb2=djb(e),equal=s==e,expectedLength=__NEWLEN__,expectedDjb2=__NEWHASH__,matchesExpected=s==e and #s==__NEWLEN__ and djb(s)==__NEWHASH__})
'''

manifest=[]
for index,(rel,draft_path,record) in enumerate(items,1):
    old=(BASE/rel).read_text();new=draft_path.read_text();m=meta[rel]
    assert sha(old)==record['baselineSha256']==m['sha256'],rel
    assert sha(new)==record['draftSha256'],rel
    old_lines,new_lines=old.splitlines(keepends=True),new.splitlines(keepends=True)
    groups=list(difflib.SequenceMatcher(None,old_lines,new_lines,autojunk=False).get_grouped_opcodes(n=3))
    fragments=[]
    for group in groups:
        a,b=group[0][1],group[-1][2];c,d=group[0][3],group[-1][4]
        before,after=''.join(old_lines[a:b]),''.join(new_lines[c:d])
        assert before and old.count(before)==1,(rel,a,b,'fragment not unique')
        fragments.append({'old':before,'new':after,'baselineStartLine':a+1,'baselineEndLine':b})
    check=old
    for part in reversed(fragments):check=check.replace(part['old'],part['new'],1)
    assert check==new,rel
    names='{'+','.join(quoted(n) for n in m['names'])+'}'
    substitutes={'__NAMES__':names,'__CLASS__':quoted(m['class']),'__OLDLEN__':str(len(old.encode())),'__OLDHASH__':str(djb(old)),
        '__NEWLEN__':str(len(new.encode())),'__NEWHASH__':str(djb(new)),
        '__EDITS__':',\n'.join(' {old='+quoted(f['old'])+',new='+quoted(f['new'])+'}' for f in fragments)}
    payload=template;verify=verification_template
    for key,value in substitutes.items():payload=payload.replace(key,value);verify=verify.replace(key,value)
    short={1:'game-manager',2:'level5-adapter',3:'window-watcher',4:'lobby-builder',5:'outage',6:'b-clue'}[index]
    payload_path=ROOT/f'{index:02d}-{short}.apply.luau';payload_path.write_text(payload)
    verify_path=ROOT/f'{index:02d}-{short}.verify.luau';verify_path.write_text(verify)
    for file in [payload_path,verify_path]:
        result=subprocess.run([str(LUAU/'luau-compile'),'-O0','--null',str(file)],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
    wrapper=ROOT/'checks'/f'{index:02d}-{short}.compile.luau';wrapper.parent.mkdir(exist_ok=True)
    wrapper.write_text('return function()\n'+new+'\nend\n')
    result=subprocess.run([str(LUAU/'luau-compile'),'-O0','--null',str(wrapper)],capture_output=True,text=True)
    assert result.returncode==0,result.stdout+result.stderr
    manifest.append({'file':rel,'studioPath':m['path'],'names':m['names'],'class':m['class'],
        'draftFile':str(draft_path),'payloadFile':str(payload_path),'verifyFile':str(verify_path),
        'baselineLength':len(old.encode()),'baselineDjb2':djb(old),'baselineSha256':sha(old),
        'expectedLength':len(new.encode()),'expectedDjb2':djb(new),'expectedSha256':sha(new),
        'fragmentCount':len(fragments),'contextLines':3,'payloadBytes':len(payload.encode()),'compileO0':True,
        'fragments':[{'start':f['baselineStartLine'],'end':f['baselineEndLine'],'oldBytes':len(f['old'].encode()),'newBytes':len(f['new'].encode())}for f in fragments]})
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps([{k:r[k]for k in ['file','baselineLength','baselineDjb2','expectedLength','expectedDjb2','fragmentCount','payloadBytes']} for r in manifest],indent=2))
