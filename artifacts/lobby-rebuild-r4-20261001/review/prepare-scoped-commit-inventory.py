"""Read Git metadata/stat only first; diff explicit small scoped changed files.

No staging/commit, no broad status, and no binary or cold unrelated file reads.
The inventory identifies exact candidate paths after authoritative export/QA.
It remains distinct from the root's final staged-diff and publication review.
"""
from pathlib import Path
import datetime
import json
import os
import re
import subprocess

ROOT=Path(__file__).resolve().parents[3]
TASK=ROOT/"artifacts/lobby-rebuild-r4-20261001"
SCOPES=("artifacts/lobby-rebuild-r4-20261001/","assets/models/lobby-reimagined-r4-20261001/","tools/lobby_reimagined/")
SMALL_EXTENSIONS={".json",".md",".txt",".py",".luau",".diff"}
NATIVE_SMALL_RECORDS={
    "accounted-concurrent-native-preservation.json","backup-file-hashes.json","backup-metadata-summary.json",
    "checkpoint-install-gate.json","checkpoint-reuse-proof.json","final-scoped-source-mirror.json",
    "fresh-source-manifest.json","metadata.json","metadata.received.json","native-place-verification.json",
    "native-recovery-reopen-verification.json","scoped-native-preservation.json","service-property-schema.json",
    "source-manifest.json","source-transfer-receipt.json","static-pbr-native-reference-verification-final.json",
    "static-pbr-native-reference-verification.json",
}

def run(args):
    return subprocess.run(args,cwd=ROOT,check=True,capture_output=True).stdout

def main():
    head=run(["git","rev-parse","HEAD"]).decode().strip()
    staged=run(["git","diff","--cached","--name-status"]).decode().splitlines()
    raw=run(["git","ls-files","--debug","-z"])
    pattern=rb"([^\0]+)\0  ctime: (\d+):(\d+)\n  mtime: (\d+):(\d+)\n  dev: (\d+)\tino: (\d+)\n  uid: (\d+)\tgid: (\d+)\n  size: (\d+)\tflags: ([^\n]+)\n"
    entries=list(re.finditer(pattern,raw))
    assert entries and sum(match.end()-match.start() for match in entries)==len(raw),"Unexpected Git debug metadata format"
    changed=[]
    for match in entries:
        name=match.group(1).decode()
        index_mtime=int(match.group(4))*1000000000+int(match.group(5))
        index_size=int(match.group(10))
        try:
            stat=(ROOT/name).stat()
            differs=stat.st_mtime_ns!=index_mtime or stat.st_size!=index_size
            current_size=stat.st_size
        except FileNotFoundError:
            differs=True;current_size=None
        if differs:
            changed.append({"file":name,"inTaskScope":name.startswith(SCOPES),"indexBytes":index_size,
                            "currentBytes":current_size,"classification":"stat-different; content not assumed changed"})
    small=[row["file"] for row in changed if row["inTaskScope"] and Path(row["file"]).suffix in SMALL_EXTENSIONS
           and (row["currentBytes"] or 0)<1200000]
    precise=[]
    if small:
        output=run(["git","diff","--name-status","--",*small]).decode().splitlines()
        precise=[{"status":line.split("\t",1)[0],"file":line.split("\t",1)[1]} for line in output]
    others=run(["git","ls-files","--others","--exclude-standard","-z","--",*SCOPES]).split(b"\0")
    catalog=json.loads((ROOT/"tools/lobby_reimagined/r4_candidates/install-catalog-r4-final.json").read_bytes())
    final_mirrors={"artifacts/lobby-rebuild-r4-20261001/fresh-source-after/"+row["path"]+"."+row["class"]+".luau" for row in catalog["sources"]}
    assert len(final_mirrors)==8
    excluded_local=[]
    def selected(path):
        native_prefix="artifacts/lobby-rebuild-r4-20261001/native-after/"
        mirrors_prefix="artifacts/lobby-rebuild-r4-20261001/fresh-source-after/"
        if path.startswith(native_prefix):
            relative=path[len(native_prefix):]
            return relative in NATIVE_SMALL_RECORDS
        if path.startswith(mirrors_prefix):return path in final_mirrors
        if path.startswith("artifacts/lobby-rebuild-r4-20261001/review/concurrent-studio-20261002/") and path.endswith(".observed.luau"):
            return False # Exact bytes remain in full local/native recovery; commit hash/diff/parity records.
        return not any(part in path.split("/") for part in ("__pycache__",".DS_Store")) and not path.endswith(".partial")
    candidates=[item.decode() for item in others if item]
    untracked=[path for path in candidates if selected(path)]
    excluded_local=[path for path in candidates if not selected(path)]
    archive_receipt=TASK/"review/native-after-archive-verification.json"
    ignored_recovery=[]
    if archive_receipt.exists():
        archive=json.loads(archive_receipt.read_bytes())
        assert archive["verified"] is True and archive["recoveryGateVerified"] is True
        archived=["artifacts/lobby-rebuild-r4-20261001/"+row["file"] for row in archive["files"]
                  if selected("artifacts/lobby-rebuild-r4-20261001/"+row["file"])]
        ignore=subprocess.run(["git","check-ignore","--stdin"],cwd=ROOT,input=("\n".join(archived)+"\n").encode(),capture_output=True)
        assert ignore.returncode in (0,1)
        ignored_recovery=ignore.stdout.decode().splitlines()
        assert all(path.startswith("artifacts/lobby-rebuild-r4-20261001/native-after/") and Path(path).name in NATIVE_SMALL_RECORDS for path in ignored_recovery)
    inventory={"schema":"lobby-r4-scoped-commit-inventory-v1","preparedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "head":head,"stagedNameStatus":staged,"trackedIndexEntriesInspected":len(entries),
               "trackedStatDifferences":changed,"exactSmallScopedTrackedChanges":precise,
               "untrackedTaskScopeCandidates":untracked,
               "ignoredVerifiedNativeRecoveryCandidates":ignored_recovery,
               "ignoredRecoveryStagingInstruction":"Only these exact reviewed small JSON hash/property/parity records may be git add -f; raw native/source transfers and local recovery caches remain excluded",
               "excludedLocalRecoveryOrDuplicateSourceCandidates":excluded_local,
               "exactFinalSourceMirrors":sorted(final_mirrors),
               "contentReadsLimitedTo":small,"stagingPerformed":False,"commitPerformed":False,
               "constraints":["Do not stage unrelated stat differences or cathedral assets", "Review exact staged diff after final Studio export",
                              "Exact final native archive and rendered-image evidence are verified; root owns final staged diff and publication receipt",
                              "Full .rbxl/.rbxm/native/source chunks/scripts.json recovery retained locally and in /private/tmp; never force-add raw backups or caches"],
               "limits":"Metadata/stat inventory plus bounded exact small-file names; not a final staged diff, gameplay test or Studio synchronization claim."}
    target=TASK/"review/scoped-commit-inventory.json"
    target.write_text(json.dumps(inventory,indent=2)+"\n")
    (TASK/"review/scoped-commit-candidate-paths.txt").write_text("\n".join(sorted({row["file"] for row in precise}|set(untracked)|set(ignored_recovery)))+"\n")
    (TASK/"review/scoped-commit-force-native-paths.txt").write_text("\n".join(sorted(ignored_recovery))+"\n")
    print(json.dumps({"head":head,"stagedEntries":len(staged),"exactSmallScopedTrackedChanges":precise,
                      "untrackedTaskCandidateCount":len(untracked),"unrelatedStatDifferenceCount":sum(not row["inTaskScope"] for row in changed),
                      "ignoredVerifiedRecoveryPaths":len(ignored_recovery),
                      "inventory":str(target)}),flush=True)

if __name__=="__main__":main()
