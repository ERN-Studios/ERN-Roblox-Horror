"""Actual main and real temporary files around manifest registration faults."""
from pathlib import Path
from contextlib import redirect_stdout
from unittest.mock import patch
import argparse
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('actual_installer_ports', HERE / 'test_candidate_v3.py')
ports = importlib.util.module_from_spec(spec); spec.loader.exec_module(ports)
app, sync, legacy = ports.candidate, ports.sync, ports.legacy
checks = 0


def check(value, message):
    global checks
    checks += 1
    assert value, message


def main_case(scenario):
    with tempfile.TemporaryDirectory(prefix='generic-atomic-fault-') as directory:
        root = Path(directory)
        mirror = root / legacy.FILE
        mirror.parent.mkdir(parents=True)
        mirror.write_bytes(legacy.NEW.encode())
        target = {'file': legacy.FILE, 'studioPath': legacy.PATH, 'className': 'ModuleScript', 'status': 'synced', 'ownerUnknown': {'receiptIDs': ['keep']}}
        other = {'file': 'ReplicatedStorage/Other.ModuleScript.lua', 'studioPath': 'ReplicatedStorage.Other', 'className': 'ModuleScript', 'status': 'pending-studio-push', 'ownerUnknown': 'keep'}
        value = {'items': [target, other], 'counts': {'scripts': 2, 'total': 2}, 'ownerUnknown': 'keep'}
        manifest = root / 'studio-sync-manifest.json'
        manifest.write_bytes((json.dumps(value) + '\n').encode())
        before = manifest.read_bytes()
        temporary = manifest.with_name(manifest.name + '.installer-owned.tmp')
        foreign = b'foreign authoring work preserved'
        client = ports.Client('overwrite', legacy.PATH, legacy.NEW)
        original_open, original_replace, original_read, original_unlink, original_stat = Path.open, os.replace, Path.read_bytes, Path.unlink, Path.stat
        used = False
        foreign_manifest = None
        observed_identity = None
        expected_partial = None
        manifest_reads = 0

        class WritePort:
            def __init__(self, stream): self.stream = stream
            def __enter__(self): self.stream.__enter__(); return self
            def __exit__(self, *args):
                result = self.stream.__exit__(*args)
                if scenario == 'write-close-error': raise OSError('controlled close error after complete write')
                return result
            def fileno(self): return self.stream.fileno()
            def write(self, encoded):
                nonlocal foreign_manifest, expected_partial
                if scenario == 'write-error-before':
                    expected_partial = b''
                    raise OSError('controlled before write error')
                if scenario in {'write-partial-error', 'write-incomplete-return'}:
                    expected_partial = encoded[:37]
                    self.stream.write(expected_partial)
                    if scenario == 'write-partial-error': raise OSError('controlled partial write error')
                    return len(expected_partial)
                result = self.stream.write(encoded)
                if scenario == 'foreign-manifest-pre-replace':
                    foreign_value = json.loads(before)
                    foreign_value['ownerConcurrent'] = {'marker': 314}
                    foreign_value['items'][1]['ownerConcurrent'] = 'preserve'
                    foreign_manifest = (json.dumps(foreign_value) + '\n').encode()
                    with original_open(manifest, 'wb') as stream: stream.write(foreign_manifest)
                return result

        def open_port(self, *args, **kwargs):
            nonlocal used
            if self == temporary and args and args[0] == 'xb' and scenario == 'foreign-temp-open-race' and not used:
                used = True
                with original_open(temporary, 'xb') as stream:
                    stream.write(foreign)
            stream = original_open(self, *args, **kwargs)
            if self == temporary and args and args[0] == 'xb' and scenario in {'write-error-before', 'write-partial-error', 'write-incomplete-return', 'write-close-error', 'foreign-manifest-pre-replace'}:
                return WritePort(stream)
            return stream

        def read_port(self):
            nonlocal manifest_reads
            if self == manifest:
                manifest_reads += 1
                if scenario == 'manifest-pre-replace-read-error' and manifest_reads == 3:
                    raise OSError('controlled immediate registration guard read failure')
                if scenario == 'manifest-post-replace-read-error' and manifest_reads == 4:
                    raise OSError('controlled postreplace guard read failure')
            return original_read(self)

        def stat_port(self, *args, **kwargs):
            if self == temporary and scenario == 'temp-cleanup-getter-error' and used:
                raise OSError('controlled owned cleanup identity getter error')
            return original_stat(self, *args, **kwargs)

        def replace_port(source, destination):
            nonlocal used, foreign_manifest, observed_identity
            if Path(source) == temporary and not used:
                used = True
                if scenario == 'replace-before-error':
                    raise OSError('controlled pre-replace failure')
                if scenario == 'temp-cleanup-getter-error':
                    raise OSError('controlled pre-replace failure before getter error')
                if scenario == 'foreign-temp-edit':
                    with original_open(temporary, 'wb') as stream:
                        stream.write(foreign)
                    raise OSError('controlled after foreign temp edit')
                if scenario == 'foreign-temp-replacement-same-bytes':
                    replacement = root / 'foreign-owned.tmp'
                    with original_open(replacement, 'xb') as stream:
                        stream.write(original_read(temporary))
                    observed_identity = (temporary.stat().st_ino, replacement.stat().st_ino)
                    check(observed_identity[0] != observed_identity[1], 'real replacement has distinct file identity')
                    original_replace(replacement, temporary)
                    raise OSError('controlled after foreign identity replacement')
                result = original_replace(source, destination)
                if scenario == 'replace-commit-error':
                    raise OSError('controlled error after actual replace')
                if scenario == 'foreign-manifest-post-replace':
                    landed = json.loads(original_read(manifest))
                    landed['ownerConcurrent'] = {'marker': 213}
                    landed['items'][0]['ownerConcurrent'] = 'preserve'
                    foreign_manifest = (json.dumps(landed) + '\n').encode()
                    with original_open(manifest, 'wb') as stream:
                        stream.write(foreign_manifest)
                return result
            return original_replace(source, destination)

        def unlink_port(self, *args, **kwargs):
            if self == temporary and scenario == 'own-cleanup-unlink-error':
                raise OSError('controlled owned temp cleanup error')
            return original_unlink(self, *args, **kwargs)

        if scenario == 'own-cleanup-unlink-error':
            # Causes own temp to remain for cleanup, which then throws.
            real_replace_port = replace_port
            def replace_port(source, destination):
                raise OSError('controlled pre-replace failure before cleanup error')

        output = io.StringIO()
        with patch.object(app, 'ROOT', root), patch.object(app, 'StudioMcpClient', lambda _: client), patch.object(app, 'find_mcp_batch', lambda: root/'NO-MCP'), patch.object(app.time, 'sleep', lambda _: None), patch.object(sys, 'argv', ['candidate', legacy.FILE, '--overwrite']), patch.object(Path, 'open', open_port), patch.object(app.os, 'replace', replace_port), patch.object(Path, 'unlink', unlink_port), patch.object(Path, 'read_bytes', read_port), patch.object(Path, 'stat', stat_port), redirect_stdout(output):
            exitcode = app.main()
        check(exitcode == 1, 'fault gives truthful failure: ' + scenario)
        check(client.initialized and client.closed and client.writes == 1 and client.source == legacy.NEW, 'native candidate remains current; no retry or blind old-source restore')
        check(mirror.read_bytes() == legacy.NEW.encode(), 'input mirror unchanged')
        if scenario in {'foreign-temp-open-race', 'foreign-temp-edit'}:
            check(temporary.exists() and temporary.read_bytes() == foreign, 'foreign temp retained: ' + scenario)
        elif scenario == 'foreign-temp-replacement-same-bytes':
            check(temporary.exists() and temporary.stat().st_ino == observed_identity[1], 'foreign same-byte file identity retained')
        elif scenario == 'own-cleanup-unlink-error':
            check(temporary.exists() and 'cleanup error' in output.getvalue(), 'owned cleanup failure remains visible')
        elif scenario == 'temp-cleanup-getter-error':
            check(temporary.exists() and 'getter error' in output.getvalue(), 'unknown cleanup identity is preserved and reported')
        elif scenario in {'write-error-before', 'write-partial-error', 'write-incomplete-return'}:
            check(temporary.exists() and temporary.read_bytes() == expected_partial, 'unknown incomplete write outcome retained exactly')
        else:
            check(not temporary.exists(), 'known own temp cleaned or moved: ' + scenario)
        if scenario in {'foreign-manifest-post-replace', 'foreign-manifest-pre-replace'}:
            check(manifest.read_bytes() == foreign_manifest, 'foreign concurrent manifest is preserved exactly')
        elif scenario in {'replace-commit-error', 'manifest-post-replace-read-error'}:
            current = json.loads(manifest.read_bytes())
            check(current['items'][-1]['sha256'] == ports.sha(legacy.NEW), 'committed manifest is preserved after error')
        else:
            check(manifest.read_bytes() == before, 'pre-replace failure leaves manifest exactly unchanged')
        live = json.loads(manifest.read_bytes())
        check(next(row for row in live['items'] if row['file'] == other['file']) == other or scenario in {'foreign-manifest-post-replace', 'foreign-manifest-pre-replace'}, 'unrelated queued row remains untouched by candidate')
        # A foreign postreplace fixture explicitly modifies that row itself.
        return {'case': scenario, 'pass': True, 'sourceWrites': client.writes, 'tempRemaining': temporary.exists(), 'stdout': output.getvalue()}


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--receipt', type=Path, required=True); args = ap.parse_args()
    assert not args.receipt.exists()
    cases = [main_case(case) for case in ('foreign-temp-open-race', 'foreign-temp-edit', 'foreign-temp-replacement-same-bytes', 'replace-before-error', 'replace-commit-error', 'foreign-manifest-post-replace', 'own-cleanup-unlink-error', 'write-error-before', 'write-partial-error', 'write-incomplete-return', 'write-close-error', 'foreign-manifest-pre-replace', 'manifest-pre-replace-read-error', 'manifest-post-replace-read-error', 'temp-cleanup-getter-error')]
    value = {'schema': 'generic-installer-actual-main-atomic-faults-v2', 'pass': True, 'cases': cases, 'checks': checks, 'candidateSHA256': hashlib.sha256((HERE/'tools/install_new_scripts.py').read_bytes()).hexdigest(), 'testSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'nativeCalls': 0, 'productionWrites': 0, 'limits': 'Real local open/replace/postread/cleanup with actual main. Native service/chunk transport boundaries fake; no cross-process lock or native authoring certification. Unknown partial temp writes and cleanup getter failures deliberately retain the own file for review.'}
    with args.receipt.open('xb') as stream: stream.write((json.dumps(value, indent=2)+'\n').encode())
    print(json.dumps({'pass': True, 'cases': len(cases), 'checks': checks}))


if __name__ == '__main__': main()
