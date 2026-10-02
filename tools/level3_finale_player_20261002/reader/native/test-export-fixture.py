"""Bounded export safety tests; isolated synthetic temp repository only."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile

script = Path(__file__).with_name('export-native-five.py').resolve()
compile(script.read_text(), str(script), 'exec')
mapping = {
    'ServerScriptService.Level 3 Systems.Level 3 Mall Manager AI Controller': ('ModuleScript', 'ServerScriptService/Level 3 Systems/Level 3 Mall Manager AI Controller.ModuleScript.lua'),
    'ServerScriptService.Level 3 Systems.Level 3 Objective Controller': ('ModuleScript', 'ServerScriptService/Level 3 Systems/Level 3 Objective Controller.ModuleScript.lua'),
    'ServerScriptService.Level 3 Systems.Level 3 World Builder': ('ModuleScript', 'ServerScriptService/Level 3 Systems/Level 3 World Builder.ModuleScript.lua'),
    'ServerScriptService.Level 3 Systems.Level 3 Worn Party Visual Adapter': ('ModuleScript', 'ServerScriptService/Level 3 Systems/Level 3 Worn Party Visual Adapter.ModuleScript.lua'),
    'StarterPlayer.StarterPlayerScripts.Level 3 Reader Client': ('LocalScript', 'StarterPlayer/StarterPlayerScripts/Level 3 Reader Client.LocalScript.lua'),
}
def sha(v): return hashlib.sha256(v).hexdigest()
with tempfile.TemporaryDirectory(prefix='level3-finale-export-fixture-') as task_dir:
    directory = Path(task_dir)
    verify, repo, checkpoint = directory/'verify', directory/'fixture-repo', directory/'prior'
    verify.mkdir(); repo.mkdir()
    live, manifest, native = directory/'live.json', directory/'manifest.json', directory/'after.rbxl'
    live.write_bytes(b'fixture live metadata'); manifest.write_bytes(b'fixture frozen manifest'); native.write_bytes(b'fixture native bytes')
    payload, changes = [], []
    for index, (path, (class_name, relative)) in enumerate(mapping.items(), 1):
        source = '-- synthetic verified fixture source %d\n' % index
        payload.append({'path':path,'class':class_name,'source':source,'sourceSHA256':sha(source.encode()),'sourceBytes':len(source.encode())})
        changes.append({'path':path,'class':class_name,'afterSHA256':sha(source.encode()),'afterBytes':len(source.encode())})
        dest = repo/relative; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(b'prior fixture source\n')
    receipt = {'schema':'level3-finale-native-five-v1','verified':True,'placeId':131311258779917,'universeId':10559217407,
        'sourceCount':231,'changedSourceCount':5,'unchangedSourceCount':226,'allSourcePathsClassesEqual':True,
        'onlyFiveExpectedSourcesChanged':True,'all231SavedLiveSourceEditorMatch':True,'sourceMaskedNativeCanonicalEqual':True,
        'liveCatalogPath':str(live),'liveCatalogSHA256':sha(live.read_bytes()),'installManifestPath':str(manifest),
        'installManifestSHA256':sha(manifest.read_bytes()),'afterNativePath':str(native),'afterNativeSHA256':sha(native.read_bytes()),'changes':changes}
    receipt_path, payload_path = verify/'native-five-verification.json', verify/'native-five-sources.json'
    receipt_path.write_text(json.dumps(receipt)); payload_path.write_text(json.dumps(payload))
    command=[sys.executable,str(script),'--verification-dir',str(verify),'--repo',str(repo),'--checkpoint',str(checkpoint)]
    result=subprocess.run(command,capture_output=True,text=True)
    assert result.returncode==0 and json.loads(result.stdout)['apply'] is False
    assert not checkpoint.exists() and all((repo/rel).read_bytes()==b'prior fixture source\n' for _,rel in mapping.values())
    bad=dict(receipt,verified=False); receipt_path.write_text(json.dumps(bad))
    assert subprocess.run(command+['--apply'],capture_output=True).returncode!=0
    assert not checkpoint.exists()
    receipt_path.write_text(json.dumps(receipt)); live.write_bytes(b'changed live catalog')
    assert subprocess.run(command+['--apply'],capture_output=True).returncode!=0
    assert not checkpoint.exists(); live.write_bytes(b'fixture live metadata')
    altered=[dict(row) for row in payload]; altered[0]['source']='tampered payload'; payload_path.write_text(json.dumps(altered))
    assert subprocess.run(command+['--apply'],capture_output=True).returncode!=0
    assert not checkpoint.exists(); payload_path.write_text(json.dumps(payload))
    result=subprocess.run(command+['--apply'],capture_output=True,text=True)
    assert result.returncode==0, result.stderr
    assert json.loads(result.stdout)['exported']==5
    for row in payload:
        relative=mapping[row['path']][1]
        assert (repo/relative).read_bytes()==row['source'].encode()
        assert (checkpoint/relative).read_bytes()==b'prior fixture source\n'
    assert subprocess.run(command+['--apply'],capture_output=True).returncode!=0
    print('Export fixture checks passed: read-only default; unverified/catalog/payload failures write no mirrors; exact five apply preserves prior bytes; receipt overwrite blocked.')
