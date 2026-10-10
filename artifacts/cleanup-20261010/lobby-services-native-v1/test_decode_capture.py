"""Actual bounded decoder and CLI negative ports. Explicit synthetic metadata."""
from pathlib import Path
import argparse
import base64
import copy
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('actual_owned_capture_decoder', HERE / 'decode_capture.py')
decoder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(decoder)
zstd = decoder.zstandard

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def body():
    return {'schema': 'mongotv-lobby-owned-native-baseline-v1', 'attributeEncoding': 'roblox-attribute-components-v1',
            'pass': True, 'session': {'fixtureOnly': True}, 'originalSourceWrites': 0, 'modeSwitches': 0, 'objectsCreated': 0,
            'rows': [{'meta': {'instanceId': f'fixture_{i}', 'studioPath': f'Fixture.Original{i}', 'className': 'ModuleScript'},
                      'bytes': 0, 'sha256': '0' * 64} for i in range(213)],
            'assetRows': [{'fixtureOnly': True}], 'nativeManifestSHA256': '0' * 64}

def envelope(value, contentsize=True):
    raw = (json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n').encode()
    compressed = zstd.ZstdCompressor(level=3, write_content_size=contentsize).compress(raw)
    return {'schema': 'mongotv-lobby-native-compressed-envelope-v2', 'encoding': 'zstd/base64',
            'rawBytes': len(raw), 'rawSHA256': sha(raw), 'compressedBytes': len(compressed),
            'compressedSHA256': sha(compressed), 'data': base64.b64encode(compressed).decode()}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--receipt', required=True)
    args = parser.parse_args()
    receipt = ROOT / args.receipt
    assert not receipt.exists()
    cases, checks = [], 0
    wanted = body()
    valid = envelope(wanted)
    raw, result = decoder.decode(valid)
    assert result == wanted and sha(raw) == valid['rawSHA256']
    cases.append({'name': 'bounded exact decode', 'pass': True})
    checks += 2
    negatives = []
    for name, field, value in [('raw hash', 'rawSHA256', 'f' * 64), ('compressed hash', 'compressedSHA256', 'f' * 64),
                               ('raw too large', 'rawBytes', 1000001), ('raw bool', 'rawBytes', True),
                               ('compressed bool', 'compressedBytes', True), ('compressed too large', 'compressedBytes', 60001),
                               ('invalid base64', 'data', '!!!!!'), ('base64 over bound', 'data', 'A' * 80001),
                               ('raw length mismatch', 'rawBytes', valid['rawBytes'] + 1),
                               ('compressed length mismatch', 'compressedBytes', valid['compressedBytes'] + 1),
                               ('encoding', 'encoding', 'gzip'), ('schema', 'schema', 'old'),
                               ('sha not lowercase', 'rawSHA256', 'F' * 64)]:
        changed = copy.deepcopy(valid)
        changed[field] = value
        negatives.append((name, changed))
    changed = copy.deepcopy(valid)
    changed['unknown'] = 1
    negatives.append(('unknown envelope field', changed))
    negatives.append(('frame without bounded content size', envelope(wanted, False)))
    changed = copy.deepcopy(valid)
    compressed = base64.b64decode(changed['data']) + b'foreign'
    changed.update(data=base64.b64encode(compressed).decode(), compressedBytes=len(compressed), compressedSHA256=sha(compressed))
    negatives.append(('trailing compressed payload', changed))
    for name, change in [('original count', lambda v: v['rows'].pop()),
                         ('duplicate identity', lambda v: v['rows'][1]['meta'].update(instanceId='fixture_0')),
                         ('duplicate path', lambda v: v['rows'][1]['meta'].update(studioPath='Fixture.Original0')),
                         ('wrong class', lambda v: v['rows'][1]['meta'].update(className='Folder')),
                         ('failed capture', lambda v: v.update(pass_=False)),
                         ('original source write', lambda v: v.update(originalSourceWrites=1)),
                         ('mode switch', lambda v: v.update(modeSwitches=1)),
                         ('object write', lambda v: v.update(objectsCreated=1)),
                         ('empty asset census', lambda v: v.update(assetRows=[])),
                         ('untyped attributes', lambda v: v.update(attributeEncoding='old'))]:
        changed = copy.deepcopy(wanted)
        change(changed)
        if name == 'failed capture':
            changed.pop('pass_')
            changed['pass'] = False
        negatives.append((name, envelope(changed)))
    for name, changed in negatives:
        try:
            decoder.decode(changed)
        except (AssertionError, ValueError, KeyError, zstd.ZstdError) as error:
            cases.append({'name': name, 'pass': True, 'errorType': type(error).__name__})
            checks += 1
        else:
            raise AssertionError(f'Actual decoder accepted {name}')
    with tempfile.TemporaryDirectory(prefix='mongotv-native-decoder-') as temporary:
        work = Path(temporary)
        input_file, output = work / 'envelope.json', work / 'baseline.json'
        input_file.write_text(json.dumps(valid), encoding='utf-8')
        command = [sys.executable, '-B', str(HERE / 'decode_capture.py'), '--input', str(input_file), '--output', str(output)]
        run = subprocess.run(command, capture_output=True, text=True, timeout=30)
        assert run.returncode == 0 and output.read_bytes() == raw
        cases.append({'name': 'actual main exact output', 'pass': True})
        checks += 2
        run = subprocess.run(command, capture_output=True, text=True, timeout=30)
        assert run.returncode != 0 and output.read_bytes() == raw
        cases.append({'name': 'actual main immutable existing output', 'pass': True})
        checks += 2
        bad_output = work / 'bad-output.json'
        input_file.write_text(json.dumps(negatives[0][1]), encoding='utf-8')
        run = subprocess.run(command[:-1] + [str(bad_output)], capture_output=True, text=True, timeout=30)
        assert run.returncode != 0 and not bad_output.exists()
        cases.append({'name': 'actual main malformed before output', 'pass': True})
        checks += 2
    dependencies = [{'path': p.as_posix(), 'bytes': len(p.read_bytes()), 'sha256': sha(p.read_bytes())}
                    for p in (HERE / 'decode_capture.py', Path(zstd.__file__))]
    report = {'schema': 'mongotv-owned-native-bounded-decoder-tests-v1', 'pass': True,
              'cases': cases, 'checks': checks, 'dependencies': dependencies, 'zstandardVersion': zstd.__version__,
              'nativeCalls': 0, 'productionWrites': 0, 'indexWrites': 0, 'fixtureOnly': True}
    with receipt.open('x', encoding='utf-8', newline='\n') as file:
        json.dump(report, file, ensure_ascii=False, indent=2)
        file.write('\n')
    print(json.dumps({'pass': True, 'cases': len(cases), 'checks': checks}))

if __name__ == '__main__':
    main()
