"""Create ReplicatedStorage.Level5Void.Sounds from sound_ids.json (the ids of assets/level5-void-20261004/*.mp3
after Asset Manager > Import). Level5PreviewAccess and the Level 5 Lighting Controller clone from that folder."""
import json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io
ids = json.loads((Path(__file__).parent / 'sound_ids.json').read_text())
print(studio_io.Studio().luau('''
local ids = game:GetService("HttpService"):JSONDecode([==[%s]==])
local RS = game:GetService("ReplicatedStorage")
local folder = RS:FindFirstChild("Level5Void") or Instance.new("Folder")
folder.Name = "Level5Void"
folder.Parent = RS
local old = folder:FindFirstChild("Sounds")
if old then old:Destroy() end
local sounds = Instance.new("Folder")
sounds.Name = "Sounds"
local n = 0
for name, id in pairs(ids) do
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. string.format("%%.0f", id)
	sound.Volume = 0.4
	sound.Parent = sounds
	n += 1
end
sounds.Parent = folder
return n .. " sounds installed"
''' % json.dumps(ids)))
