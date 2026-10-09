"""Archive exactly the owner's retired R1/R2/R3/R3B local authoring closure.

The active R4 authoring port runs before and after. No Studio operations. On
failure, exclusively restore our removed files; preserve concurrent new files.
"""
from pathlib import Path
from datetime import datetime, timezone
import ast
import hashlib
import json
import subprocess
import sys
from verify_lobby_authoring_equivalence import verify

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'tools/lobby_reimagined'
DEST = ROOT / 'artifacts/cleanup-serverstorage-20261009/retired-lobby-authoring-v2'
NAMES = (
    'build.py', 'serve.py', 'install.py', 'revision_install.py',
    'revision_install_r3.py', 'revision_install_r3b.py',
    'source_module_manifest.json', 'source_module_manifest_r3.json',
    'runtime_bake.ModuleScript.luau', 'preview_builder.ModuleScript.luau',
    'preview_bootstrap.Script.luau', 'queue_controller.LocalScript.luau',
    'queue_bridge.ModuleScript.luau', 'compile_candidates.luau',
    'verify_import_helpers.py', 'verify_r3_geometry.py', 'verify_r3_native_scope.luau',
)
COMPILER = Path('C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe')
BEFORE = ROOT / '.git/mongotv-cleanup-20261009/s07-r4-before-v4/receipt.json'
AFTER = ROOT / '.git/mongotv-cleanup-20261009/s07-r4-after-v2'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    assert not DEST.exists() and not AFTER.exists(), 'Refuse immutable archive/port overwrite'
    before_raw = BEFORE.read_bytes()
    before = json.loads(before_raw)
    assert before['pass'] is True and before['schema'] == 'retired-lobby-authoring-active-port-v1'
    selected = {HERE / name: (HERE / name).read_bytes() for name in NAMES}
    tracked = subprocess.check_output(['git', 'ls-files', '-z', 'tools/lobby_reimagined']).split(b'\0')
    protected = {ROOT / p.decode(): (ROOT / p.decode()).read_bytes()
                 for p in tracked if p and ROOT / p.decode() not in selected}
    shared = ROOT / 'tools/level6_build/import/export_prefabs.py'
    protected[shared] = shared.read_bytes()
    assert all(p.resolve().parent == HERE.resolve() and p.is_file() for p in selected)
    ast_checks = compiles = 0
    for path, raw in selected.items():
        if path.suffix == '.py':
            ast.parse(raw.decode('utf8'), filename=str(path))
            ast_checks += 1
        if path.suffix == '.luau':
            for optimization in ('-O0', '-O1'):
                result = subprocess.run([str(COMPILER), '--binary', optimization, str(path)],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                assert result.returncode == 0, result.stderr.decode(errors='replace')
                compiles += 1
    def guard():
        assert BEFORE.read_bytes() == before_raw, 'Before proof changed'
        assert all(path.read_bytes() == raw for path, raw in protected.items()), 'Concurrent preserved authoring edit'
        assert all(path.read_bytes() == raw for path, raw in selected.items()), 'Concurrent retired entry edit'
    guard()
    DEST.mkdir(parents=True)
    rows = []
    archive_compiles = 0
    for path, raw in selected.items():
        target = DEST / 'sources' / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream:
            assert stream.write(raw) == len(raw)
        assert target.read_bytes() == raw
        if path.suffix == '.luau':
            for optimization in ('-O0', '-O1'):
                result = subprocess.run([str(COMPILER), '--binary', optimization, str(target)],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                assert result.returncode == 0, result.stderr.decode(errors='replace')
                archive_compiles += 1
        rows.append({'file': path.relative_to(ROOT).as_posix(), 'bytes': len(raw),
                     'sha256': sha(raw), 'archiveFile': target.relative_to(ROOT).as_posix()})
    (DEST / 'before-active-port.json').write_bytes(before_raw)
    guard()
    removed = []
    try:
        for path, raw in selected.items():
            assert path.read_bytes() == raw and BEFORE.read_bytes() == before_raw
            assert all(p.read_bytes() == v for p, v in protected.items()), 'Concurrent preserved authoring edit'
            path.unlink()
            removed.append(path)
        subprocess.run([sys.executable, str(ROOT / 'tools/cleanup_20261009/probe_lobby_authoring.py'),
                        '--dest', str(AFTER)], check=True)
        after_raw = (AFTER / 'receipt.json').read_bytes()
        after = json.loads(after_raw)
        assert BEFORE.read_bytes() == before_raw, 'Before proof changed during active after-port'
        equivalence = verify(BEFORE.parent, AFTER)
        assert all(not path.exists() for path in selected), 'Retired tool was concurrently reintroduced'
        assert all(path.read_bytes() == raw for path, raw in protected.items()), 'Preserved authoring bytes changed'
        assert all((ROOT / row['archiveFile']).read_bytes() == selected[ROOT / row['file']] for row in rows)
        (DEST / 'after-active-port.json').write_bytes(after_raw)
        (DEST / 'active-equivalence.json').write_text(json.dumps(equivalence, indent=2) + '\n', encoding='utf8')
    except BaseException as error:
        restored, conflicts = [], []
        for path in removed:
            try:
                with path.open('xb') as stream:
                    stream.write(selected[path])
                assert path.read_bytes() == selected[path]
                restored.append(path.relative_to(ROOT).as_posix())
            except FileExistsError:
                conflicts.append(path.relative_to(ROOT).as_posix())
            except BaseException as cleanup:
                error.add_note(f'Exclusive restore failed for {path.name}: {cleanup}')
        try:
            (DEST / 'rollback.json').write_text(json.dumps({'pass': False, 'reason': str(error),
                'restored': restored, 'preservedConcurrentFiles': conflicts}, indent=2) + '\n', encoding='utf8')
        except BaseException as evidence_error:
            error.add_note(f'Rollback evidence write failed: {evidence_error}')
        raise
    receipt = {'schema': 'retired-lobby-authoring-removal-v1', 'pass': True,
        'atUtc': datetime.now(timezone.utc).isoformat(), 'files': rows,
        'filesRemoved': len(rows), 'rawBytesOffActiveTools': sum(r['bytes'] for r in rows),
        'pythonAstChecks': ast_checks, 'beforeLuauCompiles': compiles, 'archiveLuauCompiles': archive_compiles,
        'preservedFiles': len(protected), 'sameActiveAuthoringSemantics': True,
        'beforePortSHA256': sha(before_raw), 'afterPortSHA256': sha(after_raw),
        'scope': 'Retired local workflow closure only; native five-pack removal and active gameplay ports remain separate.'}
    (DEST / 'removal-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf8')
    print(json.dumps({k: receipt[k] for k in ('pass', 'filesRemoved', 'rawBytesOffActiveTools',
                                           'pythonAstChecks', 'beforeLuauCompiles', 'preservedFiles')}))


if __name__ == '__main__':
    main()
