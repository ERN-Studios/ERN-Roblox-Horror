"""Read-only aggregation of root's actual Play receipts; no Studio/Git actions."""
from pathlib import Path
import hashlib
import json
import math
import statistics

ROOT = Path(__file__).resolve().parents[5]
DATA = ROOT / "artifacts/lobby-polish-20261002/root"
OUT = ROOT / "artifacts/lobby-polish-20261002/bays/actual-interaction-aggregate.json"
inputs = {}


def read(path):
    path = ROOT / path if not path.is_absolute() else path
    raw = path.read_bytes()
    inputs[path] = raw
    value = json.loads(raw)
    if isinstance(value, dict) and "content" in value:
        assert value.get("isError") is False, path
        texts = [item["text"] for item in value["content"] if item["type"] == "text"]
        assert len(texts) == 1, path
        value = json.loads(texts[0])
    return value


def array(value):
    if isinstance(value, list):
        return value
    assert isinstance(value, dict) and all(key.isdigit() for key in value)
    return [value[key] for key in sorted(value, key=int)]


server = read(DATA / "server-inspection.json")
idle = read(DATA / "client-inspection-idle.json")
active = read(DATA / "client-inspection-active.json")
launch = read(DATA / "queue-launch-proof.json")
returned = read(DATA / "return-lobby-proof.json")
stage = read(DATA / "stage-walk-proof.json")
before = read(DATA / "before-performance.json")
after = read(DATA / "after-performance-final.json")
first_after = read(DATA / "after-performance-first-sample.json")
after_server = read(DATA / "after-server-memory.json")
bays_fix = read(DATA / "bays-runtime-fix-receipt.json")
backing_fix = read(DATA / "clutter-backing-fix-receipt.json")
final_pins = read(DATA / "final-frozen-source-hashes.json")
preparation = read(ROOT / "artifacts/lobby-polish-20261002/bays/inspection/preparation-receipt.json")
assert preparation["finalSourcePinsSHA256"] == hashlib.sha256(inputs[DATA / "final-frozen-source-hashes.json"]).hexdigest()
for row in final_pins:
    source_path = ROOT / row["file"]
    raw = source_path.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == row["sha256"], source_path

for report, context in [(server, "Server"), (idle, "Client"), (active, "Client")]:
    assert report["context"] == context and report["propertyChecksPassed"] is True
    assert not report["failures"] and report["passedCount"] == report["checkCount"]
    rows = array(report["queues"])
    assert sorted(row["id"] for row in rows) == list(range(101, 125))
    assert all(row["level"] == (row["id"] - 101) // 4 + 1 for row in rows)
    assert report["materials"]["counts"] == {"tunnel_concrete": 15, "asphalt_road": 7, "sidewalk_concrete": 26}
    assert report["materials"]["jointAtlasCount"] == 14
assert server["colliders"]["originalCount"] == 830 and server["colliders"]["extraEndBlockers"] == 66
assert idle["holograms"]["active"] == 0 and idle["holograms"]["idle"] == 24
assert active["holograms"]["active"] == 1 and active["holograms"]["idle"] == 23
active_stations = [row for row in array(active["queues"]) if row["active"]]
assert len(active_stations) == 1 and active_stations[0]["id"] == 121
active_holograms = [row for row in array(active["holograms"]["rows"]) if row["active"]]
assert len(active_holograms) == 1
bands = array(active_holograms[0]["bands"])
alphas = [row["transparency"] for row in bands]
assert len(bands) == 10 and alphas == sorted(alphas) and math.isclose(alphas[0], .74, abs_tol=.00001) and alphas[-1] == 1
assert all(math.isclose(row["height"], .6, abs_tol=.00001) for row in bands)
props = array(server["propClearance"]["rows"])
assert len(props) == 19 and all(row["renderFidelity"] == "Precise" for row in props)
assert server["propClearance"]["minimum"] > .6
themes = ["OFFICE BACKROOMS · START HERE", "POOLROOMS", "MALL BACKROOMS", "90s CINEMA · DEV ONLY", "QUIET SUBURBS", "MALL PARTY"]
for sign in array(server["signs"]):
    level = sign["level"]
    assert array(sign["header"])[0]["text"] == f"LEVEL {level}"
    assert array(sign["theme"])[0]["text"] == themes[level - 1]
    assert sign["arrow"] == {"Left": f"←  LEVEL {level}", "Right": f"LEVEL {level}  →"}
gates = {row["level"]: row for row in array(active["viewer"]["gates"])}
assert gates[5] == {"status": "COMING SOON", "level": 5, "shutter": True, "allowed": False}
assert gates[6] == {"status": "DEV PREVIEW", "level": 6, "shutter": False, "allowed": True}
vinyl = array(active["vinyl"]["rows"])
assert len(vinyl) == 2 and all(row["animationEligible"] and row["centerDrift"] == 0 for row in vinyl)
assert all(abs(row["degrees"] - row["elapsed"] * 12) < 1.8 for row in vinyl)
assert launch["health"] == 100 and launch["attributes"]["Level6PreviewActive"] is True and launch["attributes"]["Level6InRound"] is True
assert returned["health"] == 100 and returned["previewAttributeAbsent"] and returned["roundAttributeAbsent"]
assert returned["actualEHoldMilliseconds"] == 1500 and abs(returned["position"][0]) < .001 and returned["position"][2] == -860
assert stage["state"] == "Running" and stage["health"] == 100 and stage["walkSpeed"] == 16
assert bays_fix["onlyRemovedRuntimeRenderFidelityWrite"] and bays_fix["editorMatch"]
assert backing_fix["only12BackingPosesChanged"] and backing_fix["editorMatch"]
historical_pins = array(server["candidateSources"])
historical_by_path = {row["path"]: row for row in historical_pins}
source_deltas = []
for row in final_pins:
    old = historical_by_path[row["path"]]
    if old["sha256"] != row["sha256"]:
        source_deltas.append({"path": row["path"], "testedSHA256": old["sha256"], "finalSHA256": row["sha256"]})
assert len(source_deltas) == 1 and source_deltas[0]["path"].endswith(".EndBlockades")
assert source_deltas[0]["testedSHA256"] == backing_fix["beforeSHA256"] and source_deltas[0]["finalSHA256"] == backing_fix["afterSHA256"]
shop_screenshot = ROOT / "artifacts/lobby-polish-20261002/screenshots/shop-focus-tokens20.jpg"
shop_raw = shop_screenshot.read_bytes()
inputs[shop_screenshot] = shop_raw
rows = after["rows"]
performance = {
    "scope": after["scope"],
    "before": {key: before[key] for key in ["samples", "p50ms", "p95ms", "clientMemory", "serverMemoryMb"]},
    "finalAfter": {key: after[key] for key in ["samples", "elapsed", "p50ms", "p95ms", "clientMemory"]} | {"serverMemoryMb": after_server["serverMemoryMb"]},
    "p50DeltaMs": after["p50ms"] - before["p50ms"],
    "p95DeltaMs": after["p95ms"] - before["p95ms"],
    "afterEngineSamples": {key: {"minimum": min(row[key] for row in rows), "median": statistics.median(row[key] for row in rows), "maximum": max(row[key] for row in rows)} for key in ["cpuMs", "gpuMs", "renderThreadMs", "renderAverageMs", "engineAverageFPS"]},
    "firstAfterOutlierRetained": first_after,
    "firstAfterOutlierComparability": "Root reported focus/CPU state was unknown; retain the 74-frame sample but do not compare it as the settled final measurement",
    "performancePassClaimed": False,
    "interpretation": "Median frame interval was similar and p95 was 4.63ms higher in short Solo Studio samples. CPU/GPU after-samples lack matched before metrics; these records do not isolate the change's cause or establish mobile/multiplayer performance.",
}
receipt = {
    "schema": "lobby-polish-root-actual-interaction-aggregate-v1",
    "scope": "Independent disk parsing of root's actual Studio Server/Client/UI evidence, not an independent Studio invocation. Historical interaction checks used EndBlockades426; final backing-only source is5c. No publication or native-parity claim.",
    "aggregationValidation": "PASS",
    "actualPropertyInspections": [{"context": report["context"], "condition": condition, "passedChecks": report["passedCount"], "failures": report["failures"]} for report, condition in [(server, "Server"), (idle, "Idle Client"), (active, "Active Client")]],
    "queue": {"id": 121, "level": 6, "activeTitle": active_stations[0]["title"], "existingQueueSubtitle": active_stations[0]["subtitle"], "subtitleIsNotCampaignAccessProof": True, "activeStations": 1, "idleStations": 23, "bandTransparencies": alphas, "healthyDestination": {key: launch[key] for key in ["health", "position"]}, "Level6PreviewActive": True, "Level6InRound": True, "multiplayerVerified": False},
    "returnLobby": returned,
    "stageEndpoint": stage | {"scope": "Running healthy avatar observed on stage; this endpoint record alone is not a continuous stair-path trace"},
    "viewerAccess": active["viewer"],
    "vinyl": active["vinyl"],
    "furniture": {"actualCloneCount": len(props), "actualRenderFidelityCounts": {"Precise": len(props)}, "minimumDetectorClearance": server["propClearance"]["minimum"]},
    "materials": {"exactPBRMeshCounts": server["materials"]["counts"], "exactJointAtlasCount": 14, "shaderRenderingVerifiedByThisAggregate": False},
    "shop": {"cards": array(server["shop"]), "originalProductAttributesArtAndFocusCopiesPassed": True, "actualFocusScreenshot": {"path": str(shop_screenshot.relative_to(ROOT)), "sha256": hashlib.sha256(shop_raw).hexdigest(), "independentlyReadVisibleTitle": "20 Research Tokens", "independentlyReadVisiblePrice": "149 R$"}, "purchaseExecutionVerified": False},
    "signs": array(server["signs"]),
    "performance": performance,
    "sourceScope": {"historicallyTestedExpectedPins": historical_pins, "finalExpectedPins": final_pins, "finalPinsSHA256": preparation["finalSourcePinsSHA256"], "changedSinceInteractionInspections": source_deltas, "finalChangeOnly12BackingPoses": True, "finalClutterCollidersEqualHistorical": preparation["finalClutterCollidersExactlyEqualFirstInstall"], "refreshedInspectorPreparation": preparation, "finalNativeScopeAuditVerifiedByThisAggregate": False, "freshFinalInspectorExecutionVerifiedByThisAggregate": False},
    "publicationVerified": False,
    "inputs": [{"path": str(path.relative_to(ROOT)), "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()} for path, raw in inputs.items()],
}
for path, raw in inputs.items():
    assert path.read_bytes() == raw, f"Evidence changed during aggregation: {path}"
OUT.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n")
print(json.dumps({"path": str(OUT.relative_to(ROOT)), "sha256": hashlib.sha256(OUT.read_bytes()).hexdigest(), "validation": "PASS", "historicalEnd426FinalEnd5cSeparated": True, "performancePassClaimed": False}))
