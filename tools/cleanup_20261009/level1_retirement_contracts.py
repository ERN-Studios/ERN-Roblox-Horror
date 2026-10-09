"""S08 paired actual-tool authoring port in disposable private workspaces.

Keeps canonical files/assets byte-identical. No network, uploads or Studio.
Headless runs are actual Blender geometry/export and native/FBX QA, not gameplay.
"""
from pathlib import Path
import argparse
import ast
import base64
import contextlib
import difflib
import hashlib
import importlib.util
import io
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import types

ROOT=Path(__file__).resolve().parents[2]
ASSET_KITS=('blender','blender-v2','elevator-inset-20261004')

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def inventory(path):
    return {p.relative_to(path).as_posix():sha(p.read_bytes()) for p in path.rglob('*') if p.is_file()}

def mesh_geometry(blob):
    """Exact f32 bytes + pools + oriented corner tuples; only index/order remap.

    No value rounding/tolerance, winding reversal, pool deduplication or hash/
    receipt substitution. Cyclic corner starts describe the same oriented face.
    """
    nv,nn,nu,nf=struct.unpack_from('<4I',blob)
    assert nv<=60000 and nf<=20000
    assert len(blob)==16+12*(nv+nn)+8*nu+36*nf
    offset=16
    pools=[]
    for count,width in ((nv,12),(nn,12),(nu,8)):
        pools.append([blob[offset+i*width:offset+(i+1)*width] for i in range(count)])
        offset+=count*width
    faces=[]
    for f in range(nf):
        indexes=struct.unpack_from('<9I',blob,offset+f*36)
        corners=[]
        for i in (0,3,6):
            v,n,u=indexes[i:i+3]
            assert v<nv and n<nn and u<nu
            corners.append(pools[0][v]+pools[1][n]+pools[2][u])
        faces.append(min(b''.join(corners[i:]+corners[:i]) for i in range(3)))
    raw=struct.pack('<4I',nv,nn,nu,nf)+b''.join(b''.join(sorted(pool)) for pool in pools)+b''.join(sorted(faces))
    return sha(raw)

def geometry_guard_fixtures():
    vertices=[struct.pack('<3f',*v) for v in ((0,0,0),(1,0,0),(0,1,0))]
    normal=struct.pack('<3f',0,0,1)
    uvs=[struct.pack('<2f',*v) for v in ((0,0),(1,0),(0,1))]
    def blob(vs,us,indices):
        return struct.pack('<4I',3,1,3,1)+b''.join(vs)+normal+b''.join(us)+struct.pack('<9I',*indices)
    first=blob(vertices,uvs,(0,0,0,1,0,1,2,0,2))
    permuted=blob(vertices[::-1],uvs[::-1],(2,0,2,1,0,1,0,0,0))
    assert mesh_geometry(first)==mesh_geometry(permuted),'Equivalent index remap rejected'
    assert mesh_geometry(first)==mesh_geometry(blob(vertices,uvs,(1,0,1,2,0,2,0,0,0))),'Cyclic oriented corner start rejected'
    assert mesh_geometry(first)!=mesh_geometry(blob(vertices,uvs,(0,0,0,2,0,2,1,0,1))),'Winding reversal hidden'
    changed=vertices.copy()
    changed[1]=struct.pack('<3f',1.000001,0,0)
    assert mesh_geometry(first)!=mesh_geometry(blob(changed,uvs,(0,0,0,1,0,1,2,0,2))),'Coordinate delta hidden'
    assert mesh_geometry(first)!=mesh_geometry(blob(vertices,uvs,(0,0,1,1,0,0,2,0,2))),'UV binding delta hidden'
    duplicate=vertices.copy()
    duplicate[1]=vertices[0]
    assert mesh_geometry(first)!=mesh_geometry(blob(duplicate,uvs,(0,0,0,1,0,1,2,0,2))),'Pool multiplicity hidden'
    return 6

def export_geometry(export):
    data=json.loads((export/'manifest.json').read_bytes())
    for chunk in data['chunks']:
        wire=(export/'chunks'/('c%05d.b64'%chunk['id'])).read_bytes().strip()
        blob=base64.b64decode(wire,validate=True)
        assert sha(wire)==chunk['wireSha256'] and sha(blob)==chunk['sha256']
        # Original wire hashes remain untouched on disk and in the raw inventory.
        chunk['exactGeometrySHA256']=mesh_geometry(blob)
        del chunk['wireSha256']
        del chunk['sha256']
    return data

def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def call_main(module,args):
    prior=sys.argv
    output=io.StringIO()
    try:
        sys.argv=[module.__file__,*map(str,args)]
        with contextlib.redirect_stdout(output):
            module.main()
    finally:
        sys.argv=prior
    return output.getvalue()

def rejected(module,args):
    try:
        call_main(module,args)
    except (AssertionError,SystemExit) as error:
        assert not isinstance(error,SystemExit) or error.code!=0
        return type(error).__name__+': '+str(error)
    raise AssertionError('Legacy target unexpectedly accepted')

def fixtures(workspace,phase,proof,compiler):
    def forbidden(*_args,**_kwargs):
        raise AssertionError('Forbidden Studio/network boundary used')
    fake=types.ModuleType('sync_from_studio')
    fake.StudioMcpClient=fake.find_mcp_batch=fake.select_studio=forbidden
    sys.modules['sync_from_studio']=fake
    import http.server
    previous_server=http.server.ThreadingHTTPServer
    http.server.ThreadingHTTPServer=forbidden
    try:
        source=workspace/'tools/level1_blender'
        importer=load('S08_import_'+phase,source/'import_assets.py')
        importer.ASSETS=workspace/'assets/level1/blender-v2'
        importer.EXPORT=importer.ASSETS/'export'
        importer.RESULTS=importer.EXPORT/'roblox-assets.json'
        data,records=importer.payload()
        assert data['version']==2 and len(data['rooms'])==42 and len(data['components'])==41
        assert all(chunk['assetId'] for chunk in data['chunks'])
        assert all(value for material in data['materials'].values() for value in material['robloxMaps'].values())
        v2=importer.write_installer(data,'Level1BlenderKitV2')
        assert 'kit.Name = "Level1BlenderKitV2"' in v2 and 'FindFirstChild("Level1BlenderKit")' not in v2
        (proof/'V2-payload.json').write_text(json.dumps(data,sort_keys=True,indent=2)+'\n')
        (proof/'V2-installer.luau').write_text(v2,encoding='utf8')
        # Exercise actual matching old wire-receipt fallback with a missing V2 entry.
        prior_records=importer.RESULTS.read_bytes()
        old=json.loads((workspace/'assets/level1/blender/export/roblox-assets.json').read_bytes())
        by_hash={r['wireSha256']:r for r in old.values()}
        reused=next(c for c in data['chunks'] if c['wireSha256'] in by_hash)
        missing={k:v for k,v in records.items() if k!=str(reused['id'])}
        importer.RESULTS.write_text(json.dumps(missing))
        restored,restored_records=importer.payload()
        expected=by_hash[reused['wireSha256']]
        assert restored_records[str(reused['id'])]['assetId']==expected['assetId']
        assert restored_records[str(reused['id'])]['reusedFrom']=='level1-blender-20261002'
        importer.RESULTS.write_bytes(prior_records)
        # Bad texture receipt must not authorize an asset merely from the filename.
        published_path=importer.ASSETS/'textures/published.json'
        published_raw=published_path.read_bytes()
        published=json.loads(published_raw)
        assert not (importer.ASSETS/'textures/roblox-assets.json').exists()
        first=next(iter(published))
        published[first]['sha256']='0'*64
        published_path.write_text(json.dumps(published))
        invalid,_=importer.payload()
        assert any(material['robloxMaps'].get(key) is None for material in invalid['materials'].values() for key,name in material['maps'].items() if name==first)
        published_path.write_bytes(published_raw)
        elevator=load('S08_elevator_'+phase,source/'import_elevator_inset.py')
        elevator_data,_=elevator.base.payload()
        assert elevator_data['build']=='level1-elevator-inset-20261004'
        code=elevator.installer(elevator_data)
        assert 'kit.Name = "Level1ElevatorInsetKit"' in code and 'FindFirstChild("Level1BlenderKit")' not in code
        assert 'Concurrent elevator import: no overwrite' in code
        (proof/'elevator-payload.json').write_text(json.dumps(elevator_data,sort_keys=True,indent=2)+'\n')
        (proof/'elevator-installer.luau').write_text(code,encoding='utf8')
        for path in (proof/'V2-installer.luau',proof/'elevator-installer.luau'):
            for optimization in ('-O0','-O1'):
                subprocess.run([str(compiler),'--null',optimization,str(path)],check=True,capture_output=True)
        checker=load('S08_checker_'+phase,source/'check_assets.py')
        checker_args=[] if phase=='candidate' else ['--assets',workspace/'assets/level1/blender-v2']
        check_output=call_main(checker,checker_args)
        publisher=load('S08_publish_'+phase,source/'publish_textures.py')
        publish_output=call_main(publisher,[] if phase=='candidate' else ['--assets',workspace/'assets/level1/blender-v2'])
        elevator_publish=call_main(publisher,['--assets',workspace/'assets/level1/elevator-inset-20261004'])
        assert 'already uploaded' in publish_output and 'already uploaded' in elevator_publish
        cli_importer=load('S08_cli_import_'+phase,source/'import_assets.py')
        call_main(cli_importer,[] if phase=='candidate' else ['--assets',workspace/'assets/level1/blender-v2','--kit-name','Level1BlenderKitV2'])
        assert (workspace/'assets/level1/blender-v2/export/install.luau').read_text()==v2
        exporter=load('S08_export_'+phase,workspace/'tools/export_level1_facelift_verified.py')
        export_output=call_main(exporter,[] if phase=='candidate' else ['--revision-v2'])
        assert len(exporter.SCRIPTS)==7
        assert 'resolve({"ServerStorage","Level1BlenderKitV2"})' in exporter.KIT
        generated=exporter.COMMON+exporter.KIT+'\nreturn true\n'
        (proof/'V2-exporter.luau').write_text(generated,encoding='utf8')
        subprocess.run([str(compiler),'--null','-O0',str(proof/'V2-exporter.luau')],check=True,capture_output=True)
        legacy_refusals={}
        if phase=='candidate':
            # Compatibility alias must not append duplicate scripts or suffix V2 twice.
            scripts=exporter.SCRIPTS.copy()
            kit=exporter.KIT
            call_main(exporter,['--revision-v2'])
            assert exporter.SCRIPTS==scripts and exporter.KIT==kit
            asset_before=inventory(workspace/'assets')
            for name,module,args in (
                ('importLegacyName',cli_importer,['--kit-name','Level1BlenderKit']),
                ('importLegacyPath',cli_importer,['--assets',workspace/'assets/level1/blender']),
                ('checkLegacyPath',checker,['--assets',workspace/'assets/level1/blender']),
                ('publishLegacyPath',publisher,['--assets',workspace/'assets/level1/blender']),
            ):
                legacy_refusals[name]=rejected(module,args)
            try:
                importer.write_installer(data,'Level1BlenderKit')
            except AssertionError:
                legacy_refusals['helperLegacyName']='AssertionError before output'
            else:
                raise AssertionError('Legacy helper target accepted')
            assert inventory(workspace/'assets')==asset_before,'Rejected CLI/helper wrote assets or receipts'
        record={'actualV2Assets':{'meshes':len(data['chunks']),'rooms':len(data['rooms']),'components':len(data['components'])},
                'cachedPublish':{'V2':publish_output.strip(),'elevator':elevator_publish.strip()},
                'reusedReceipt':{'chunkId':reused['id'],'assetId':expected['assetId'],'wireSha256':reused['wireSha256']},
                'badTextureReceiptRejected':True,'legacyRefusals':legacy_refusals,'checkAssetsOutput':check_output.strip(),
                'exporterScripts':exporter.SCRIPTS,'exporterOutput':export_output.strip(),'networkCalls':0,'StudioCalls':0,
                'generatedCompile':'O0/O1 V2+elevator, O0 exporter PASS'}
        (proof/'contracts.json').write_text(json.dumps(record,indent=2)+'\n')
        return record
    finally:
        http.server.ThreadingHTTPServer=previous_server

def command(args,log):
    env=os.environ.copy()
    env.update(PYTHONHASHSEED='0',PYTHONNOUSERSITE='1')
    for name in ('PYTHONPATH','PYTHONHOME','PYTHONSTARTUP'):
        env.pop(name,None)
    result=subprocess.run(list(map(str,args)),capture_output=True,env=env)
    log.write_bytes(result.stdout+result.stderr)
    assert result.returncode==0,f'Command failed ({result.returncode}): {log}'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proposal',type=Path,required=True)
    parser.add_argument('--dest',type=Path,required=True)
    parser.add_argument('--package-only',action='store_true',help='Current immutable-package selector/import/publish/QA port; fresh mesh regeneration is separate')
    parser.add_argument('--verify-installed',action='store_true',help='Require canonical scoped files to match reviewed candidate hashes')
    args=parser.parse_args()
    proposal=args.proposal.resolve()
    dest=args.dest.resolve()
    assert proposal.is_relative_to(ROOT) and dest.is_relative_to(ROOT) and not dest.exists()
    manifest_raw=(proposal/'manifest.json').read_bytes()
    manifest=json.loads(manifest_raw)
    rows=manifest['sourceFiles']
    assert len(rows)==7 and manifest['productionFilesModified'] is False
    sources={r['path']:(ROOT/r['path']).read_bytes() for r in rows}
    expected_source='candidateSHA256' if args.verify_installed else 'beforeSHA256'
    assert all(sha(sources[r['path']])==r[expected_source] for r in rows),'Fresh source differs from pinned phase; no tests begun'
    canonical_assets={kit:inventory(ROOT/'assets/level1'/kit) for kit in ASSET_KITS}
    dependencies={p.relative_to(ROOT).as_posix():p.read_bytes() for p in (ROOT/'tools/level1_blender').glob('*.py')}
    compiler=Path('C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe')
    blender=Path('D:/Blender/blender.exe')
    helper=Path(__file__).with_name('level1_retirement_headless.py')
    helper_raw=helper.read_bytes()
    runner_raw=Path(__file__).read_bytes()
    geometry_cases=geometry_guard_fixtures()
    dest.mkdir(parents=True)
    (dest/'headless-source.py').write_bytes(helper_raw)
    (dest/'contracts-source.py').write_bytes(runner_raw)
    phase_records={}
    phases=('before','candidate') if args.package_only else ('before','control-before','candidate')
    for phase in phases:
        proof=dest/phase
        proof.mkdir()
        print('S08 phase '+phase+': private actual-tool fixtures and headless authoring/QA',flush=True)
        with tempfile.TemporaryDirectory(prefix='MongoTV-S08-') as temporary:
            workspace=Path(temporary)
            (workspace/'S08_PRIVATE_WORKSPACE').touch()
            tools=workspace/'tools/level1_blender'
            tools.mkdir(parents=True)
            for relative,raw in dependencies.items():
                (workspace/relative).write_bytes(raw)
            for row in rows:
                input_kind='candidate' if phase=='candidate' else 'before'
                input_path=ROOT/row[input_kind+'Path']
                raw=input_path.read_bytes()
                assert sha(raw)==row[input_kind+'SHA256']
                target=workspace/row['path']
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(raw)
                if target.suffix=='.py':
                    ast.parse(raw.decode(),filename=str(target))
            for kit in ASSET_KITS:
                shutil.copytree(ROOT/'assets/level1'/kit,workspace/'assets/level1'/kit)
            record=fixtures(workspace,phase,proof,compiler)
            if not args.package_only:
                command([blender,'-b','--factory-startup','-t','2','--python-use-system-env','--python-exit-code','1','-P',helper,'--',workspace],proof/'headless-kernels.log')
                shutil.copyfile(workspace/'headless-kernels.json',proof/'headless-kernels.json')
                generated={kit:inventory(workspace/'generated'/kit/'export') for kit in ASSET_KITS[1:]}
                (proof/'generated-export-sha256.json').write_text(json.dumps(generated,indent=2)+'\n')
                geometry={kit:export_geometry(workspace/'generated'/kit/'export') for kit in ASSET_KITS[1:]}
                (proof/'generated-exact-geometry.json').write_text(json.dumps(geometry,sort_keys=True,indent=2)+'\n')
            qa=[blender,'-b',workspace/'assets/level1/blender-v2/Level1_ModularKit.blend','-t','2','--python-exit-code','1','-P',tools/'verify_native.py']
            if phase!='candidate':
                qa.extend(['--','--assets',workspace/'assets/level1/blender-v2'])
            command(qa,proof/'V2-native-fbx-QA.log')
            shutil.copyfile(workspace/'assets/level1/blender-v2/native-verification.json',proof/'V2-native-verification.json')
            if phase=='candidate':
                assets_before=inventory(workspace/'assets')
                refusal=subprocess.run([str(blender),'-b','--factory-startup','-t','2','--python-exit-code','1','-P',str(tools/'build.py')],capture_output=True)
                (proof/'legacy-build-refusal.log').write_bytes(refusal.stdout+refusal.stderr)
                assert refusal.returncode!=0 and b'Legacy Level1BlenderKit build retired' in refusal.stdout+refusal.stderr
                refusal=subprocess.run([str(blender),'-b','--factory-startup','-t','2','--python-exit-code','1','-P',str(tools/'verify_native.py'),'--','--assets',str(workspace/'assets/level1/blender')],capture_output=True)
                (proof/'legacy-native-QA-refusal.log').write_bytes(refusal.stdout+refusal.stderr)
                assert refusal.returncode!=0 and b'Legacy Level1BlenderKit QA retired' in refusal.stdout+refusal.stderr
                assert inventory(workspace/'assets')==assets_before,'Retired Blender invocation wrote private assets'
            phase_records[phase]=record
        assert all((ROOT/path).read_bytes()==raw for path,raw in sources.items()),'Concurrent scoped source change; do not install'
        assert all(inventory(ROOT/'assets/level1'/kit)==rows for kit,rows in canonical_assets.items()),'Canonical asset/receipt drift'
    equal_names=('V2-payload.json','V2-installer.luau','elevator-payload.json','elevator-installer.luau','V2-exporter.luau','V2-native-verification.json')
    if not args.package_only:
        equal_names+=('headless-kernels.json','generated-exact-geometry.json')
    for other in phases[1:]:
        for name in equal_names:
            assert (dest/'before'/name).read_bytes()==(dest/other/name).read_bytes(),'Active output mismatch: '+other+'/'+name
    assert all((ROOT/path).read_bytes()==raw for path,raw in dependencies.items()),'Concurrent shared helper changed'
    assert helper.read_bytes()==helper_raw and Path(__file__).read_bytes()==runner_raw and (proposal/'manifest.json').read_bytes()==manifest_raw,'Concurrent proof input changed'
    raw_deltas={}
    if not args.package_only:
        raw_generated={phase:json.loads((dest/phase/'generated-export-sha256.json').read_bytes()) for phase in phases}
        raw_deltas={phase:{kit:[path for path,h in raw_generated['before'][kit].items() if raw_generated[phase][kit].get(path)!=h] for kit in ASSET_KITS[1:]} for phase in phases[1:]}
    receipt={'schema':'level1-legacy-workflow-paired-contracts-v1','pass':True,'productionFilesModified':False,
             'nativeStudioCalls':0,'networkCalls':0,'portScope':'Current immutable package selectors/import/publish/export/native-FBX QA only' if args.package_only else 'Paired authoring generation and package contracts',
             'authoringKernel':'Separate v1/v2/v3 actual kernels completed; full fresh V2 exact generation gate remains pending baseline LeverHandle triangulation variability' if args.package_only else 'Actual headless Blender V2+elevator component/room/assembly/UV+chunk export before/after exact',
             'nativeFileQA':'Actual V2 .blend and fresh FBX import before/after exact verification record',
             'retainedCanonicalAssetTreesUnchanged':True,'retainedSharedHelpersUnchanged':True,
             'equalOutputs':len(equal_names),'legacyNegativeGates':7,'phaseRecords':phase_records,
             'sameSourceControl':'Historical paired-port-v2/v3 same-before control retained; fresh V2 byte/triangle exactness still pending' if args.package_only else 'before input repeated with fixed embedded Python hash seed0; existing7outputs plus exact geometry contract compared',
             'rawGeneratedWireDifferences':raw_deltas,'geometryNormalization':'Exact f32 pool multiplicities and oriented corner tuples; index/triangle order only, no numerical tolerance',
             'geometryGuardFixtures':geometry_cases,'contractsRunnerSHA256':sha(runner_raw),
             'proposalManifestSHA256':sha(manifest_raw),'compilerSHA256':sha(compiler.read_bytes()),
             'headlessProbeSHA256':sha(helper_raw),'limits':'No render regeneration, full authoring main invocation, Studio gameplay, uploads, live import/export, multiplayer/streaming or performance gain certified.'}
    (dest/'paired-result.json').write_text(json.dumps(receipt,indent=2)+'\n')
    patch=[]
    for row in manifest['sourceFiles']:
        before=(ROOT/row['beforePath']).read_bytes().decode().splitlines(keepends=True)
        after=(ROOT/row['candidatePath']).read_bytes().decode().splitlines(keepends=True)
        patch.extend(difflib.unified_diff(before,after,fromfile='a/'+row['path'],tofile='b/'+row['path']))
    (dest/'proposal.patch').write_text(''.join(patch),encoding='utf8')
    print(json.dumps({'pass':True,'productionFilesModified':False,'equalOutputs':len(equal_names),'legacyNegativeGates':7,'StudioCalls':0,'packageOnly':args.package_only}),flush=True)

if __name__=='__main__':
    main()
