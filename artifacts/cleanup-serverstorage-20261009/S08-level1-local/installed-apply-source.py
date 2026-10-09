from pathlib import Path
import ast, hashlib, json, os, subprocess, sys, tempfile

ROOT = Path('G:/Roblox/MongoTV')
PROOF = ROOT / 'artifacts/cleanup-serverstorage-20261009/S08-level1-local'
CHECKPOINT = ROOT / '.git/mongotv-cleanup-20261009/s08-application-before'
RUNNER = ROOT / 'tools/cleanup_20261009/level1_retirement_contracts.py'

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def inventory(path):
    return {p.relative_to(path).as_posix():sha(p.read_bytes()) for p in path.rglob('*') if p.is_file()}

def save_new(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        assert stream.write(raw) == len(raw)
    assert path.read_bytes() == raw

def replace_exact(path, before, after):
    assert path.read_bytes() == before, 'Concurrent target edit: ' + str(path)
    fd, name = tempfile.mkstemp(prefix='.mongotv-s08-', dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, 'wb') as stream:
            assert stream.write(after) == len(after)
        assert temporary.read_bytes() == after
        assert path.read_bytes() == before, 'Concurrent target edit before atomic replace'
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)

assert not CHECKPOINT.exists() and not (PROOF/'installed-result.json').exists()
manifest_raw = (PROOF/'manifest.json').read_bytes()
manifest = json.loads(manifest_raw)
paired_raw = (PROOF/'current-package-port-v2/paired-result.json').read_bytes()
paired = json.loads(paired_raw)
assert paired['pass'] and paired['equalOutputs'] == 6 and paired['legacyNegativeGates'] == 7
assert paired['proposalManifestSHA256'] == sha(manifest_raw)
assert sha(RUNNER.read_bytes()) == paired['contractsRunnerSHA256']
rows = manifest['sourceFiles']
assert len(rows) == 7 and len({r['path'] for r in rows}) == 7
before, after = {}, {}
for row in rows:
    name = row['path']
    path = ROOT/name
    assert path.resolve().is_relative_to(ROOT) and not path.is_symlink()
    before[name] = path.read_bytes()
    after[name] = (ROOT/row['candidatePath']).read_bytes()
    assert before[name] == (ROOT/row['beforePath']).read_bytes()
    assert sha(before[name]) == row['beforeSHA256'] and sha(after[name]) == row['candidateSHA256']
    if name.endswith('.py'):
        ast.parse(before[name].decode(), filename=name)
        ast.parse(after[name].decode(), filename=name)
assets_before = inventory(ROOT/'assets/level1')
dependencies_before = {p.relative_to(ROOT).as_posix():sha(p.read_bytes()) for p in (ROOT/'tools/level1_blender').glob('*.py') if p.relative_to(ROOT).as_posix() not in before}
head = subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT).decode().strip()
assert not subprocess.check_output(['git','diff','--name-only','--cached'], cwd=ROOT).strip()
CHECKPOINT.mkdir(parents=True)
save_new(CHECKPOINT/'manifest.json', manifest_raw)
save_new(CHECKPOINT/'asset-hashes.json', (json.dumps(assets_before, indent=2)+'\n').encode())
save_new(CHECKPOINT/'dependencies.json', (json.dumps(dependencies_before, indent=2)+'\n').encode())
for name, raw in before.items():
    save_new(CHECKPOINT/'sources'/name, raw)

def guard(changed):
    assert (PROOF/'manifest.json').read_bytes() == manifest_raw
    assert (PROOF/'current-package-port-v2/paired-result.json').read_bytes() == paired_raw
    assert sha(RUNNER.read_bytes()) == paired['contractsRunnerSHA256']
    assert all((ROOT/name).read_bytes() == (after[name] if name in changed else raw) for name,raw in before.items())
    assert all(sha((ROOT/name).read_bytes()) == value for name,value in dependencies_before.items())

changed = []
try:
    for name in before:
        guard(changed)
        replace_exact(ROOT/name, before[name], after[name])
        changed.append(name)
    guard(changed)
    assert inventory(ROOT/'assets/level1') == assets_before
    command = [sys.executable,'-B',str(RUNNER),'--proposal',str(PROOF),'--dest',str(PROOF/'installed-package-port-v1'),'--package-only','--verify-installed']
    subprocess.run(command, cwd=ROOT, check=True)
    installed = json.loads((PROOF/'installed-package-port-v1/paired-result.json').read_bytes())
    assert installed['pass'] and installed['equalOutputs'] == 6 and installed['legacyNegativeGates'] == 7
    guard(changed)
    assert inventory(ROOT/'assets/level1') == assets_before
    receipt = {'schema':'level1-legacy-workflow-installed-v1','pass':True,'filesChanged':7,'nativeWrites':0,'networkCalls':0,
        'headAtStart':head,'rawBytesBefore':sum(map(len,before.values())),'rawBytesAfter':sum(map(len,after.values())),
        'allLevel1AssetFilesUnchanged':len(assets_before),'otherLevel1PythonFilesUnchanged':len(dependencies_before),
        'installedPort':'installed-package-port-v1/paired-result.json','installedPortPass':True,
        'scope':'Retired legacy standalone/public selectors. Shared V2/elevator helpers and all assets/receipts preserved. Fresh V2 generation, native old-kit removal and gameplay gates remain pending.',
        'sources':rows}
    save_new(PROOF/'installed-result.json', (json.dumps(receipt,indent=2)+'\n').encode())
    print(json.dumps({k:receipt[k] for k in ('pass','filesChanged','rawBytesBefore','rawBytesAfter','allLevel1AssetFilesUnchanged')}))
except BaseException as error:
    restored, conflicts = [], []
    for name in reversed(changed):
        try:
            if (ROOT/name).read_bytes() != after[name]:
                conflicts.append(name)
                continue
            replace_exact(ROOT/name, after[name], before[name])
            restored.append(name)
        except BaseException as recovery:
            error.add_note('Scoped rollback: '+name+': '+str(recovery))
    save_new(PROOF/'installed-rollback.json', (json.dumps({'pass':False,'primaryError':str(error),'restored':restored,'preservedConcurrentFiles':conflicts,'notes':getattr(error,'__notes__',[])},indent=2)+'\n').encode())
    raise
