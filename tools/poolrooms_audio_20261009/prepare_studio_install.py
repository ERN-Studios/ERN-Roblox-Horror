#!/usr/bin/env python3
"""Prepare a compare-and-swap Studio command for the reviewed Poolrooms audio pack.

Reads task files only. Does not connect to Studio, upload, publish or overwrite
repository sources. Run the emitted command only in the owner-identified Edit
place after taking a fresh native backup and rereading the target/editor source.
"""
import argparse, hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
asset = ROOT / "assets/poolrooms-audio-20261009"
plan = json.loads((asset / "plan.json").read_text())
ids = json.loads((asset / "sound_ids.json").read_text())
qc = json.loads((asset / "qc.json").read_text())
assert all(v["numeric_pass"] for v in qc["sounds"].values()), "Audio QC has a material blocker"
names = sorted(qc["sounds"])
assert set(names) == set(ids), "Asset keys mismatch"
for key in names:
    assert str(ids[key]["asset_id"]).isdigit() and ids[key]["asset_fetch_status"] == "Success"
    assert ids[key]["master_sha256"] == hashlib.sha256((asset / "masters" / (key + ".ogg")).read_bytes()).hexdigest()
before = (ROOT / "artifacts/poolrooms-audio-20261009/baseline/Level 2 Sound Controller.LocalScript.lua").read_text()
legacy = (ROOT / "StarterPlayer/StarterPlayerScripts/Level 2 Sound Controller.LocalScript.lua").read_text()
new = (ROOT / "StarterPlayer/StarterPlayerScripts/Level 2 Poolrooms Ambience.LocalScript.lua").read_text()
payload = {"before": before, "legacy": legacy, "new": new, "plan": json.dumps(plan, separators=(",", ":")), "sounds": ids}
encoded = json.dumps(payload, ensure_ascii=False)
# JSON is decoded from a Luau long string; choose a delimiter absent from data.
marks = "="
while "]" + marks + "]" in encoded:
    marks += "="
blob = "[" + marks + "[" + encoded + "]" + marks + "]"
code = """assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong place")
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
local h = game:GetService("HttpService")
local e = game:GetService("ScriptEditorService")
local p = h:JSONDecode(PAYLOAD)
local scripts = game.StarterPlayer.StarterPlayerScripts
local target = assert(scripts:FindFirstChild("Level 2 Sound Controller"), "Missing exact target")
assert(target:IsA("LocalScript"), "Wrong class")
assert(target.Source == p.before and e:GetEditorSource(target) == p.before, "Fresh Source/editor baseline changed; reread live")
assert(not scripts:FindFirstChild("Level 2 Poolrooms Ambience"), "New controller now exists; reread it")
assert(not game.ReplicatedStorage:FindFirstChild("Level2Poolrooms"), "Audio pack now exists; reconcile it")
local template = assert(game.ServerStorage:FindFirstChild("Level2PoolroomsMap"), "Missing promoted map")
assert(template:GetAttribute("Level2NewMap") == true and template:GetAttribute("PromotionRevision") == "live20261009", "Map changed; reread it")
local function checkDestinations()
    assert(scripts == game.StarterPlayer:FindFirstChild("StarterPlayerScripts"), "Script container changed; reread it")
    assert(target == scripts:FindFirstChild("Level 2 Sound Controller"), "Target identity changed; reread it")
    assert(not scripts:FindFirstChild("Level 2 Poolrooms Ambience"), "Concurrent new controller detected")
    assert(not game.ReplicatedStorage:FindFirstChild("Level2Poolrooms"), "Concurrent audio bank detected")
    assert(template == game.ServerStorage:FindFirstChild("Level2PoolroomsMap")
        and template:GetAttribute("Level2NewMap") == true
        and template:GetAttribute("PromotionRevision") == "live20261009", "Concurrent map change detected")
end
-- Build the small reviewed audio bank off-tree. No map objects are changed.
local bank = Instance.new("Folder")
bank.Name = "Level2Poolrooms"
bank:SetAttribute("AudioRevision", "poolrooms-audio-20261009-v1")
bank:SetAttribute("Provider", "ElevenLabs")
local plan = Instance.new("StringValue")
plan.Name, plan.Value, plan.Parent = "Plan", p.plan, bank
local sounds = Instance.new("Folder")
sounds.Name, sounds.Parent = "Sounds", bank
for key, row in pairs(p.sounds) do
    local sound = Instance.new("Sound")
    sound.Name, sound.SoundId, sound.Volume = key, "rbxassetid://" .. tostring(row.asset_id), 0
    sound.Looped = key:match("^bed_") ~= nil or key:match("^loop_") ~= nil
    sound:SetAttribute("MasterSHA256", row.master_sha256)
    sound:SetAttribute("Provider", "ElevenLabs")
    sound.Parent = sounds
end
local client = Instance.new("LocalScript")
client.Name, client.Source = "Level 2 Poolrooms Ambience", p.new
-- Compare again inside the actual write callback; never import an old repo mirror.
e:UpdateSourceAsync(target, function(current)
    checkDestinations()
    assert(target.Parent == scripts and target.Source == p.before and current == p.before, "Concurrent live edit detected")
    return p.legacy
end)
assert(target.Source == p.legacy and e:GetEditorSource(target) == p.legacy, "Source/editor write parity failed")
checkDestinations()
bank.Parent = game.ReplicatedStorage
client.Parent = scripts
assert(client.Source == p.new and e:GetEditorSource(client) == p.new, "New script parity failed")
return h:JSONEncode({placeId=game.PlaceId, version=game.PlaceVersion, revision=bank:GetAttribute("AudioRevision"), templates=#sounds:GetChildren(), scripts=2})
"""
args.output.write_text(code.replace("PAYLOAD", blob))
print(args.output)
