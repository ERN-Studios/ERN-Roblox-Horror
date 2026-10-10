"""Re-record mirrored scripts in studio-sync-manifest.json after a push from the Mac, but only when Studio really holds them.

    python3 tools/mac_record_synced.py "<repo-relative file>" ...

For each file the Studio source is fetched whole (the same reader tools/mac_merge_push.py uses) and compared with the
working file under tools/studio_source_contract.py's rules. Equal: the entry gets the REPO file's canonical size and hash and
status `synced`. Different: nothing is written for that file and the tool exits non-zero. A file with no manifest entry is
reported, not invented: new scripts get their entry by hand, as CLAUDE.md says.
"""
import datetime
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / 'level6_playground'))
import import_to_studio as studio_io   # noqa: E402
import mac_merge_push as push          # noqa: E402
from studio_source_contract import canonical_bytes, classify, permits_trailing_newline, sha256_of, EXACT, TRAILING_NEWLINE, apply_trailing_newline_verdict   # noqa: E402

MANIFEST = ROOT / 'studio-sync-manifest.json'


def main():
    rels = [a for a in sys.argv[1:] if not a.startswith('--')]
    manifest = json.loads(MANIFEST.read_text())
    by_file = {item['file']: item for item in manifest['items']}
    studio = studio_io.Studio()
    failed = 0
    for rel in rels:
        item = by_file.get(rel)
        if not item:
            print(f'{rel}: NO MANIFEST ENTRY (add one by hand for a new script)')
            failed += 1
            continue
        repo_text = (ROOT / rel).read_text(encoding='utf-8')
        studio_text = push.fetch(studio, rel).decode('utf-8')
        verdict = classify(repo_text, studio_text, allow_trailing_newline=True)
        if verdict not in (EXACT, TRAILING_NEWLINE):
            print(f'{rel}: Studio differs from the working file ({len(studio_text)} vs {len(repo_text)} characters): not recorded')
            failed += 1
            continue
        apply_trailing_newline_verdict(item, verdict)
        before = item.get('sha256')
        item['bytes'] = len(canonical_bytes(repo_text))
        item['sha256'] = sha256_of(repo_text)
        item['status'] = 'synced'
        item['sourceEditorMatches'] = True
        print(f'{rel}: recorded {item["bytes"]} bytes {item["sha256"][:12]} ({verdict}{", unchanged" if before == item["sha256"] else ""})')
    if failed:
        raise SystemExit(f'{failed} file(s) not recorded; the manifest was not written')
    manifest['capturedAtUtc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
