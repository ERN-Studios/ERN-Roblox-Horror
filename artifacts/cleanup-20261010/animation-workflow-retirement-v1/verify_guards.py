"""Actual archived/candidate CLI, import, pure-helper and old-cache contracts.

Full Python sources execute against controlled optional/native boundaries. The
original publisher's actual generated Luau executes with cached PublishedAssetId
fixtures. No Studio, Blender, network or upload calls are made.
"""
from pathlib import Path
import argparse
import contextlib
import hashlib
import json
import math
import subprocess
import sys
import tempfile
import types
from unittest.mock import patch

import numpy as np

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
LUAU = Path('C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe')
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


class BoundaryStop(RuntimeError):
    pass


@contextlib.contextmanager
def load_source(file, body, actions, cli=False):
    def stopped(name):
        def operation(*args, **kwargs):
            actions.append(name)
            raise BoundaryStop(name)
        return operation
    sync = types.ModuleType('sync_from_studio')
    sync.StudioMcpClient = stopped('StudioMcpClient')
    sync.find_mcp_batch = stopped('find_mcp_batch')
    sync.select_studio = stopped('select_studio')
    blender = types.ModuleType('blender_mcp_client')
    blender.execute = stopped('blender_execute')
    class Bpy(types.ModuleType):
        def __getattr__(self, name):
            return stopped('bpy.'+name)()
    bpy = Bpy('bpy')
    utils = types.ModuleType('mathutils');utils.Matrix = object
    old_path = list(sys.path)
    namespace = {'__name__': '__main__' if cli else 'guard_contract_module', '__file__': str(ROOT/file)}
    with patch.dict(sys.modules, {'sync_from_studio': sync, 'blender_mcp_client': blender, 'bpy': bpy, 'mathutils': utils}), patch.object(sys, 'argv', [str(ROOT/file), '--v10']):
        try:
            exec(compile(body, str(ROOT/file), 'exec'), namespace)
            yield namespace
        finally:
            sys.path[:] = old_path


def helpers(namespace, path):
    cases = []
    def check(condition, name):
        assert bool(condition), name;cases.append(name)
    if path.endswith('publish_entity_animations.py'):
        check(namespace['luau_table']({'Root': None, 'Child': 'Root'}) == '{["Root"]=nil,["Child"]="Root"}', 'hierarchy root nil and named child')
        check(namespace['luau_table']({}) == '{}', 'empty hierarchy')
    else:
        check(np.array_equal(namespace['matrix'](list(range(16))), np.arange(16).reshape(4,4)), 'row-major matrix data')
        local = namespace['roblox_local']([3,4,5, 1,0,0, 0,1,0, 0,0,1])
        check(np.array_equal(local[:3,3], [3,4,5]) and np.array_equal(local[:3,:3], np.eye(3)), 'Roblox rest translation and basis')
        transform = np.eye(4);transform[:3,3]=[1,2,3]
        converted = namespace['convert_blender'](transform,2)
        check(np.array_equal(converted[:3,3],[2,6,-4]) and np.array_equal(converted[:3,:3],np.eye(3)), 'axis reflection maps scaled Blender translation')
        check(np.allclose(namespace['quaternion_xyzw'](np.eye(3)),[0,0,0,1]), 'identity quaternion')
        rotation = np.array([[0,-1,0],[1,0,0],[0,0,1]],dtype=float)
        check(np.allclose(namespace['quaternion_xyzw'](rotation),[0,0,math.sqrt(.5),math.sqrt(.5)]), 'quarter turn quaternion')
        check(np.allclose(namespace['quaternion_xyzw'](np.diag([1.00001,1.00002,1.00003])),[0,0,0,1]), 'scale stripped before quaternion solve')
        slerp = namespace['slerp_xyzw']
        check(np.allclose(slerp([0,0,0,2],[0,0,0,-3],.5),[0,0,0,1]), 'antipodal normalized shortest path')
        check(np.allclose(slerp([0,0,0,1],[0,0,1,0],.5),[0,0,math.sqrt(.5),math.sqrt(.5)]), 'half turn interpolation')
        check(np.allclose(slerp([0,0,0,1],[0,0,1,0],-2),[0,0,0,1]), 'low alpha clamp')
        check(np.allclose(slerp([0,0,0,1],[0,0,1,0],2),[0,0,1,0]), 'high alpha clamp')
        sample = namespace['blender_sample_code']()
        check('ENT_LOC_Walk_Fwd_Loop_IP_v003' in sample and 'for public_name, blender_name in actions.items()' in sample, 'retained pure Blender sampler generator')
    return cases


def old_cache(code, payload, name, asset_id, negative=False):
    # The service/data boundary is controlled, while the whole original
    # publisher-generated Luau and early-return behavior run unchanged.
    literal = lambda value: json.dumps(value, ensure_ascii=True)
    prefix = '''local checks,uploads,allocations=0,0,0
local function check(ok,label) assert(ok,label) checks+=1 end
local data={name=__NAME_VALUE__}
local published=__ASSET_ID_VALUE__
local existing={}
function existing:GetAttribute(key) check(key=="PublishedAssetId","published cache property") return published end
function existing:Destroy() error("Unexpected existing sequence destruction") end
local folder={Name="MongoTVEntityAnimations"}
function folder:FindFirstChild(key) check(key=="MongoTV_Entity_"..__NAME_VALUE__.."_v10full","exact versioned cache key") return existing end
local storage={}
function storage:FindFirstChild(key) check(key=="MongoTVEntityAnimations","exact root selector") return folder end
local http={}
function http:JSONDecode(raw) check(raw==__PAYLOAD_VALUE__,"actual current input bytes") return data end
function http:JSONEncode(value)
 check(value.name==__NAME_VALUE__ and value.id==__ASSET_ID_VALUE__ and value.reused==true,"durable ID and reuse response") return value.id
end
local asset={}
function asset:CreateAssetAsync(...) uploads+=1 error("Unexpected animation upload") end
local game={}
function game:GetService(key) return assert(({HttpService=http,ServerStorage=storage,AssetService=asset})[key],"unexpected service") end
local Instance={}
function Instance.new(...) allocations+=1 error("Unexpected sequence allocation") end
'''.replace('__NAME_VALUE__', literal(name)).replace('__PAYLOAD_VALUE__', literal(payload)).replace('__ASSET_ID_VALUE__', literal(asset_id))
    if negative:
        prefix = prefix.replace('return published end', 'return nil end')
    body = prefix + '\nlocal ok,result=pcall(function()\n'+code+'\nend)\n'
    if negative:
        body += 'check(not ok and tostring(result):find("Unexpected existing sequence destruction",1,true),"missing cache ID rejects reuse fixture")\n'
    else:
        body += 'check(ok and result=='+literal(asset_id)+',"exact cached asset returned")\n'
    body += 'check(uploads==0 and allocations==0,"no upload or new sequence")\nprint("cache checks "..checks)\n'
    with tempfile.TemporaryDirectory(prefix='retired-animation-cache-') as directory:
        path = Path(directory)/'actual-cache.luau';path.write_text(body,encoding='utf8')
        run = subprocess.run([str(LUAU),str(path)],capture_output=True,timeout=20)
    assert run.returncode == 0, run.stdout.decode(errors='replace')+run.stderr.decode(errors='replace')
    return {'name':name,'assetId':asset_id,'negative':negative,'pass':True,'stdout':run.stdout.decode().strip(),'generatedCodeSHA256':SHA(code.encode()),'nativeCalls':0}


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--receipt',type=Path,required=True);ap.add_argument('--verify-installed',action='store_true');args=ap.parse_args()
    assert not args.receipt.exists()
    proposal_path=HERE/'proposal-v1/proposal.json';proposal=json.loads(proposal_path.read_bytes())
    current = {row['file']:(ROOT/row['file']).read_bytes() for row in proposal['files']}
    retained = {row['file']:(ROOT/row['file']).read_bytes() for row in proposal['retainedInputsAndReceipts']}
    assert all(SHA(current[row['file']])==row['candidateSHA256' if args.verify_installed else 'beforeSHA256'] for row in proposal['files'])
    assert all(SHA(retained[row['file']])==row['rawSHA256'] for row in proposal['retainedInputsAndReceipts'])
    runtime_path=ROOT/'ServerScriptService/Level 1 Systems/EntityAnimation.Script.lua'
    runtime_before=runtime_path.read_bytes()
    cases=[];helper_cases=[];cache=[]
    for row in proposal['files']:
        file=row['file'];before=(HERE/'proposal-v1/before'/file).read_bytes();after=(HERE/'proposal-v1/candidate'/file).read_bytes()
        assert SHA(before)==row['beforeSHA256'] and SHA(after)==row['candidateSHA256']
        for flags in ([],['--help'],['--v10'],['--v3','--force']):
            executable=ROOT/file if args.verify_installed else HERE/'proposal-v1/candidate'/file
            run=subprocess.run([sys.executable,'-B',str(executable),*flags],capture_output=True,timeout=10)
            assert run.returncode==1 and not run.stdout and run.stderr.decode().strip()==proposal['message']
            cases.append({'file':file,'phase':'actualCandidateCLI','flags':flags,'pass':True,'optionalNativeImportsReached':False})
        # Original full CLI hits the guarded optional/native boundary. We do not
        # run these old CLI operations against the owner's real Studio/Blender.
        actions=[]
        try:
            with load_source(file,before,actions,cli=True):
                raise AssertionError('Original authoring route unexpectedly did nothing')
        except BoundaryStop:
            assert actions
        cases.append({'file':file,'phase':'actualOriginalCLIBoundary','pass':True,'reached':actions})
        if row['importWorkflowRetired']:
            for label,body in (('before',before),('candidate',after)):
                actions=[]
                try:
                    with load_source(file,body,actions): raise AssertionError('Unsafe old import unexpectedly did nothing')
                except BoundaryStop:
                    assert label=='before' and actions
                except RuntimeError as error:
                    assert label=='candidate' and str(error)==proposal['message'] and not actions
                cases.append({'file':file,'phase':label+'Import','pass':True,'reached':actions})
        else:
            namespaces={}
            for label,body in (('before',before),('candidate',after)):
                actions=[]
                with load_source(file,body,actions) as namespace:
                    assert not actions
                    helper_cases.append({'file':file,'phase':label,'pass':True,'cases':helpers(namespace,file)})
                    namespaces[label]=namespace
                    for name in row['retiredCallableEntries']:
                        actions.clear()  # Imported boundary closures capture this exact list.
                        call_args=['{}'] if name=='publish_code' else []
                        try:
                            namespace[name](*call_args)
                            if label=='candidate':raise AssertionError('Retired entry unexpectedly returned')
                        except BoundaryStop:
                            assert label=='before' and actions
                        except RuntimeError as error:
                            assert label=='candidate' and str(error)==proposal['message']
                        if label=='candidate': assert not actions
                        cases.append({'file':file,'phase':label+'Callable','entry':name,'pass':True,'reached':list(actions)})
            if file.endswith('publish_entity_animations.py'):
                original=namespaces['before'];published=json.loads((ROOT/'assets/animations/entity/published-assets-v10-full.json').read_bytes())
                for name in original['ACTION_FILES']:
                    payload=(ROOT/'assets/animations/entity/keyframes_v3'/name).read_text(encoding='utf8')
                    data=json.loads(payload);asset_id=published[data['name']]['id'];code=original['publish_code'](payload)
                    cache.append(old_cache(code,payload,data['name'],asset_id))
                item=cache[0];payload=(ROOT/'assets/animations/entity/keyframes_v3'/original['ACTION_FILES'][0]).read_text(encoding='utf8')
                cache.append(old_cache(original['publish_code'](payload),payload,item['name'],item['assetId'],negative=True))
                runtime=runtime_before.decode('utf8')
                assert all('"'+str(item['id'])+'"' in runtime for item in published.values()) and len(published)==8
    assert all((ROOT/file).read_bytes()==raw for file,raw in current.items())
    assert all((ROOT/file).read_bytes()==raw for file,raw in retained.items())
    assert runtime_path.read_bytes()==runtime_before
    value={'schema':'mongotv-retired-animation-workflow-actual-ports-v1','pass':True,'cases':cases,'helperCases':helper_cases,'cacheCases':cache,
           'candidateCLICases':16,'pureHelperCasesPerVersion':sum(len(row['cases']) for row in helper_cases if row['phase']=='before'),
           'actualOriginalGeneratedCacheIds':8,'missingCacheIdNegative':True,'retainedInputReceiptFiles':len(retained),
           'proposalSHA256':SHA(proposal_path.read_bytes()),'testSHA256':SHA(Path(__file__).read_bytes()),
           'verifiedInstalled':args.verify_installed,'runtimeIdFileSHA256':SHA(runtime_before),'runtimeIdFileUnchanged':True,
           'nativeCalls':0,'networkCalls':0,'assetUploads':0,'productionWrites':0,'runtimeWrites':0,'toolWrites':0,'manifestWrites':0,'indexWrites':0,
           'limits':'Whole archived/candidate Python CLI/import/retired callables and unchanged pure-helper behaviors; whole original generated Luau early cache return with actual input bytes and8 versioned published-ID fixtures. Optional Blender/Studio services and cached metadata are controlled boundaries; no current native cache-child/data/reference proof, actual upload or gameplay playback is certified. Huge roots are not removed and need independent archive/absence/recovery gates. Historical deprecated bpy imports were unsafe authoring initializers and intentionally now refuse.'}
    args.receipt.parent.mkdir(parents=True,exist_ok=True)
    with args.receipt.open('xb') as stream:stream.write((json.dumps(value,indent=2)+'\n').encode())
    print(json.dumps({'pass':True,'cliCases':16,'cases':len(cases),'helpersPerVersion':value['pureHelperCasesPerVersion'],'cacheIds':8,'cacheNegative':1,'retained':len(retained),'nativeCalls':0}))


if __name__=='__main__': main()
