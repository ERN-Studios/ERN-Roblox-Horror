"""Task-owned proposals from the exact read-only Edit captures; never writes Studio."""
from pathlib import Path
import difflib
import hashlib
import json

HERE = Path(__file__).resolve().parent


def replace_once(source, before, after):
    assert source.count(before) == 1, repr(before[:80])
    return source.replace(before, after, 1)


def main():
    l2 = (HERE / "Level2Sound.before.luau").read_bytes().decode("utf-8")
    l6 = (HERE / "Level6Client.before.luau").read_bytes().decode("utf-8")
    l2_new = l2
    for category in ("Corridor", "WetHall", "PumpPipe"):
        l2_new = replace_once(l2_new,
            f'ambientAnchorSeen[instance] = true\n\t\ttable.insert(ambientAnchors.{category}, instance)',
            f'ambientAnchorSeen[instance] = "{category}"\n\t\ttable.insert(ambientAnchors.{category}, instance)')
    l2_new = replace_once(l2_new, "local function startRandomSession(world)", '''-- Streaming removes individual anchors while the world's Model can remain.
local function forgetAmbientAnchor(instance)
\tlocal category = ambientAnchorSeen[instance]
\tif not category then return end
\tambientAnchorSeen[instance] = nil
\tlocal list = ambientAnchors[category]
\tlocal index = table.find(list, instance)
\tif index then table.remove(list, index) end
end

local function startRandomSession(world)''')
    l2_new = replace_once(l2_new,
        "\ttable.insert(ambientConnections, world.DescendantAdded:Connect(classifyAmbientAnchor))",
        "\ttable.insert(ambientConnections, world.DescendantAdded:Connect(classifyAmbientAnchor))\n"
        "\ttable.insert(ambientConnections, world.DescendantRemoving:Connect(forgetAmbientAnchor))")
    l6_new = replace_once(l6,
        'local exitLamp = {bulb = nil, base = 0, dipUntil = 0, nextDip = 0}\ntask.spawn(function()',
        '''local exitLamp = {bulb = nil, base = 0, dipUntil = 0, nextDip = 0}
-- Keep live finale baselines strong, but restore and release each removed replica.
-- Deferred removal callbacks may run after Parent is nil; the saved values still belong to that instance.
local function forgetFinaleInstance(item)
\tlocal before = litBefore[item]
\tlitBefore[item] = nil
\tif before then
\t\tpcall(function()
\t\t\titem.Color = before[1]
\t\t\tif item:IsA("Light") then item.Brightness = before[2] end
\t\t\tif item:IsA("SpotLight") then item.Angle = before[3] end
\t\tend)
\tend
\tif exitLamp.bulb == item then
\t\tlocal base = exitLamp.base
\t\texitLamp.bulb, exitLamp.base = nil, 0
\t\tpcall(function() item.Brightness = base end)
\tend
end
workspace.DescendantRemoving:Connect(forgetFinaleInstance)
task.spawn(function()''')
    l6_new = replace_once(l6_new, '''local function rigOf(child)
\tlocal rig = rigs[child]
\tif rig then return rig end
\tlocal body = child:FindFirstChild("Body")
\tif not body then return nil end''', '''local function rigOf(child)
\tlocal body = child:FindFirstChild("Body")
\tlocal rig = rigs[child]
\tif rig and rig.body == body and body.Parent == child then return rig end
\trigs[child] = nil
\tif not body then return nil end''')
    l6_new = replace_once(l6_new,
        "\trig = {bones = bones, last = {}, from = {}, fade = 1, t = 0, name = nil, serial = nil,",
        "\trig = {body = body, bones = bones, last = {}, from = {}, fade = 1, t = 0, name = nil, serial = nil,")
    baseline = json.loads((HERE / "baseline-capture.json").read_text(encoding="utf-8"))
    records = []
    for stem, original, proposed, meta in zip(("Level2Sound", "Level6Client"), (l2, l6), (l2_new, l6_new), baseline):
        raw = original.encode("utf-8")
        assert len(raw) == meta["bytes"]
        assert meta["editorOk"] and meta["parity"]
        (HERE / f"{stem}.proposed.luau").write_bytes(proposed.encode("utf-8"))
        diff = "".join(difflib.unified_diff(original.splitlines(keepends=True), proposed.splitlines(keepends=True),
            fromfile=f"{stem}.before.luau", tofile=f"{stem}.proposed.luau"))
        (HERE / f"{stem}.patch.diff").write_bytes(diff.encode("utf-8"))
        records.append({**meta, "datamodel": "Edit", "baseline": f"{stem}.before.luau",
            "baselineSha256": hashlib.sha256(raw).hexdigest(), "proposal": f"{stem}.proposed.luau",
            "proposalBytes": len(proposed.encode("utf-8")), "proposalSha256": hashlib.sha256(proposed.encode("utf-8")).hexdigest()})
    (HERE / "proposal-manifest.json").write_text(json.dumps({"studioId":"1b603e69-7ae1-4572-b210-d5bf05c684ff", "records":records}, indent=2)+"\n", encoding="utf-8")
    relative = "tools/optimization_20261009/loading/install/compatibility/"
    install = {"status":"Fresh Edit prepared; read-only task; root owns source CAS installation",
        "placeId":131311258779917, "universeId":10559217407, "scripts":[{
            "segments":record["path"].split("."), "class":record["class"],
            "baselineInstanceId":record["instanceId"],
            "beforeFile":relative+record["baseline"], "beforeSha256":record["baselineSha256"], "beforeBytes":record["bytes"],
            "afterFile":relative+record["proposal"], "afterSha256":record["proposalSha256"], "afterBytes":record["proposalBytes"]
        } for record in records]}
    (HERE / "source-install-manifest.json").write_text(json.dumps(install, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
