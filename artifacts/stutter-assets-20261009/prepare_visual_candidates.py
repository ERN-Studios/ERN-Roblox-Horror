"""Scoped candidates from the fresh Studio capture, never from runtime mirrors."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "visual-candidates"
OUT.mkdir(exist_ok=True)


def change(folder, name, replacements):
    capture = ROOT / ".git/stutter-assets-20261009" / folder / name
    baseline = OUT.parent / "visual-baselines" / folder / name
    if capture.exists():
        baseline.parent.mkdir(parents=True, exist_ok=True)
        baseline.write_bytes(capture.read_bytes())
        (baseline.parent / "sources.json").write_bytes((capture.parent / "sources.json").read_bytes())
    raw = baseline.read_bytes()
    source = raw.decode("utf-8").replace("\r\n", "\n")
    for before, after in replacements:
        assert source.count(before) == 1, (name, before)
        source = source.replace(before, after)
    candidate = OUT / name
    candidate.write_bytes(source.encode("utf-8"))
    metadata = json.loads((baseline.parent / "sources.json").read_text(encoding="utf-8"))
    row = next(row for row in metadata if Path(row["sourceFile"]).name == name)
    assert hashlib.sha256(raw).hexdigest() == row["sha256"], "fresh capture hash differs"
    return {"path": row["path"], "class": row["class"], "placeVersion": row["placeVersion"],
            "baselineFile": str(baseline.relative_to(ROOT)), "baselineSha256": row["sha256"],
            "candidateFile": str(candidate.relative_to(ROOT)),
            "candidateSha256": hashlib.sha256(candidate.read_bytes()).hexdigest()}


rows = []
rows.append(change("visuals-refreshed", "StarterPlayer__StarterPlayerScripts__Shop Display Client.luau", [
    ("local elapsed = 0\nRunService.Heartbeat:Connect(function(delta)\n\telapsed += delta\n",
     "local elapsed, scanElapsed = 0, 0.5\nRunService.Heartbeat:Connect(function(delta)\n\telapsed += delta\n"
     "\tif player:GetAttribute(\"InRound\") == true or workspace:GetAttribute(\"RoundActive\") == true then\n"
     "\t\tif animating then restoreMotion() end\n\t\tscanElapsed = 0.5\n\t\treturn\n\tend\n\tscanElapsed += delta\n"),
    ("\t\tcollect(shopModel)\n\tend\n\t-- Replication hands", "\t\tcollect(shopModel)\n\t\tscanElapsed = 0\n\tend\n\t-- Replication hands"),
    ("\tif shopModel and #boxes < (tonumber(shopModel:GetAttribute(\"ShopItemCount\")) or 0) then\n\t\tcollect(shopModel)\n\tend",
     "\t-- Streamed-out boxes may stay absent; retry at most twice a second.\n"
     "\tif scanElapsed >= 0.5 and shopModel and #boxes < (tonumber(shopModel:GetAttribute(\"ShopItemCount\")) or 0) then\n"
     "\t\tcollect(shopModel)\n\t\tscanElapsed = 0\n\tend"),
]))
rows.append(change("visuals-refreshed", "StarterPlayer__StarterPlayerScripts__Lobby DJ Client.luau", [
    ("local function tracks()\n\tlocal ok, list = pcall(function() return HttpService:JSONDecode(workspace:GetAttribute(\"LobbyDJTracks\")) end)\n\treturn ok and type(list) == \"table\" and list or {}\nend",
     "local trackJson, trackList = nil, {}\nlocal function tracks()\n"
     "\tlocal raw = workspace:GetAttribute(\"LobbyDJTracks\")\n\tif raw ~= trackJson then\n"
     "\t\ttrackJson = raw\n\t\tlocal ok, list = pcall(function() return HttpService:JSONDecode(raw) end)\n"
     "\t\ttrackList = ok and type(list) == \"table\" and list or {}\n\tend\n\treturn trackList\nend"),
    ("\t\tlocal entry = tracks()[workspace:GetAttribute(\"LobbyDJTrack\") or 0]\n\t\tlocal on = entry ~= nil and workspace:GetAttribute(\"ReservedRoundServer\") ~= true and player:GetAttribute(\"InRound\") ~= true",
     "\t\tif workspace:GetAttribute(\"ReservedRoundServer\") == true or player:GetAttribute(\"InRound\") == true then\n"
     "\t\t\tif active then active = false; restore() end\n\t\t\treturn\n\t\tend\n"
     "\t\tlocal entry = tracks()[workspace:GetAttribute(\"LobbyDJTrack\") or 0]\n\t\tlocal on = entry ~= nil"),
]))
rows.append(change("visuals-refreshed", "ServerScriptService__Level 1 Systems__BlenderRoomRenderer.luau", [
    ("\t\t\t\tlocal room = Renderer.PickRoom(choices, math.random()):Clone()",
     "\t\t\t\tlocal room = Renderer.PickRoom(choices, math.random()):Clone()\n"
     "\t\t\t\troom.ModelStreamingMode = Enum.ModelStreamingMode.Atomic"),
]))
(OUT / "manifest.json").write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
print("Prepared 3 scoped visual candidates from verified fresh capture hashes")
