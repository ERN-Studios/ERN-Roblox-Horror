"""Replay archived offline tests in a temporary tree; never write Studio or repo sources.

The six old sources are reconstructed by reversing the recorded exact fragments,
then checked against their baseline SHA-256. Current mirrors must match the six
installed hashes. Test generators remain unchanged and run only inside the temp tree.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile

PACKAGE = Path(__file__).resolve().parent
REPO = PACKAGE.parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--luau-dir', type=Path, default=REPO.parent / 'level5-build/tools/luau')
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args()
luau = args.luau_dir.resolve()
assert (luau / 'luau').is_file() and (luau / 'luau-compile').is_file(), 'Pass --luau-dir with both Luau binaries'
manifest = json.loads((PACKAGE / 'cas-payloads/manifest.json').read_text())
closures = {row['file']: row for row in json.loads((PACKAGE / 'closure/source-transitions.json').read_text())['files']}
sha = lambda value: hashlib.sha256(value).hexdigest()
results = []
json_string = r'"(?:[^"\\]|\\.)*"'
edit_pattern = re.compile(r'\{old=(' + json_string + r'),new=(' + json_string + r')\}')

with tempfile.TemporaryDirectory(prefix='level5-opening-checks-') as folder:
    project = Path(folder)
    output = project / 'output'
    task = output / 'level5-opening-20260927'
    task.mkdir(parents=True)
    (output / 'level5-build/tools').mkdir(parents=True)
    (output / 'level5-build/tools/luau').symlink_to(luau, target_is_directory=True)
    (output / 'level5-window-watcher-repository').symlink_to(REPO, target_is_directory=True)
    for name in ('access-drafts', 'cas-payloads', 'outage-drafts', 'lobby-drafts', 'puzzle-review', 'clue-drafts', 'closure'):
        shutil.copytree(PACKAGE / name, task / name)
    for row in closures.values():
        closed = (REPO / row['file']).read_bytes()
        assert sha(closed) == row['closedSha256'], 'Current closure mirror changed: ' + row['file']
        target = task / 'closure/sources' / row['file']
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(closed)
    baseline = task / 'baseline/sources'
    for service in ('ReplicatedStorage', 'ServerScriptService', 'StarterPlayer'):
        for path in (REPO / service).rglob('*.lua'):
            target = baseline / path.relative_to(REPO)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    for row in manifest:
        new = (REPO / row['file']).read_bytes()
        if sha(new) != row['expectedSha256'] and row['file'] in closures:
            closure = closures[row['file']]
            assert sha(new) == closure['closedSha256'], 'Unexpected source after closure: ' + row['file']
            text = new.decode('utf-8')
            for edit in reversed(closure['edits']):
                assert text.count(edit['closed']) == 1, 'Closure fragment must be unique'
                text = text.replace(edit['closed'], edit['opened'], 1)
            new = text.encode('utf-8')
        assert sha(new) == row['expectedSha256'], 'Runtime mirror changed: ' + row['file']
        payload = task / 'cas-payloads' / Path(row['payloadFile']).name
        edits = [(json.loads(a), json.loads(b)) for a, b in edit_pattern.findall(payload.read_text())]
        assert len(edits) == row['fragmentCount'], 'Could not decode recorded fragments'
        old = new.decode('utf-8')
        for before, after in reversed(edits):
            assert old.count(after) == 1, 'Reverse fragment must be unique'
            old = old.replace(after, before, 1)
        assert sha(old.encode('utf-8')) == row['baselineSha256'], 'Reconstructed baseline hash mismatch'
        (baseline / row['file']).write_text(old)
        draft_parts = Path(row['draftFile']).parts
        index = next(i for i, part in enumerate(draft_parts) if part in ('access-drafts', 'lobby-drafts', 'outage-drafts', 'clue-drafts'))
        draft = task.joinpath(*draft_parts[index:])
        draft.parent.mkdir(parents=True, exist_ok=True)
        draft.write_bytes(new)
        row['draftFile'] = str(draft)
        row['payloadFile'] = str(payload)
        row['verifyFile'] = str(task / 'cas-payloads' / Path(row['verifyFile']).name)
    (task / 'cas-payloads/manifest.json').write_text(json.dumps(manifest))
    for name in ('cas-payloads', 'access-drafts', 'outage-drafts'):
        (task / name / 'checks').mkdir(exist_ok=True)

    def run(label, command):
        result = subprocess.run([str(p) for p in command], cwd=task, capture_output=True, text=True)
        record = {'test': label, 'exitCode': result.returncode, 'stdout': result.stdout.strip(), 'stderr': result.stderr.strip()}
        results.append(record)
        if result.returncode:
            raise RuntimeError(json.dumps(record, indent=2))

    for row in manifest:
        wrapper = task / 'cas-payloads/checks' / (Path(row['file']).name + '.compile.luau')
        wrapper.write_text('return function()\n' + Path(row['draftFile']).read_text() + '\nend\n')
        run('compile ' + row['file'], [luau / 'luau-compile', '-O0', '--null', wrapper])
        for kind in ('payloadFile', 'verifyFile'):
            run('compile ' + Path(row[kind]).name, [luau / 'luau-compile', '-O0', '--null', row[kind]])
    for name in ('access-drafts/verify_drafts.py', 'cas-payloads/test_payloads.py', 'outage-drafts/build_and_verify.py', 'lobby-drafts/run_geometry_checks.py'):
        run(name, [sys.executable, task / name])
    for name in ('test_level5_puzzle_catalog.luau', 'test_puzzle_layout_math.luau'):
        run(name, [luau / 'luau', task / 'puzzle-review' / name])
    run('current closure policy/defaults/builder checks', [sys.executable, task / 'closure/run_offline_verification.py'])

report = {'scope': 'Historical opening-state offline replay followed by current closed-access checks, in an automatically removed temporary tree. Recorded closure fragments reconstruct the verified opening sources for the historical tests. No Studio writes, native gameplay or source changes.',
          'mirrorsAndReconstructedBaselinesVerified': 6, 'passed': True, 'results': results}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print(f'PASS: {len(results)} checks; six current and reconstructed baseline SHA-256 pairs verified')
