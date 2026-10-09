"""Scoped downstream reconciliation of ten already-absent native backup sources.

No Studio calls. Exact historical files/entries stay in an immutable off-mirror
archive. Unrelated current manifest entries and working files are preserved.
"""
from pathlib import Path
import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime,timezone

ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'artifacts/cleanup-serverstorage-20261009/retired-repo-mirrors'
LUAU=Path('C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe')

def sha(data):
    return hashlib.sha256(data).hexdigest()

def prepare_manifest_temp(path,encoded):
    """Fully write/verify an owned sibling before deleting canonical files."""
    descriptor,name=tempfile.mkstemp(prefix='.'+path.name+'.cleanup-',suffix='.tmp',dir=path.parent)
    temporary=Path(name)
    try:
        stream=os.fdopen(descriptor,'wb')
        descriptor=None
        with stream:
            assert stream.write(encoded)==len(encoded),'Incomplete temporary manifest write'
            stream.flush()
            os.fsync(stream.fileno())
        assert temporary.read_bytes()==encoded,'Temporary manifest reload differs'
        return temporary
    except BaseException as error:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except BaseException as cleanup:
                error.add_note(f'Owned temporary descriptor close failed: {cleanup}')
        try:
            temporary.unlink(missing_ok=True)
        except BaseException as cleanup:
            error.add_note(f'Owned temporary manifest cleanup failed: {cleanup}')
        raise

def main():
    metadata_path=DEST.parent/'native-script-metadata.json'
    metadata_raw=metadata_path.read_bytes()
    metadata_sha=sha(metadata_raw)
    meta=json.loads(metadata_raw)
    def metadata_guard():
        assert metadata_path.read_bytes()==metadata_raw,'Concurrent native evidence changed; pinned absence proof invalid'
    missing=set(meta['manifestOnlyPaths'])
    assert len(missing)==10 and all(p.startswith(('ServerStorage.CodexBackup_20260902_ComingSoonGates.','ServerStorage.CodexBackup_20260902_FiveFixes.')) for p in missing)
    assert not DEST.exists(),'Refuse immutable archive overwrite'
    path=ROOT/'studio-sync-manifest.json'
    before=path.read_bytes()
    manifest=json.loads(before)
    rows=[r for r in manifest['items'] if r['studioPath'] in missing]
    assert len(rows)==10 and {r['studioPath'] for r in rows}==missing
    natives={r['studioPath'] for r in meta['items']}
    assert not missing & natives and not meta['editorConflicts']
    data={r['file']:(ROOT/r['file']).read_bytes() for r in rows}
    for row in rows:
        raw=data[row['file']]
        canonical=raw.replace(b'\r\n',b'\n')
        assert len(canonical)==row['bytes'] and sha(canonical)==row['sha256'],'Stale source baseline changed'
        file=(ROOT/row['file']).resolve()
        assert file.is_relative_to(ROOT/'ServerStorage') and file.suffix=='.lua','Scoped target escaped'
        subprocess.run([str(LUAU),'--binary','-O0',str(file)],stdout=subprocess.DEVNULL,check=True)
    metadata_guard()
    assert path.read_bytes()==before and all((ROOT/name).read_bytes()==raw for name,raw in data.items()),'Concurrent baseline changed; keep sources'
    DEST.mkdir()
    (DEST/'manifest-before.json').write_bytes(before)
    records=[]
    for row in rows:
        raw=data[row['file']]
        backup=DEST/'sources'/row['file']
        backup.parent.mkdir(parents=True,exist_ok=True)
        backup.write_bytes(raw)
        assert backup.read_bytes()==raw,'Archive reload byte mismatch'
        subprocess.run([str(LUAU),'--binary','-O1',str(backup)],stdout=subprocess.DEVNULL,check=True)
        records.append(dict(row,rawBytes=len(raw),rawSHA256=sha(raw),archiveFile=backup.relative_to(ROOT).as_posix()))
    after=copy.deepcopy(manifest)
    after['items']=[r for r in after['items'] if r['studioPath'] not in missing]
    after['counts']['scripts']=sum(r['className'] in ('Script','LocalScript','ModuleScript') for r in after['items'])
    after['counts']['remoteEvents']=sum(r['className']=='RemoteEvent' for r in after['items'])
    after['counts']['total']=len(after['items'])
    # created/updated/unchanged describe the old full-sync operation; preserve them.
    assert {r['studioPath']:r for r in after['items']}=={r['studioPath']:r for r in manifest['items'] if r['studioPath'] not in missing}
    metadata_guard()
    assert path.read_bytes()==before and all((ROOT/name).read_bytes()==raw for name,raw in data.items()),'Concurrent baseline changed; keep sources'
    encoded=(json.dumps(after,indent=2,ensure_ascii=False)+'\n').encode('utf8')
    removed=[]
    temporary=None
    try:
        temporary=prepare_manifest_temp(path,encoded)
        metadata_guard()
        assert path.read_bytes()==before and all((ROOT/name).read_bytes()==raw for name,raw in data.items()),'Concurrent baseline changed; keep sources'
        for name,raw in data.items():
            metadata_guard()
            file=(ROOT/name).resolve()
            assert file.is_relative_to(ROOT/'ServerStorage') and file.read_bytes()==raw
            file.unlink()
            removed.append(name)
        assert path.read_bytes()==before,'Manifest changed during batch; restore only our deleted files'
        metadata_guard()
        os.replace(temporary,path)
        temporary=None
    except BaseException as error:
        for name in removed:
            file=ROOT/name
            # Exclusive creation preserves a concurrently reintroduced file,
            # including one appearing after a presence check would have run.
            try:
                with file.open('xb') as stream:
                    stream.write(data[name])
            except FileExistsError:
                pass
            except BaseException as recovery:
                error.add_note(f'Restore of our deleted file {name} failed: {recovery}')
        raise
    finally:
        if temporary is not None:
            primary=sys.exc_info()[1]
            try:
                temporary.unlink(missing_ok=True)
            except BaseException as cleanup:
                if primary is None:
                    raise
                primary.add_note(f'Owned temporary manifest cleanup failed: {cleanup}')
    assert path.read_bytes()==encoded
    assert all(not (ROOT/name).exists() for name in data)
    # Commit has completed; a later evidence edit fails receipt certification
    # without restoring sources into the already-updated manifest.
    metadata_guard()
    receipt={'schema':'already-absent-mirror-retirement-v1','batch':'S02','completedAtUtc':datetime.now(timezone.utc).isoformat(),
        'nativeEvidence':'artifacts/cleanup-serverstorage-20261009/native-script-metadata.json',
        'nativeEvidenceSHA256':metadata_sha,
        'nativeMutations':0,'studioModeChanges':0,'removedMirrorFiles':len(rows),'removedCanonicalBytes':sum(r['bytes'] for r in rows),
        'archived':records,'manifestRawBeforeSHA256':sha(before),'manifestRawAfterSHA256':sha(encoded),
        'countsBefore':manifest['counts'],'countsAfter':after['counts'],'archiveReloadByteExact':True,'compilesBeforeO0':10,'compilesArchiveO1':10,
        'scope':'Only downstream mirror absence; no runtime feature removal or native folder restoration claim'}
    (DEST/'removal-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf8',newline='\n')
    print(json.dumps({k:receipt[k] for k in ('batch','removedMirrorFiles','removedCanonicalBytes','nativeMutations','countsAfter')}))

if __name__=='__main__':
    main()
