from pathlib import Path
import difflib, hashlib, json

ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent / 'baseline' / 'sources'
FILES = [
    'ServerScriptService/GameManager.Script.lua',
    'ServerScriptService/Level 5 Systems/Level 5 Round Adapter.ModuleScript.lua',
    'ServerScriptService/Level 5 Systems/Level 5 Window Watcher Encounters.ModuleScript.lua',
]

def replace_once(text, old, new):
    assert text.count(old) == 1, old[:140]
    return text.replace(old, new, 1)

originals = {name: (BASE/name).read_text() for name in FILES}
drafts = dict(originals)
name = FILES[0]
s = drafts[name]
s = replace_once(s, '''-- LEVEL5_MAP_PREVIEW_20260923. A ceiling is only a transport bound. Access
-- is checked against the REQUESTED level too, so enabling 5 cannot enable 4.
''', '''-- Level 5 is a selectable public preview, separate from campaign progression.
-- A ceiling is only a transport bound: canAccessLevel still checks the exact
-- requested level, so opening 5 never opens the developer-only Level 4.
-- Explicit false keeps public entry closed while preserving developer access.
if workspace:GetAttribute("Level5PublicPreviewEnabled") == nil then
 workspace:SetAttribute("Level5PublicPreviewEnabled", true)
end
''')
s = replace_once(s, '''local function devCeiling(group)
 if type(group) ~= "table" or #group == 0 then return Routing.MaxLevel end
''', '''local function devCeiling(group)
 if type(group) ~= "table" or #group == 0 then return Routing.MaxLevel end
 if workspace:GetAttribute("Level5PublicPreviewEnabled") == true then return 5 end
''')
s = replace_once(s, ''' if not level or level ~= level then return false end
 if level <= Routing.MaxLevel then return true end
''', ''' if not level or level ~= level or level % 1 ~= 0 or level < 1 then return false end
 if level <= Routing.MaxLevel then return true end
 if level == 5 and workspace:GetAttribute("Level5PublicPreviewEnabled") == true then
  return type(group) == "table" and #group > 0
 end
''')
s = replace_once(s, ''' -- LEVEL4_DEV_GATE_20260921: ClampLevelTo with the dev ceiling. For every
 -- normal party devCeiling() returns Routing.MaxLevel, so this is exactly the
 -- old Routing.ClampLevel(requestedLevel).
''', ''' -- Access was checked for this exact level. The transport ceiling also
 -- includes the standalone public preview without changing the campaign.
''')
s = replace_once(s, '''  -- LEVEL4_DEV_GATE_20260921: clamped AFTER the roster is known, because the
  -- dev ceiling requires every arriving member to pass DevAccess. For a normal
  -- party this is exactly the old Routing.ClampLevel(group.Level).
''', '''  -- Check the exact destination after the whole roster arrives. The public
  -- Level 5 preview is independent of Level 4's entire-party developer check.
''')
drafts[name] = s

name = FILES[1]
s = drafts[name]
s = replace_once(s, '-- Level 5 map-only preview lifecycle. Independent of Level 4 and its gameplay.', '-- Level 5 playable preview lifecycle. Independent of Level 4 and campaign completion.')
s = replace_once(s, '''function Adapter.Build()
\tassert(workspace:GetAttribute("Level5DevEnabled") == true, "Level 5 map preview is developer-only")
\tfor _, player in ipairs(Players:GetPlayers()) do
\t\tassert(DevAccess.IsAllowed(player), "Level 5 preview refuses a non-developer roster")
\tend
''', '''function Adapter.Build()
\tif workspace:GetAttribute("Level5PublicPreviewEnabled") ~= true then
\t\tassert(workspace:GetAttribute("Level5DevEnabled") == true, "Level 5 preview is currently closed")
\t\tfor _, player in ipairs(Players:GetPlayers()) do
\t\t\tassert(DevAccess.IsAllowed(player), "Level 5 private preview requires a developer roster")
\t\tend
\tend
''')
s = replace_once(s, '\t\t\t"End the existing level before starting the Level 5 map preview")', '\t\t\t"End the existing level before starting the Level 5 preview")')
notice = '''-- These two owned signs describe the current preview boundary. They do not
-- complete the round, award a clear, or invoke any transfer; the existing
-- BACK TO LOBBY control remains the player's way out.
local function addPreviewNotices(world: Model, built: any)
\tlocal notices = Instance.new("Folder")
\tnotices.Name = "Level5PreviewNotices"
\tnotices:SetAttribute(OWNED, true)
\tnotices.Parent = world
\tlocal function sign(name: string, frame: CFrame, text: string)
\t\tlocal board = Instance.new("Part")
\t\tboard.Name, board.Size, board.CFrame = name, Vector3.new(6.6, 3.6, 0.1), frame
\t\tboard.Anchored, board.CanCollide, board.CanTouch, board.CanQuery = true, false, false, false
\t\tboard.CastShadow = false
\t\tboard.Color, board.Material = Color3.fromRGB(49, 44, 35), Enum.Material.Wood
\t\tboard:SetAttribute(OWNED, true)
\t\tboard.Parent = notices
\t\tlocal gui = Instance.new("SurfaceGui")
\t\tgui.Name, gui.Face = "PreviewInformation", Enum.NormalId.Front
\t\tgui.CanvasSize, gui.LightInfluence, gui.AlwaysOnTop = Vector2.new(880, 480), 0, false
\t\tgui.MaxDistance = 55
\t\tgui.Parent = board
\t\tlocal label = Instance.new("TextLabel")
\t\tlabel.Position, label.Size = UDim2.fromScale(.06, .06), UDim2.fromScale(.88, .88)
\t\tlabel.BackgroundTransparency = 1
\t\tlabel.Font, label.TextColor3 = Enum.Font.GothamMedium, Color3.fromRGB(236, 226, 194)
\t\tlabel.TextSize, label.TextWrapped, label.Text = 35, true, text
\t\tlabel.Parent = gui
\tend
\tlocal entry = built.SpawnCFrame.Position
\tsign("PreviewArrival", CFrame.lookAt(entry + Vector3.new(8, 2, 7), entry + Vector3.new(0, 2, 0)),
\t\t"LEVEL 5 · PLAYABLE PREVIEW\\n\\nSeven puzzles lead through eight sections. The final slide and ending are still in development.\\n\\nUse the lobby control to leave at any time.")
\tassert(typeof(built.ChuteEnd) == "CFrame", "Preview ending needs the authored descent endpoint")
\tlocal ending = built.ChuteEnd.Position
\tsign("PreviewEnding", CFrame.lookAt(ending + Vector3.new(0, 4.5, 8.45), ending + Vector3.new(0, 4.5, 0)),
\t\t"END OF THE CURRENT PREVIEW\\n\\nThe final slide and ending are still in development.\\n\\nUse the lobby control to return.")
end

'''
s = replace_once(s, 'function Adapter.Build()\n', notice + 'function Adapter.Build()\n')
s = replace_once(s, '\t\tmanifest.World, manifest.Origin = world, ORIGIN\n', '\t\tmanifest.World, manifest.Origin = world, ORIGIN\n\t\taddPreviewNotices(world, manifest)\n')
drafts[name] = s

name = FILES[2]
s = drafts[name]
s = replace_once(s, '-- Start only from the existing developer-only Level 5 round adapter.', '-- Start only from the enabled public/developer Level 5 preview round adapter.')
s = replace_once(s, 'local function finite(value)\n', '''local function previewEnabled()
\treturn workspace:GetAttribute("Level5PublicPreviewEnabled")==true
\t\tor workspace:GetAttribute("Level5DevEnabled")==true
end

local function finite(value)
''')
s = replace_once(s, 'or workspace:GetAttribute("Level5DevEnabled")~=true or not world:IsDescendantOf(workspace) then', 'or not previewEnabled() or not world:IsDescendantOf(workspace) then')
s = replace_once(s, 'requires the enabled Level 5 developer map preview in Workspace', 'requires an enabled Level 5 preview in Workspace')
s = replace_once(s, 'if workspace:GetAttribute("Level5DevEnabled")~=true then cleanup(false);return end', 'if not previewEnabled() then cleanup(false);return end')
drafts[name] = s

index=[]
diff=[]
for name in FILES:
    original, draft = originals[name], drafts[name]
    path = ROOT/'sources'/name
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(draft)
    index.append({'file':name,'baselineSha256':hashlib.sha256(original.encode()).hexdigest(),'draftSha256':hashlib.sha256(draft.encode()).hexdigest()})
    diff.extend(difflib.unified_diff(original.splitlines(keepends=True),draft.splitlines(keepends=True),fromfile='baseline/'+name,tofile='draft/'+name))
(ROOT/'access.patch').write_text(''.join(diff))
(ROOT/'manifest.json').write_text(json.dumps(index,indent=2)+'\n')
print(f'Prepared {len(index)} script drafts. No repository or Studio writes.')
