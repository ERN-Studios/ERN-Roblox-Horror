"""Actual candidate main/read protocol and generated guard ports; never Studio."""
from pathlib import Path
from contextlib import redirect_stdout
from unittest.mock import patch
import argparse
import copy
import hashlib
import importlib.util
import io
import json
import os
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
spec = importlib.util.spec_from_file_location("v3_installer", HERE / "tools/install_new_scripts.py")
candidate = importlib.util.module_from_spec(spec); spec.loader.exec_module(candidate)
import sync_from_studio as sync
import push_repo_to_studio as push
import studio_source_contract as contract
old_spec = importlib.util.spec_from_file_location("legacy_candidate_ports", HERE.parent / "test-installer-candidate.py")
legacy = importlib.util.module_from_spec(old_spec); old_spec.loader.exec_module(legacy)
legacy.candidate = candidate
LUAU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe")
checks = 0

def check(value, message):
    global checks
    checks += 1
    assert value, message

def sha(value):
    return hashlib.sha256(value.encode() if isinstance(value, str) else value).hexdigest()

def execute_native_matrix(path, source, extra):
    old_native = legacy.NATIVE
    text = old_native.replace('Name="Fixture",ClassName=className', 'Name=__TARGET_NAME__,ClassName=className')
    text = text.replace(' local writes,destroys,callbacks=0,0,0', ' local writes,destroys,callbacks=0,0,0\n local created=nil\n local setupFaultUsed=false')
    text = text.replace(' local running=false\n local created=nil', ' local running=false')
    text = text.replace('    if key=="Parent" then\n     local old=row.Parent', '''    if key=="Parent" then
     if created==object and not setupFaultUsed and scenario=="parent-set-before-error" then setupFaultUsed=true;error("controlled before parenting") end
     local old=row.Parent''')
    text = text.replace('    row[key]=value\n    if key=="Enabled"', '''    row[key]=value
    if created==object and key=="Parent" and value~=nil and not setupFaultUsed and scenario=="parent-set-commit-error" then setupFaultUsed=true;error("controlled after parenting") end
    if key=="Enabled"''')
    text = text.replace(' function methods.Destroy(self)destroys+=1;self.Parent=nil end', ''' function methods.Destroy(self)
  destroys+=1
  if self==created and scenario=="cleanup-destroy-error" then error("controlled cleanup error") end
  self.Parent=nil
 end''')
    text = text.replace('  created=node({Name=klass,ClassName=klass', '  created=node({Name=klass,ClassName=klass')
    text = text.replace('  return created\n end}', '''  if scenario=="race-after-allocation" then rows[parent].children={target} end
  return created
 end}''')
    text = text.replace(' services.ScriptEditorService={GetEditorSource=function(_,object)return rows[object].editor end,', ''' services.ScriptEditorService={GetEditorSource=function(_,object)
  if object==created and scenario=="owned-editor-read-error" then error("controlled owned editor read error") end
  return rows[object].editor
 end,''')
    text = text.replace('   if scenario=="update-error" then error("fixture SES error before callback") end', '''   if scenario=="update-error" or scenario=="cleanup-destroy-error" then error("fixture SES error before callback") end
   if scenario=="detached-foreign" then object.Parent=nil;row.Source=__FOREIGN__;row.editor=__FOREIGN__ end
   if scenario=="detached-own" then object.Parent=nil end
   if scenario=="renamed-parent" then rows[parent].Name="ForeignParent" end
   if scenario=="replaced-parent" then
    local replacement=node({Name="ServerScriptService",ClassName="ServerScriptService",id="replacement",Parent=game,children={}})
    parent.Parent=nil;rows[game].children={replacement}
   end''')
    text = text.replace('   if scenario=="commit-then-error" then error("fixture committed then SES error") end', '''   if scenario=="post-source" then row.Source=__FOREIGN__;row.editor=__FOREIGN__ end
   if scenario=="post-attribute" then row.attributes.Foreign=true end
   if scenario=="commit-then-error" then error("fixture committed then SES error") end''')
    text = text.replace(' if scenario=="initial-editor" then', ''' if scenario=="missing-parent" then rows[game].children={} end
 if scenario=="changed-parent-before" then rows[parent].id="foreign-parent" end
 if scenario=="initial-editor" then''')
    text = text.replace('createdEnabled=created and rows[created].Enabled}', 'createdEnabled=created and rows[created].Enabled,createdEditor=created and rows[created].editor}')
    text = text.replace('local createRunners={__CREATES__}', 'local createRunners={__CREATES__}\nlocal lookupRunner=function(game)\n__LOOKUP__\nend')
    text = text.replace('local result=state();check(result.writes==1 and result.callbacks==1 and result.source==__NEW__,"one scoped source write")', '''local result=state();check(result.writes==1 and result.callbacks==1 and result.source==__NEW__,"one scoped source write")
 local presence=lookupRunner(game)
 check(type(presence.missing)=="boolean" and presence.missing==false and presence.parentId=="parent","actual existing Unicode presence")
 local absent=select(1,fresh(klass,"good",true))
 local missing=lookupRunner(absent)
 check(missing.missing==true and missing.parentId=="parent","actual absent Unicode presence")''')
    if extra:
        text = text.replace('print("NATIVE CASES="', r'''
for _,klass in {"ModuleScript","Script","LocalScript"} do
 for _,scenario in {"missing-parent","changed-parent-before","race-after-allocation","renamed-parent","replaced-parent",
  "detached-foreign","detached-own","owned-editor-read-error","parent-set-before-error","parent-set-commit-error",
  "post-source","post-attribute","cleanup-destroy-error"} do
  local g,state=fresh(klass,scenario,true)
  local ok,err=pcall(createRunners[klass],g)
  local result=state()
  check(not ok,"additional create fault rejects: "..scenario)
  check(result.source==__OLD__ and result.editor==__OLD__,"never edit original on additional create fault")
  if scenario=="race-after-allocation" or scenario=="parent-set-before-error" or scenario=="parent-set-commit-error" then
   check(result.created~=nil and result.createdParent==nil and result.destroys==1,"clean precise owned allocation: "..scenario)
  elseif scenario=="detached-foreign" then
   check(result.destroys==0 and result.createdSource==__FOREIGN__ and result.createdParent==nil,"preserve detached foreign Source/editor")
  elseif scenario=="detached-own" then
   check(result.destroys==0 and result.createdParent==nil,"preserve foreign detach even without Source mutation")
  elseif scenario=="owned-editor-read-error" then
   check(result.destroys==0 and result.createdParent==nil,"unknown editor outcome never destroyed")
  elseif scenario=="renamed-parent" or scenario=="replaced-parent" then
   check(result.destroys==0 and result.createdParent~=nil,"foreign parent workflow retained")
  elseif scenario=="post-source" or scenario=="post-attribute" then
   check(result.destroys==0 and result.createdParent~=nil,"foreign postcommit fields retained")
  elseif scenario=="cleanup-destroy-error" then
   check(result.destroys==1 and result.createdParent~=nil,"failed cleanup explicit and object retained")
   check(tostring(err):find("owned cleanup unknown",1,true)~=nil,"cleanup error not masked")
  else check(result.created==nil and result.writes==0,"parent preflight refuses before allocation") end
  cases+=1
 end
end
print("NATIVE CASES="''')
    with patch.object(legacy, "PATH", path), patch.object(legacy, "NEW", source), patch.object(legacy, "NATIVE", text):
        program, updates, creates = legacy.native_fixture()
    program = program.replace('__TARGET_NAME__', push.luau_string(path.rsplit('.', 1)[-1]))
    program = program.replace('__LOOKUP__', candidate.lua_lookup(path))
    normalized = contract.normalize(source)
    digest = hashlib.sha256(normalized.encode()).digest()
    extra_hash = '\nknownHashes[' + push.luau_string(normalized) + ']=' + '"' + ''.join('\\' + f'{v:03}' for v in digest) + '"\n'
    program = program.replace('local trueType=typeof', extra_hash + 'local trueType=typeof')
    with tempfile.TemporaryDirectory(prefix="generic-v3-native-ports-") as directory:
        file = Path(directory) / 'actual-generated.luau'; file.write_bytes(program.encode())
        compiles = []
        for opt in ('-O0', '-O1'):
            result = subprocess.run([str(LUAU.with_name('luau-compile.exe')), '--binary', opt, str(file)], capture_output=True, timeout=30)
            check(result.returncode == 0, 'generated port compile ' + opt + ': ' + result.stderr.decode(errors='replace'))
            compiles.append({'optimization':opt,'pass':True})
        result = subprocess.run([str(LUAU), str(file)], capture_output=True, text=True, encoding='utf8', errors='replace', timeout=30)
        check(result.returncode == 0, 'actual generated port: ' + result.stdout + result.stderr)
    match = re.search(r'NATIVE CASES=(\d+) CHECKS=(\d+)', result.stdout)
    return {'pass':True,'path':path,'sourceBytes':len(source.encode()),'cases':int(match[1]),'checks':int(match[2]),
            'compiles':compiles,'fixtureSHA256':sha(program),'generatedUpdates':{k:sha(v) for k,v in updates.items()},
            'generatedCreates':{k:sha(v) for k,v in creates.items()},'actualLookupSHA256':sha(candidate.lua_lookup(path)),
            'limits':'Actual generated payloads; table services/JSON/known-body hash boundary. No Studio SES or native object certificate.'}

class Client:
    def __init__(self, scenario, path, source):
        self.scenario,self.path,self.new=scenario,path,source
        self.source = source if scenario.startswith('same') or scenario=='large-same' else legacy.OLD
        self.missing = scenario.startswith('create')
        self.calls=[];self.metadataReads=0;self.writes=0;self.closed=False;self.initialized=False
        self.manifest=None;self.chunkResponses=[];self.inputBytes=[]
    def initialize(self):self.initialized=True
    def close(self):self.closed=True
    def metadata(self):
        with patch.object(legacy,'PATH',self.path):value=legacy.record(self.source)
        if self.missing:value['attributes']={};value['tags']=[]
        if self.metadataReads >= 3 and self.scenario in {'final-property','same-final-property'}:value['properties']['Archivable']=False
        if self.metadataReads >= 3 and self.scenario=='final-editor':value['sourceEditorMatches']=False
        return value
    def call(self,tool,args=None):
        args=args or {};self.calls.append(tool)
        if tool=='list_roblox_studios':return json.dumps({'studios':[{'id':'owned-fake','name':f'{candidate.PLACE} (placeId: 131311258779917)'}]})
        if tool=='get_studio_state':return '- Current Studio Mode: Edit\n- Available DataModels: Edit'
        assert tool=='execute_luau' and args['datamodel_type']=='Edit'
        code=args['code'];self.inputBytes.append(len(code.encode()))
        if code==candidate.lua_lookup(self.path):
            malformed={'presence-list':'[]','presence-null':'null','presence-invalid-json':'{oops','presence-empty':'{}',
                       'presence-missing-int':json.dumps({'missing':1,'parentId':'parent'}),
                       'presence-parent-null':json.dumps({'missing':True,'parentId':None}),
                       'presence-parent-empty':json.dumps({'missing':True,'parentId':''}),
                       'presence-extra':json.dumps({'missing':False,'parentId':'parent','source':'no'}),
                       'presence-oversized':'x'*20001}
            if self.scenario in malformed:return malformed[self.scenario]
            if self.scenario=='missing-parent':raise sync.StudioMcpError('Missing installer parent')
            return json.dumps({'missing':self.missing,'parentId':'parent'})
        if code==sync.native_metadata_code(self.path.split('.'),'ModuleScript',sync.EXPECTED_PLACE_ID,sync.EXPECTED_UNIVERSE_ID):
            self.metadataReads+=1
            if self.scenario=='final-source' and self.metadataReads>=3:self.source=legacy.FOREIGN
            return json.dumps(self.metadata())
        names=', '.join(push.luau_string(s) for s in self.path.split('.'))
        normal=contract.normalize(self.source)
        if code==push.READ_META_LUAU % names:
            data=normal.encode();return f'{len(data)}\t{push.djb2(data)}\t{normal.count(chr(10))+1}\tModuleScript'
        chunk=re.search(r'local first, count = (\d+), (\d+)',code)
        if chunk:
            first,count=map(int,chunk.groups());check(count==64,'candidate isolated 64-line chunk')
            assert code==push.READ_CHUNK_LUAU % (names,first,count)
            response='\n'.join(normal.split('\n')[first-1:first-1+count])
            if self.scenario=='chunk-oversized':response='x'*8001
            if self.scenario=='chunk-failure':raise sync.StudioMcpError('controlled chunk read failure')
            if self.scenario=='chunk-truncated':response=response[:-1]
            self.chunkResponses.append(len(response.encode()));return response
        if self.missing:
            assert code==candidate.lua_create(self.path,self.new,'ModuleScript','parent')
            if self.scenario in {'create-race','create-parent-changed','create-editor-error'}:raise sync.StudioMcpError(self.scenario)
        else:
            with patch.object(legacy,'PATH',self.path):baseline=legacy.record(self.source)
            assert code==candidate.lua_update(self.path,self.new,baseline)
        self.writes+=1;self.source=self.new
        if self.scenario=='create-commit-error':raise sync.StudioMcpError('owned candidate committed then transport error')
        return 'ok'

def actual_main_case(scenario, unicode=False, large=False):
    path='ServerScriptService.Prøve 😀' if unicode else legacy.PATH
    file=path.replace('.','/')+'.ModuleScript.lua'
    source=('\n'.join('-- æøå 😀 bounded line '+str(i)+' '+('x'*24) for i in range(1600))+'\nreturn true\n') if large else legacy.NEW
    with tempfile.TemporaryDirectory(prefix='generic-v3-main-') as name:
        root=Path(name);mirror=root/file;mirror.parent.mkdir(parents=True);mirror.write_bytes(source.encode())
        row={'file':file,'studioPath':path,'className':'ModuleScript','sha256':sha(legacy.OLD),'bytes':len(legacy.OLD.encode()),'status':'synced',
             'ownerUnknown':{'receiptIDs':['preserve'],'marker':19},'studioTrailingNewline':True}
        other={'file':'ReplicatedStorage/Other.ModuleScript.lua','studioPath':'ReplicatedStorage.Other','className':'ModuleScript','status':'pending-studio-push',
               'studioSha256Before':'other baseline','properties':{'Archivable':False},'attributes':{'ReceiptId':'keep'},'tags':['keep']}
        data={'items':[row,other],'counts':{'scripts':2,'total':2,'remoteEvents':0},'ownerMeta':'preserve'}
        if scenario=='duplicate-row':data['items'].append(copy.deepcopy(row))
        manifest=root/'studio-sync-manifest.json';manifest.write_bytes((json.dumps(data,ensure_ascii=False)+'\n').encode());before=manifest.read_bytes()
        client=Client(scenario,path,source);client.manifest=manifest
        if scenario=='manifest-temp':(manifest.with_name(manifest.name+'.installer-owned.tmp')).write_bytes(b'foreign temp preserved')
        output=io.StringIO();error=None
        with patch.object(candidate,'ROOT',root),patch.object(candidate,'StudioMcpClient',lambda _:client),patch.object(candidate,'find_mcp_batch',lambda:root/'NO-MCP'),patch.object(candidate.time,'sleep',lambda _:None),patch.object(sys,'argv',['candidate',file,'--overwrite']),redirect_stdout(output):
            try:exitcode=candidate.main()
            except sync.StudioMcpError as caught:exitcode=1;error=str(caught)
        check(mirror.read_bytes()==source.encode(),'input mirror unchanged')
        live=json.loads(manifest.read_bytes());check(next(r for r in live['items'] if r['file']==other['file'])==other,'unrelated queued row exact')
        success=scenario in {'same','overwrite','unicode','create','large-same','large-overwrite'}
        check(exitcode==(0 if success else 1),'truthful actual main result '+scenario+': '+output.getvalue())
        target=next(r for r in live['items'] if r['file']==file)
        if success:
            check(target['ownerUnknown']==row['ownerUnknown'],'unknown target metadata retained')
            check(target['properties']=={'Archivable':True,'LinkedSource':''} and target['sourceEditorMatches'] is True,'fresh final metadata registered')
            check('studioTrailingNewline' not in target,'stale newline flag removed on exact landing')
            check(target['sha256']==sha(source) and target['bytes']==len(source.encode()),'canonical Source registered')
        else:
            check(manifest.read_bytes()==before,'failure preserves manifest bytes')
        if scenario=='duplicate-row':check(not client.initialized and not client.calls,'duplicate targeted row refuses before client')
        else:check(client.initialized and client.closed,'actual main closes independent client')
        if scenario.startswith('presence') or scenario in {'missing-parent','chunk-failure','chunk-oversized','chunk-truncated','create-race','create-parent-changed','create-editor-error'}:
            check(client.writes==0,'prewrite rejection makes no Source mutation')
        if scenario=='final-source':check(client.source==legacy.FOREIGN,'foreign final Source never restored')
        if scenario=='manifest-temp':check((manifest.with_name(manifest.name+'.installer-owned.tmp')).read_bytes()==b'foreign temp preserved','foreign temp retained')
        if large:
            check(len(client.chunkResponses)>40 and all(size<=8000 for size in client.chunkResponses),'large source reads bounded and multi-chunk')
        return {'case':scenario,'pass':True,'unicode':unicode,'sourceBytes':len(source.encode()),'writes':client.writes,'metadataReads':client.metadataReads,
                'chunkResponses':len(client.chunkResponses),'maxResponseBytes':max(client.chunkResponses,default=0),'largestRequestBytes':max(client.inputBytes,default=0),'error':error}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--receipt',type=Path,required=True);args=parser.parse_args()
    assert not args.receipt.exists()
    protected={p:p.read_bytes() for p in [ROOT/'tools/install_new_scripts.py',ROOT/'studio-sync-manifest.json',ROOT/'StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua']}
    original=subprocess.run([sys.executable,'-B',str(ROOT/'tools/tests/test_install_new_scripts.py')],cwd=ROOT,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=60,env={**os.environ,'LUAU_BIN':str(LUAU)})
    check(original.returncode==0,'unchanged production Unicode baseline gate: '+original.stdout+original.stderr)
    check('20 checks passed' in original.stdout,'all original Unicode gates preserved')
    check(candidate.ROOT==HERE and Path(sync.__file__).resolve().parent==HERE/'tools' and Path(push.__file__).resolve().parent==HERE/'tools','production-normal layout uses isolated pinned dependency copies')
    for name in ('sync_from_studio.py','push_repo_to_studio.py','studio_source_contract.py'):
        check((HERE/'tools'/name).read_bytes()==(ROOT/'tools'/name).read_bytes(),'copied helper exact '+name)
    prior=[legacy.main_case(s) for s in ('same-source','overwrite','no-overwrite','empty-attributes','pending','conflict','dry-run','wrong-class','editor-conflict','property-read-error','update-error','callback-concurrent','post-property-drift','manifest-concurrent')]
    matrix=[]
    for path in (legacy.PATH,'ServerScriptService.Prøve "😀"'):
        for source in ('return 1\n','local s = "é æøå 😀"\nreturn s\n','quotes " backslash \\ controls \x00\x01\x08\t\r\n\x7f end'):
            matrix.append(execute_native_matrix(path,source,False))
    matrix.append(execute_native_matrix('ServerScriptService.Prøve "😀"',legacy.NEW,True))
    cases=[actual_main_case(s,unicode=(s=='unicode')) for s in ('same','overwrite','unicode','create','create-race','create-parent-changed','create-editor-error','create-commit-error',
        'presence-list','presence-null','presence-invalid-json','presence-empty','presence-missing-int','presence-parent-null','presence-parent-empty','presence-extra','presence-oversized',
        'missing-parent','final-property','same-final-property','final-editor','final-source','chunk-oversized','chunk-failure','chunk-truncated','manifest-temp','duplicate-row')]
    cases += [actual_main_case('large-same',unicode=True,large=True),actual_main_case('large-overwrite',unicode=True,large=True)]
    check(all(p.read_bytes()==raw for p,raw in protected.items()),'production installer/manifest/owner RoundUI untouched by local ports')
    proof={'schema':'generic-installer-v4-expanded-offline-ports','pass':True,'nativeCalls':0,'productionWrites':0,'manifestWrites':0,'indexWrites':0,
           'candidateSHA256':sha((HERE/'tools/install_new_scripts.py').read_bytes()),'testSHA256':sha(Path(__file__).read_bytes()),
           'pythonChecks':checks,'preservedV2MainCases':prior,'preservedV2Checks':legacy.CHECKS,'additionalMainCases':cases,'generatedGuardMatrices':matrix,
           'unchangedOldUnicodeGate':{'pass':True,'checks':20,'stdout':original.stdout},
           'limits':'Actual main, S13 metadata validation/reader in bounded namespace, local files and generated callbacks. Native/JSON/SHA scheduler boundaries fake. Large read responses bounded64lines/8k; write literal is one larger request with real native transport still pending. No real SES/creation/compile/gameplay certificate.'}
    args.receipt.parent.mkdir(parents=True,exist_ok=True)
    with args.receipt.open('xb') as out:out.write((json.dumps(proof,indent=2,ensure_ascii=False)+'\n').encode())
    print(json.dumps({'pass':True,'pythonChecks':checks,'preservedMainCases':len(prior),'additionalMainCases':len(cases),'generatedGuardCases':sum(v['cases'] for v in matrix),'generatedChecks':sum(v['checks'] for v in matrix),'nativeCalls':0}))

if __name__=='__main__':main()
