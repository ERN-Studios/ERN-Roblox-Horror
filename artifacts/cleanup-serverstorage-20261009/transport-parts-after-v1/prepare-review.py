"""Read-only completed-transport review; temporary partless copies, never deletion."""
from pathlib import Path
import ast
import copy
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace

sys.dont_write_bytecode = True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
BASE=ROOT/'artifacts/cleanup-serverstorage-20261009'
TOOLS=ROOT/'tools/cleanup_20261009'
sys.path.insert(0,str(ROOT/'tools'));sys.path.insert(0,str(TOOLS))
LUNE=Path(os.environ['TEMP'])/'codex-lune-0.10.5/lune.exe'
DIRS=('diagnostic-archive-before-v7','diagnostic-archive-before-v8','external-storage-archive-v1',
      'external-storage-reopen-v1','retired-authoring-archive-v3')

def sha(raw):return hashlib.sha256(raw).hexdigest()
def save(name,value):
    raw=value if isinstance(value,bytes) else (json.dumps(value,indent=2)+'\n').encode()
    with (HERE/name).open('xb') as stream:assert stream.write(raw)==len(raw)
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
def inventory(directory):
    return {p.relative_to(directory).as_posix():sha(p.read_bytes()) for p in directory.rglob('*') if p.is_file()}
def partless(directory,destination,names):
    assert destination.resolve().is_relative_to(HERE.resolve()) and not destination.exists()
    destination.mkdir()
    for name in names:
        assert Path(name).name==name and not (directory/name).is_symlink()
        shutil.copyfile(directory/name,destination/name)
    assert not list(destination.glob('*-part-*.bin'))

def main():
    assert not (HERE/'candidate.json').exists()
    save('.gitattributes',b'* -text -whitespace\n')
    initial={name:inventory(BASE/name) for name in DIRS}
    tool_names=('verify_diagnostic_folder_archive.luau','diagnostic_folder_archive.luau',
                'verify_diagnostic_folder_references.py','dump_diagnostic_reference_forest.luau',
                'external_storage_archive_reopen.py','external_storage_archive.py','retired_authoring_archive_receiver.py')
    tools_before={name:sha((TOOLS/name).read_bytes()) for name in tool_names}
    groups=[]
    for name in DIRS:
        directory=BASE/name
        transfer=json.loads((directory/'transfer-receipt.json').read_bytes())
        kinds=sorted({p.name.split('-part-')[0] for p in directory.glob('*-part-*.bin')})
        for kind in kinds:
            receipt=transfer if kind=='roundtrip' else transfer[kind]
            filename='facts.json' if kind=='facts' else kind+'.rbxm'
            full=(directory/filename).read_bytes()
            assert sha(full)==receipt['sha256'] and len(full)==receipt['bytes']
            parts=sorted(directory.glob(kind+'-part-*.bin'))
            assert [p.name for p in parts]==[f'{kind}-part-{i:04d}.bin' for i in range(receipt['parts'])]
            rows=[];offset=0
            for part in parts:
                raw=part.read_bytes();assert raw==full[offset:offset+len(raw)]
                rows.append({'path':part.relative_to(ROOT).as_posix(),'bytes':len(raw),'sha256':sha(raw),
                             'fullFile':(directory/filename).relative_to(ROOT).as_posix(),'offset':offset})
                offset+=len(raw)
            assert offset==len(full) and b''.join(p.read_bytes() for p in parts)==full
            groups.append({'directory':name,'kind':kind,'fullFile':(directory/filename).relative_to(ROOT).as_posix(),
                           'fullFileSHA256':sha(full),'bytes':len(full),'receiptFile':(directory/'transfer-receipt.json').relative_to(ROOT).as_posix(),
                           'receiptSHA256':sha((directory/'transfer-receipt.json').read_bytes()),'parts':rows,'status':'afventer test'})
    refs=module('transport_actual_reference_consumer',TOOLS/'verify_diagnostic_folder_references.py')
    s04=module('transport_actual_retired_consumer',TOOLS/'retired_authoring_archive_receiver.py')
    s06=module('transport_actual_external_consumer',TOOLS/'external_storage_archive_reopen.py')
    ports=[]
    temporary=tempfile.TemporaryDirectory(prefix='.transport-consumer-',dir=HERE)
    owned=Path(temporary.name).resolve()
    assert owned.parent==HERE.resolve() and owned.name.startswith('.transport-consumer-')
    try:
        for name in DIRS[:2]:
            directory=BASE/name;clone=owned/name
            partless(directory,clone,('facts.json','native.rbxm','references.rbxm'))
            results=[]
            for lane,archive in (('before',directory),('partless',clone)):
                receipt=HERE/f'{name}-{lane}-folders.json'
                command=[str(LUNE),'run',str(TOOLS/'verify_diagnostic_folder_archive.luau'),str(archive/'facts.json'),str(archive/'native.rbxm'),str(receipt)]
                completed=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=60)
                assert completed.returncode==0,completed.stderr.decode(errors='replace')
                folder=json.loads(receipt.read_bytes())
                reference=refs.verify_archive(LUNE,archive)
                save(f'{name}-{lane}-references.json',reference)
                results.append({'folder':folder,'reference':reference})
            assert results[0]==results[1], 'Actual before/partless consumers differ'
            ports.append({'directory':name,'pass':True,'actualConsumers':['verify_diagnostic_folder_archive.luau','verify_diagnostic_folder_references.verify_archive'],
                          'pairedFullfileResultsExact':True,'rootCount':results[1]['folder']['rootCount'],
                          'serializedReferenceCount':results[1]['reference']['serializedRefCount']})
        directory=BASE/'retired-authoring-archive-v3';clone=owned/'retired-authoring-archive-partless'
        partless(directory,clone,('facts.json','native.rbxm','transfer-receipt.json','capture-result.json'))
        before=s04.Archive(directory,'verify',52,212,'native-reopen-offline-transport.json')
        original_base=s04.BASE
        try:
            s04.BASE=owned
            after=s04.Archive(clone,'verify',52,212,'native-reopen-offline-transport.json')
            assert before.native==after.native and before.context()==after.context()
        finally:s04.BASE=original_base
        ports.append({'directory':'retired-authoring-archive-v3','pass':True,'actualConsumer':'Archive.__init__(phase=verify) + context',
                      'pairedNativeAndValidatedContextExact':True,'nativeBytes':len(after.native),'nativeSHA256':sha(after.native),
                      'historicalNativeReopenPassed':True,'newNativeExecuted':False})
        directory=BASE/'external-storage-archive-v1';clone=owned/'external-storage-archive-v1'
        partless(directory,clone,('facts.json','native.rbxm','capture-completion.json'))
        tree=ast.parse((TOOLS/'external_storage_archive_reopen.py').read_bytes())
        original=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='main')
        def assigns(node,name):return isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in node.targets)
        start=next(i for i,n in enumerate(original.body) if assigns(n,'archive'))
        stop=next(i for i,n in enumerate(original.body) if assigns(n,'context'))
        prefix=copy.deepcopy(original.body[start:stop])
        assert all(isinstance(n,(ast.Assign,ast.Assert)) for n in prefix),'Unreviewed preflight side effects'
        function=ast.FunctionDef(name='actual_readonly_preflight',args=ast.arguments(posonlyargs=[],args=[ast.arg(arg='args')],kwonlyargs=[],kw_defaults=[],defaults=[]),
                                 body=prefix+[ast.Return(value=ast.Tuple(elts=[ast.Name(id=n,ctx=ast.Load()) for n in ('inputs','facts','completion','native')],ctx=ast.Load()))],decorator_list=[])
        namespace=dict(s06.__dict__)
        exec(compile(ast.fix_missing_locations(ast.Module(body=[function],type_ignores=[])),str(TOOLS/'external_storage_archive_reopen.py'),'exec'),namespace)
        before=namespace['actual_readonly_preflight'](SimpleNamespace(archive=directory,dest=owned/'preflight-before-not-created'))
        after=namespace['actual_readonly_preflight'](SimpleNamespace(archive=clone,dest=owned/'preflight-after-not-created'))
        assert before==after and len(after[1]['roots'])==23 and len(after[1]['heldSources'])==12
        save('actual-external-preflight-extracted.py',ast.unparse(function).encode())
        ports.append({'directory':'external-storage-archive-v1','pass':True,'actualConsumer':'external_storage_archive_reopen.main exact input preflight AST statements',
                      'extractionScope':'archive/dest guards through native=inputs; excludes context/server/Studio construction',
                      'pairedInputsAndValidatedFactsExact':True,'heldRoots':23,'heldNodes':after[1]['heldNodeCount'],'heldSources':12,
                      'newNativeExecuted':False,'fullNativeRestorationCertified':False})
    finally:
        assert owned.parent==HERE.resolve() and owned.name.startswith('.transport-consumer-') and owned.is_relative_to(ROOT.resolve())
        temporary.cleanup()
        assert not owned.exists(),'Test-owned temporary copies remain'
    eligible=[];excluded=[]
    for group in groups:
        if group['directory']=='external-storage-reopen-v1':
            group['status']='afventer test'
            group['reason']='Conservatively retained: historical ownership proofs explicitly hash these four chunks; strict native readable reconstruction failed. No completed successful full-reopen consumer port was substituted.'
            excluded.append(group)
        else:
            assert any(port['directory']==group['directory'] and port['pass'] for port in ports)
            group['status']='klar til root review; ingen filer fjernet'
            eligible.append(group)
    assert {name:inventory(BASE/name) for name in DIRS}==initial,'Original archive/evidence changed'
    assert {name:sha((TOOLS/name).read_bytes()) for name in tool_names}==tools_before,'Consumer helper changed during tests'
    candidates=[part for group in eligible for part in group['parts']]
    result={'schema':'completed-transport-parts-review-v1','pass':True,'filesRemoved':0,'nativeCalls':0,'nativeWrites':0,
            'temporaryCopiesCleaned':True,'originalFiveArchiveInventoriesBeforeAfterExact':True,'consumerSourceHashes':tools_before,
            'luneSHA256':sha(LUNE.read_bytes()),'eligibleGroups':eligible,'excludedGroups':excluded,'actualOfflineConsumerPorts':ports,
            'candidateFiles':len(candidates),'candidateBytes':sum(p['bytes'] for p in candidates),'allowedPaths':candidates,
            'rollbackRecipe':['Verify exact root/relative fullfile path inside the five pinned directories; refuse symlinks and traversal.',
                              'Before removal verify fullfile+transfer receipt SHA and each current chunk SHA/size/offset against this manifest; preserve concurrently changed files.',
                              'Recreate any missing owned chunk by seeking its retained verified fullFile to offset and reading bytes; confirm chunk SHA before exclusive write, never overwrite an existing foreign chunk.',
                              'Recheck all fullfiles/receipts/helpers and rerun the same actual partless consumer gates; no runtime/native restoration claim.'],
            'keptFullFiles':'Every native.rbxm/references.rbxm/facts.json/roundtrip.rbxm, facts.json.gz, all receipts, source/proof records remain; raw41MB facts.json remains for v4.',
            'limits':'Preparation/offline completed-archive input-consumer proof only. No authored asset/package duplicate cleanup, gameplay/performance/native recovery/removal certificate.'}
    save('candidate.json',result)
    print(json.dumps({k:result[k] for k in ('pass','filesRemoved','candidateFiles','candidateBytes','temporaryCopiesCleaned')}))

if __name__=='__main__':main()
