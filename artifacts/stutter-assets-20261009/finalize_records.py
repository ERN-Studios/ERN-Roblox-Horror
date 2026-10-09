"""Finalize the task report from verified install/runtime/publication receipts."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
report = HERE / "results.md"
before = report.read_bytes()
text = before.decode("utf-8")
publication = json.loads((HERE / "publication.json").read_bytes())
assert publication["published"] is True and publication["publishedVersion"] == 2910
client = json.loads((HERE / "runtime-level1-client.json").read_bytes())
lobby = json.loads((HERE / "runtime-lobby.json").read_bytes())
server = json.loads((HERE / "runtime-level1-server.json").read_bytes())
probe = json.loads((HERE / "native-candidate-probes.json").read_bytes())
assert client["atomicRooms"] == 1600 and client["nearbyVisibleRoofMeshes"] > 0
assert server["active"] and server["loadingState"] == "ready"
head = text.index("## Exact source scope")
text = """# Lobby and in-game stutter / asset loading — 2026-10-09

Five scoped loading, scheduling and room-streaming fixes were verified in authoritative Studio and published to place **131311258779917**, universe **10559217407**, as version **2910**. Roblox Studio reported a successful publish; see [publication.json](publication.json). This establishes publication of the current Studio place, not resolution of every player-reported stutter or a published-client device pass.

""" + text[head:]
text = text.replace("cc4583a7bd4d5e2b7524b47c85b673a874da39430e7557c7f7fbb33dbb960881", "872b9ed13fdc0e21332a844a6931b5ba2796a1ffd659a45f6cf0d5d945049583")
text = text.replace("A further change to preserve the original preload pool's parallelism is pending. The loading hashes above describe the verified Opaque-content installs; they are not evidence of installing or testing that pending pool revision.",
 "The initial lobby preload preserves parallel requests with a four-worker pool under one owner. Retry/skip stops new claims, rejects stale results, and retains the busy lock until every old engine request drains. Background and entry preloads remain sequential. [Pool install](lobby-bounded-pool-native-install.json). This avoids serializing the original parallel loader; it is not a controlled performance-gain claim.")
text = text.replace("85 round-entry checks and 41 lobby-region checks", "85 round-entry checks and 100 lobby-region checks")
text = text.replace("Nine deliberate regressions", "Twelve deliberate regressions")
text = text.replace("52 cloned parts", f"{probe['renderer']['clonedParts']} cloned parts")
text = text.replace("this draft has no", "this report has no")
text = text.replace("90 nearby visible roof meshes", f"{client['nearbyVisibleRoofMeshes']} nearby visible roof meshes")
start = text.index("The focused Level 1 client sample")
end = text.index("## Optional Level 6 audio", start)
text = text[:start] + f"""The final lobby reported **17.3 seconds, 87 remote assets, zero failures**. Its five-second sample averaged {lobby['frameSample']['meanMs']:.2f} ms, with p95 {lobby['frameSample']['p95Ms']:.2f} ms. Level 1 averaged {client['frameSample']['meanMs']:.2f} ms, p95 {client['frameSample']['p95Ms']:.2f} ms, with one frame over 50 ms. [Console evidence](runtime-console.json). Earlier runs varied with Studio's 15 FPS background throttle, and the Assistant tool reported camera restoration during timed probes. These are instrumented warm Studio observations, not a controlled before/after or normal player camera/rendering pass.

The final active server sample recorded heartbeat {min(s['heartbeatMs'] for s in server['samples']):.2f}–{max(s['heartbeatMs'] for s in server['samples']):.2f} ms, physics {min(s['physicsMs'] for s in server['samples']):.2f}–{max(s['physicsMs'] for s in server['samples']):.2f} ms and combined Studio process memory around {server['samples'][0]['memoryMB']:.0f} MB. Studio memory includes editor, server and client. Cold-cache downloads, low-memory/mobile devices, multiplayer, Level 2–6 gameplay, actual Level 6 chase audio and native failed-entry deadline recovery were not verified. `PreloadAsync` and fetch status cannot establish processed PBR packs, mip residency or GPU readiness.

""" + text[end:]
start = text.index("## Remaining task-owner evidence")
text = text[:start] + """## Final preservation and publication

[verified-scope.json](verified-scope.json) records post-publication matching native Source/editor, canonical mirror and scoped manifest hashes for all five scripts, with exact classes, properties and attributes. The install receipts retain their historical `published: false` state; the later publication receipt is authoritative for publication. Studio's loaded `PlaceVersion` remained 2859 while Output identified the newly published version as **2910**. No server restart, access-setting change or GitHub push was performed.

Play was stopped and no StutterAssets probe objects remained. Temporary ModuleScripts/non-script clones were destroyed; borrowed renderer attributes were restored; the task's MicroProfiler capture was disabled. Only the five source mirrors, their manifest rows and explicit task evidence/tools belong to this commit. An alternate index keeps other developers' staged/dirty files and the unrelated RoundUI manifest row out of the task commit. Recoverable source/index checkpoints remain under `.git/stutter-assets-20261009`. The local commit ID is recorded in the final task reply.
"""
assert report.read_bytes() == before, "Report changed concurrently"
report.write_bytes(text.encode("utf-8"))
print("Final report updated from verified receipts")
