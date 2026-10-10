"""Put plan v3 and its new sounds into ReplicatedStorage.Level2Poolrooms (Studio in Edit mode).

    python3 tools/poolrooms_audio_20261010/install.py --dry     # say what would change
    python3 tools/poolrooms_audio_20261010/install.py

The 2026-10-09 installer builds the bank from nothing and refuses to run twice; this one UPDATES it and can be run again:
- every key the plan uses gets a Sound template under Level2Poolrooms.Sounds (Name = key, SoundId, Volume 0, Looped for
  bed_/loop_ keys, attribute MasterSHA256); templates of keys the plan no longer uses are left in place;
- Plan.Value is swapped to the minified plan only when it still holds what this tool last saw there (the v2 text, or an
  earlier v3 written by this tool): somebody else's edit stops it;
- AudioRevision takes the plan's revision.
It refuses a plan that names a key with no asset id, and it does not touch any script. Push the client separately
(tools/mac_merge_push.py) BEFORE this: the old client refuses any plan with more than nine keys and falls back to the
legacy ambience.
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
from import_to_studio import Studio   # noqa: E402

OLD = ROOT / 'assets' / 'poolrooms-audio-20261009'
NEW = ROOT / 'assets' / 'poolrooms-audio-20261010'

LUAU = '''
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
assert(game.PlaceId == 131311258779917, "wrong place")
local HttpService = game:GetService("HttpService")
local SPEC = HttpService:JSONDecode([==[%s]==])
local DRY = %s
local bank = game:GetService("ReplicatedStorage"):FindFirstChild("Level2Poolrooms")
assert(bank and bank:IsA("Folder"), "ReplicatedStorage.Level2Poolrooms is missing")
local sounds, planValue = bank:FindFirstChild("Sounds"), bank:FindFirstChild("Plan")
assert(sounds and planValue and planValue:IsA("StringValue"), "the bank has no Sounds folder or Plan value")
local function digest(text)
	local sum, roll = 0, 0
	for i = 1, #text do local ch = string.byte(text, i); sum += ch; roll = (roll * 31 + ch) %% 4294967291 end
	return #text .. ":" .. sum .. ":" .. roll
end
local now = digest(planValue.Value)
local known = false
for _, accepted in ipairs(SPEC.accepted) do if accepted == now then known = true end end
assert(known or now == SPEC.planDigest, "Plan.Value is not a text this tool knows (" .. now .. "): somebody else changed it")
local added, changed, kept = {}, {}, 0
for key, row in pairs(SPEC.sounds) do
	local id = "rbxassetid://" .. row.id
	local sound = sounds:FindFirstChild(key)
	if sound and not sound:IsA("Sound") then error("Sounds." .. key .. " is not a Sound") end
	if not sound then
		table.insert(added, key)
		if not DRY then
			sound = Instance.new("Sound")
			sound.Name, sound.Volume = key, 0
			sound.Looped = key:match("^bed_") ~= nil or key:match("^loop_") ~= nil
			sound.SoundId = id
			sound:SetAttribute("MasterSHA256", row.sha)
			sound:SetAttribute("Provider", "ElevenLabs")
			sound.Parent = sounds
		end
	elseif sound.SoundId ~= id then
		table.insert(changed, key)
		if not DRY then
			sound.SoundId = id
			sound:SetAttribute("MasterSHA256", row.sha)
		end
	else
		kept += 1
	end
end
table.sort(added); table.sort(changed)
local swap = now ~= SPEC.planDigest
if not DRY then
	if swap then planValue.Value = SPEC.plan end
	assert(digest(planValue.Value) == SPEC.planDigest, "Plan.Value did not take the new text")
	bank:SetAttribute("AudioRevision", SPEC.revision)
end
return string.format("%%s: %%d templates added, %%d re-pointed, %%d unchanged; plan %%s (%%d -> %%d characters); revision %%s; bank holds %%d sounds\\nadded: %%s",
	DRY and "DRY RUN" or "INSTALLED", #added, #changed, kept, swap and "swapped" or "already current", #planValue.Value, #SPEC.plan,
	SPEC.revision, #sounds:GetChildren(), table.concat(added, " "))
'''


def digest(text):
    data = text.encode()
    roll = 0
    for ch in data:
        roll = (roll * 31 + ch) % 4294967291
    return f'{len(data)}:{sum(data)}:{roll}'


def main():
    dry = '--dry' in sys.argv
    plan = json.loads((NEW / 'plan.json').read_text())
    text = json.dumps(plan, separators=(',', ':'))
    ids = json.loads((NEW / 'sound_ids.json').read_text())
    old_ids = json.loads((OLD / 'sound_ids.json').read_text())
    sounds = {}
    for group in ('beds', 'loops', 'shots'):
        for row in plan[group]:
            key = row['key']
            if key in ids:
                assert ids[key].get('moderation') == 'Approved', f'{key}: asset {ids[key]["asset_id"]} is not approved yet ({ids[key].get("moderation")})'
                sounds[key] = {'id': str(ids[key]['asset_id']), 'sha': ids[key]['master_sha256']}
            else:
                assert key in old_ids, f'{key}: no asset id'
                sounds[key] = {'id': str(old_ids[key]['asset_id']), 'sha': old_ids[key]['master_sha256']}
    accepted = [digest(json.dumps(json.loads((OLD / 'plan.json').read_text()), separators=(',', ':')))]
    seen = NEW / 'installed-plan-digests.json'
    if seen.exists():
        accepted += json.loads(seen.read_text())
    spec = {'plan': text, 'planDigest': digest(text), 'accepted': accepted, 'revision': plan['revision'], 'sounds': sounds}
    answer = Studio().luau(LUAU % (json.dumps(spec), 'true' if dry else 'false'))
    print(answer)
    if not dry and answer.startswith('INSTALLED'):
        seen.write_text(json.dumps(sorted(set(accepted + [digest(text)])), indent=1) + '\n')


if __name__ == '__main__':
    main()
