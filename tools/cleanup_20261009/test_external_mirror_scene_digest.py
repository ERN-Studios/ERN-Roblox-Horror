"""Execute the identical S06 scene multiset helper offline with real SHA256.

No Studio, native objects or canonical mirrors are touched. Lune runs the actual
extracted Luau helper; Luau0.737 compiles it at O0/O1. The native getter/scene
snapshots remain a separate parent-owned port.
"""
from pathlib import Path
import argparse
import ast
import hashlib
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GUARD = Path(__file__).with_name("external_mirror_retirement_guard.luau")
LUNE = Path(os.environ["TEMP"]) / "codex-lune-0.10.5/lune.exe"
COMPILER = Path(os.environ["TEMP"]) / "codex-luau-0.737/luau-compile.exe"
BEGIN = "-- S06_SCENE_DIGEST_BEGIN: identical pure helper is extracted by the offline port."
END = "-- S06_SCENE_DIGEST_END"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    if args.receipt:
        assert not args.receipt.exists(), "Refuse evidence overwrite"
    before = GUARD.read_bytes()
    text = before.decode("utf8")
    assert text.count(BEGIN) == text.count(END) == 1
    helper = text.split(BEGIN, 1)[1].split(END, 1)[0]
    source = 'local serde=require("@lune/serde")\n' + helper + r'''
local checks,cases=0,{}
local function check(value,message)
 checks+=1 assert(value,message)
end
local function realHash(value)return serde.hash("sha256",value)end
local yields=0
local function checkpoint()yields+=1 end
local function pass(name)cases[#cases+1]={name=name,pass=true}end
local function reject(name,fn)
 local ok=pcall(fn) check(not ok,"Missing rejection: "..name) pass(name)
end
local duplicate,bounds=sceneDigest({same=416276},416276,realHash,checkpoint)
check(#duplicate==64 and bounds.uniqueRows==1 and bounds.nodeLimit==500000,"Current large native count fits bounded multiset")
pass("416276 nodes with duplicate structural rows")
local counts={} for i=1,100001 do counts["scene-"..tostring(i)]=1 end
local ordered,bigBounds=sceneDigest(counts,100001,realHash,checkpoint)
check(bigBounds.uniqueRows==100001 and bigBounds.maxBucketUniques<=10000,"Above old100k count retains all unique rows within bucket bound")
check(yields>=100+256,"Large digest checkpoints remain bounded")
pass("100001 unique rows with real SHA256")
local reverse={} for i=100001,1,-1 do reverse["scene-"..tostring(i)]=1 end
local reordered=sceneDigest(reverse,100001,realHash,checkpoint)
check(reordered==ordered,"Equivalent scene multiset reordered must match")
pass("Reordered census preserves exact multiset digest")
reverse["scene-1"]=nil reverse["actor-renamed-row"]=1
local renamed=sceneDigest(reverse,100001,realHash,checkpoint)
check(renamed~=ordered,"Changed structural row must change digest")
pass("One changed structural row changes signature")
local multiplicity=sceneDigest({same=416275,other=1},416276,realHash,checkpoint)
check(multiplicity~=duplicate,"Duplicate multiplicity cannot be discarded")
pass("Duplicate structural row multiplicity preserved")
local boundary=sceneDigest({same=500000},500000,realHash,checkpoint)
check(boundary~=duplicate,"Exact max node count remains included in signature")
pass("500000 exact boundary succeeds")
reject("500001 exceeds scene cap before hashing",function()
 sceneDigest({same=500001},500001,function()error("must reject before hashing")end,checkpoint)
end)
reject("Declared census count differs from multiset",function()sceneDigest({same=3},4,realHash,checkpoint)end)
reject("Nonintegral or nonpositive multiplicity",function()sceneDigest({same=1.5},1,realHash,checkpoint)end)
local crowded={} for i=1,10001 do crowded["crowded-"..tostring(i)]=1 end
reject("10001 distinct rows in one forced bucket reject",function()
 sceneDigest(crowded,10001,function()return string.rep("0",64)end,checkpoint)
end)
reject("Invalid hash cannot silently select a bucket",function()
 sceneDigest({same=1},1,function()return "not-a-sha256"end,checkpoint)
end)
local interrupted=0
reject("Checkpoint failure propagates without further work",function()
 sceneDigest(counts,100001,realHash,function()interrupted+=1 error("fixture Edit/lease changed")end)
end)
check(interrupted==1,"Failed checkpoint continues no later hash stage")
print(serde.encode("json",{pass=true,checks=checks,cases=cases,checkpoints=yields,
 nativeCalls=0,nativeWrites=0,currentLargeNodeCount=416276,uniqueLargeRows=100001,
 nodeLimit=MAX_SCENE_NODES,bucketUniqueLimit=MAX_BUCKET_UNIQUES,
 scope="Actual extracted pure scene digest with real offline SHA; no native getter, Source/editor, gameplay or performance certification."}))
'''
    with tempfile.TemporaryDirectory(prefix=".s06-scene-fixture-", dir=ROOT) as directory:
        fixture = Path(directory) / "actual-scene-helper-fixture.luau"
        fixture.write_bytes(source.encode("utf8"))
        compiles = []
        for optimization in ("-O0", "-O1"):
            subprocess.run([str(COMPILER), "--binary", optimization, str(fixture)], check=True,
                           stdout=subprocess.DEVNULL)
            compiles.append(optimization)
        result = subprocess.run([str(LUNE), "run", str(fixture)], check=True, capture_output=True,
                                text=True, timeout=120)
        report = json.loads(result.stdout)
    assert report["pass"] and report["nativeCalls"] == report["nativeWrites"] == 0
    assert GUARD.read_bytes() == before, "Concurrent actual guard changed"
    ast.parse(Path(__file__).read_text(encoding="utf8"), filename=str(Path(__file__)))
    report.update(schema="s06-exact-scene-digest-offline-v1", guardSHA256=sha(before),
                  extractedHelperSHA256=sha(helper.encode("utf8")), testSHA256=sha(Path(__file__).read_bytes()),
                  luneSHA256=sha(LUNE.read_bytes()), compilerSHA256=sha(COMPILER.read_bytes()),
                  actualHelperCompiles=compiles, fixtureSHA256=sha(source.encode("utf8")))
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        with args.receipt.open("xb") as stream:
            stream.write((json.dumps(report, indent=2) + "\n").encode())
    print(json.dumps(report))


if __name__ == "__main__":
    main()
