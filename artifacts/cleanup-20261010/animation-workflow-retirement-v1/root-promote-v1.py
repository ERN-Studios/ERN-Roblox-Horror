"""Root-only scoped local retirement. No Studio, upload or Git mutation."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PRIVATE = ROOT / '.git/mongotv-cleanup-20261010/animation-retirement-v1'
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


def save(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        assert stream.write(raw) == len(raw)


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def inputs():
    frozen = json.loads((HERE / 'frozen-pins-v1.json').read_bytes())
    for row in frozen['files']:
        raw = (ROOT / row['file']).read_bytes()
        assert len(raw) == row['rawBytes'] and SHA(raw) == row['rawSHA256'], row['file']
    proposal = json.loads((HERE / 'proposal-v1/proposal.json').read_bytes())
    for row in proposal['retainedInputsAndReceipts']:
        assert SHA((ROOT / row['file']).read_bytes()) == row['rawSHA256'], row['file']
    native = json.loads((HERE / 'root-native-before-v2.json').read_bytes())
    assert native['placeId'] == 131311258779917 and native['universeId'] == 10559217407
    for row in native['sourceRows']:
        suffix = '.ModuleScript.lua' if row['class'] == 'ModuleScript' else '.LocalScript.lua' if row['class'] == 'LocalScript' else '.Script.lua'
        path = row['path'].replace('.', '/') + suffix
        raw = (ROOT / path).read_bytes().replace(b'\r\n', b'\n')
        assert SHA(raw) == row['sha256'] and len(raw) == row['bytes'] and row['editorMatches'], path
    return proposal


def checkpoint(proposal):
    assert not PRIVATE.exists(), 'Immutable checkpoint already exists'
    current = {row['file']: (ROOT / row['file']).read_bytes() for row in proposal['files']}
    assert all(SHA(current[row['file']]) == row['beforeSHA256'] for row in proposal['files'])
    receipt = {'schema': 'mongotv-local-animation-retirement-checkpoint-v1',
               'head': git('rev-parse', 'HEAD').decode().strip(),
               'status': git('status', '--short').decode(),
               'stagedPaths': git('diff', '--cached', '--name-only').decode().splitlines(),
               'nativeBeforeSHA256': SHA((HERE / 'root-native-before-v2.json').read_bytes()),
               'preparedPortSHA256': SHA((HERE / 'root-prepared-port-v1.json').read_bytes()),
               'files': []}
    assert json.loads((HERE / 'root-prepared-port-v1.json').read_bytes())['pass']
    paths = [*current, 'README.md', 'CLEANUP_PLAN.md', 'CLEANUP_RESULTS.md']
    for path in paths:
        raw = (ROOT / path).read_bytes()
        save(PRIVATE / 'before' / path, raw)
        receipt['files'].append({'file': path, 'rawBytes': len(raw), 'rawSHA256': SHA(raw)})
    index = ROOT / '.git/index'
    save(PRIVATE / 'index.before', index.read_bytes())
    save(PRIVATE / 'checkpoint.json', (json.dumps(receipt, indent=2) + '\n').encode())
    print(json.dumps({'pass': True, 'checkpointed': len(paths), 'productionWrites': 0, 'indexWrites': 0}))


def promote(proposal):
    assert PRIVATE.exists() and not (HERE / 'root-promotion-result-v1.json').exists()
    before = {row['file']: (PRIVATE / 'before' / row['file']).read_bytes() for row in proposal['files']}
    candidate = {row['file']: (HERE / 'proposal-v1/candidate' / row['file']).read_bytes() for row in proposal['files']}
    for row in proposal['files']:
        assert SHA(before[row['file']]) == row['beforeSHA256']
        assert SHA(candidate[row['file']]) == row['candidateSHA256']
        assert (ROOT / row['file']).read_bytes() == before[row['file']], row['file']
    attempted = []
    result = {'schema': 'mongotv-local-animation-retirement-promotion-v1', 'pass': False,
              'startedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'headAtStart': git('rev-parse', 'HEAD').decode().strip(), 'nativeWrites': 0,
              'manifestWrites': 0, 'indexWrites': 0, 'assetUploads': 0, 'rollback': {}}
    try:
        for row in proposal['files']:
            path = row['file']
            assert (ROOT / path).read_bytes() == before[path], 'Fresh file CAS: ' + path
            attempted.append(path)
            with (ROOT / path).open('wb') as stream:
                assert stream.write(candidate[path]) == len(candidate[path])
            assert (ROOT / path).read_bytes() == candidate[path], 'Write readback: ' + path
        run = subprocess.run([sys.executable, '-B', str(HERE / 'verify_guards.py'), '--verify-installed',
                              '--receipt', str(HERE / 'root-installed-port-v1.json')], cwd=ROOT,
                             capture_output=True, timeout=90)
        result['installedPort'] = {'exitCode': run.returncode, 'stdout': run.stdout.decode(errors='replace'),
                                   'stderr': run.stderr.decode(errors='replace')}
        assert run.returncode == 0, 'Installed port failed'
        for row in proposal['files']:
            assert (ROOT / row['file']).read_bytes() == candidate[row['file']]
        for row in proposal['retainedInputsAndReceipts']:
            assert SHA((ROOT / row['file']).read_bytes()) == row['rawSHA256']
        result['pass'] = True
        result['files'] = proposal['files']
        result['installedPortSHA256'] = SHA((HERE / 'root-installed-port-v1.json').read_bytes())
    except BaseException as error:
        result['error'] = repr(error)
        for path in reversed(attempted):
            try:
                raw = (ROOT / path).read_bytes()
                if raw == before[path]:
                    result['rollback'][path] = 'already original'
                elif raw == candidate[path]:
                    with (ROOT / path).open('wb') as stream:
                        assert stream.write(before[path]) == len(before[path])
                    assert (ROOT / path).read_bytes() == before[path]
                    result['rollback'][path] = 'exact original restored'
                else:
                    result['rollback'][path] = 'foreign/partial bytes preserved; fresh reconciliation required'
            except BaseException as recovery:
                result['rollback'][path] = 'unreadable/recovery failure preserved: ' + repr(recovery)
    result['finishedAtUtc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    result['attemptedLocalToolWrites'] = len(attempted)
    result['limits'] = 'Scoped compare/write/readback, not cross-process atomicity. Four retired authoring entrypoints only; full exact original bytes archived. Native forests, all upload-cache metadata and gameplay Sources untouched. Offline optional/native boundaries and documented cache fixtures do not certify current native cache data or playback.'
    save(HERE / 'root-promotion-result-v1.json', (json.dumps(result, indent=2) + '\n').encode())
    print(json.dumps({'pass': result['pass'], 'localTools': len(attempted), 'nativeWrites': 0, 'rollback': result['rollback']}))
    return 0 if result['pass'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--checkpoint', action='store_true')
    parser.add_argument('--promote', action='store_true')
    args = parser.parse_args()
    assert args.checkpoint != args.promote
    proposal = inputs()
    if args.checkpoint:
        checkpoint(proposal)
    else:
        raise SystemExit(promote(proposal))
