from pathlib import Path
import hashlib,json,difflib
r=Path(__file__).resolve().parent
fresh=json.loads((r/'live-baseline.json').read_text())
assert fresh['placeId']==131311258779917 and fresh['universeId']==10559217407
rows=[]
def source(name):
 p=Path('ServerScriptService/Level 3 Systems')/(name+'.ModuleScript.lua')
 b=p.read_text();record=next(x for x in fresh['sources'] if x['path'].endswith('.'+name))
 assert record['editorMatch'] and hashlib.sha256(b.encode()).hexdigest()==record['sourceHash']==record['editorHash']
 return b,record
def edit(text,old,new):
 assert text.count(old)==1,old[:120]
 return text.replace(old,new)
def save(name,b,c,record):
 p=r/(name+'.v2.candidate.luau');p.write_text(c)
 (r/(name+'.v2.diff')).write_text(''.join(difflib.unified_diff(b.splitlines(True),c.splitlines(True),fromfile='fresh live '+record['path'],tofile='scoped candidate '+name)))
 rows.append({'path':record['path'],'class':record['class'],'new':False,'baselineSHA256':record['sourceHash'],'editorSHA256':record['editorHash'],'candidateSHA256':hashlib.sha256(c.encode()).hexdigest(),'candidateFile':str(p)})

name='Level 3 Objective Controller';b,record=source(name);c=b
c=edit(c,'local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))','local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))\nlocal MallManagerController = require(script.Parent:WaitForChild("Level 3 Mall Manager AI Controller"))')
c=edit(c,'if not session.ExitUnlocked or session.FinalHallChaseTriggered\n\t\tor session.State:GetAttribute("Level3_RoomSongPhase") ~= "DONE" then','if not session.ExitUnlocked\n\t\tor session.State:GetAttribute("Level3_RoomSongPhase") ~= "DONE" then')
c=edit(c,'\t\t\tlocal character, _, root = livingCharacter(player)\n\t\t\tif character and root then\n\t\t\t\teligibleCount += 1\n\t\t\t\tif session.FinalHallCrossed[player] ~= character then',
'''\t\t\tlocal character = player.Character
\t\t\tlocal humanoid = character and character:FindFirstChildOfClass("Humanoid")
\t\t\tlocal root = character and character:FindFirstChild("HumanoidRootPart")
\t\t\t-- A live life still owns a barrier slot while its position is unavailable.
\t\t\tif character and character.Parent and humanoid and humanoid.Health > 0 then
\t\t\t\teligibleCount += 1
\t\t\t\tif session.FinalHallCrossed[player] ~= character then
\t\t\t\t\tcharacter:SetAttribute("Level3_FinalHallCrossedGeneration", nil)
\t\t\t\tend
\t\t\t\tif root and root:IsA("BasePart") and session.FinalHallCrossed[player] ~= character then''')
c=edit(c,'\t\t\t\t\t-- The first living survivor must pass strictly beyond 50% of this hall.','\t\t\t\t\t-- Every living survivor must pass strictly beyond 50% of this hall.')
c=edit(c,'local entryProgress = hall.Length * (hall.HalfwayProgress\n\t\t\t\t\t\tor Configuration.Layout.FinalHallHalfwayProgress or .50)','local entryProgress = hall.Length * .50')
c=edit(c,'\t\t\t\t\t\tsession.FinalHallCrossed[player] = character','\t\t\t\t\t\tsession.FinalHallCrossed[player] = character\n\t\t\t\t\t\tcharacter:SetAttribute("Level3_FinalHallCrossedGeneration", session.Generation)')
c=edit(c,'\tif eligibleCount == 0 or crossedCount == 0 then return end\n\n\tsession.FinalHallChaseTriggered = true',
'''\tif session.FinalHallChaseTriggered or eligibleCount == 0 or crossedCount ~= eligibleCount then return end

\t-- Attribute callbacks may be deferred. Stop the owned normal rig directly,
\t-- then issue a fresh hunt edge so the adapter cannot reuse a nearby Manager.
\tworkspace:SetAttribute("Level3MallManagerHuntActive", false)
\tMallManagerController.Stop()
\tsession.FinalHallChaseTriggered = true''')
c=edit(c,'\tlocal exitPosition = session.Manifest.ExitPosition\n\tlocal insertedCount =',
'''\tlocal exitPosition = session.Manifest.ExitPosition
\tlocal playerPosition = session.DiscPlayer and session.DiscPlayer.Position
\tsession.State:SetAttribute("Level3_CDPlayerPosition", playerPosition)
\tworkspace:SetAttribute("Level3CDPlayerPosition", playerPosition)
\tlocal insertedCount =''')
c=edit(c,'\t\tdropHeldCDs(session, player, if root and root:IsA("BasePart") then root.Position else nil)',
'''\t\tsession.FinalHallCrossed[player] = nil
\t\tcharacter:SetAttribute("Level3_FinalHallCrossedGeneration", nil)
\t\tdropHeldCDs(session, player, if root and root:IsA("BasePart") then root.Position else nil)''')
c=edit(c,'discPlayer.StatusLabel.Text = string.format("BIRTHDAY CD PLAYER  %d/%d", insertedCount, session.ModuleGoal)',
'''discPlayer.StatusLabel.Text = if insertedCount >= session.ModuleGoal
\t\t\tthen "SIGNAL RESTORED" else "AWAITING DISCS"''')
c=edit(c,'\tif discPlayer.InstructionLabel and discPlayer.InstructionLabel.Parent then',
'''\tif discPlayer.ProgressLabel and discPlayer.ProgressLabel.Parent then
\t\tdiscPlayer.ProgressLabel.Text = string.format("%d / %d CDS", insertedCount, session.ModuleGoal)
\tend
\tfor index, screenSlot in ipairs(discPlayer.ScreenSlots or {}) do
\t\tif screenSlot and screenSlot.Parent then
\t\t\tscreenSlot.BackgroundColor3 = index <= insertedCount
\t\t\t\tand Color3.fromRGB(56, 255, 176) or Color3.fromRGB(20, 37, 35)
\t\tend
\tend
\tif discPlayer.InstructionLabel and discPlayer.InstructionLabel.Parent then''')
c=edit(c,'\t\tif player:GetAttribute("Level3_Room") ~= nil then player:SetAttribute("Level3_Room", "") end',
'''\t\tif player:GetAttribute("Level3_Room") ~= nil then player:SetAttribute("Level3_Room", "") end
\t\tif player.Character then player.Character:SetAttribute("Level3_FinalHallCrossedGeneration", nil) end''')
c=edit(c,'\t\tsession.State:SetAttribute("Level3_ExitPosition", nil)','\t\tsession.State:SetAttribute("Level3_ExitPosition", nil)\n\t\tsession.State:SetAttribute("Level3_CDPlayerPosition", nil)')
c=edit(c,'\tworkspace:SetAttribute("Level3Modules", 0)','\tworkspace:SetAttribute("Level3CDPlayerPosition", nil)\n\tworkspace:SetAttribute("Level3Modules", 0)')
save(name,b,c,record)

name='Level 3 Mall Manager AI Controller';b,record=source(name);c=b
c=edit(c,'\t\tor PlayerProtection.IsActive(player, character) then','\t\tor (not session.FinalHallChase and PlayerProtection.IsActive(player, character)) then')
c=edit(c,'local function eligibleSpawnPlayers(): {any}','local function eligibleSpawnPlayers(includeProtected: boolean?): {any}')
c=edit(c,'\t\tif player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") ~= true then','\t\tif player.Parent == Players and player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") ~= true then')
c=edit(c,'\t\t\t\tand not PlayerProtection.IsActive(player, character) then','\t\t\t\tand (includeProtected or not PlayerProtection.IsActive(player, character)) then')
start=c.index('local function chooseFinalHallSpawn(');end=c.index('\nlocal function chooseBlackoutSpawn(',start)
old=c[start:end]
new=old.replace('local records = eligibleSpawnPlayers()','local records = eligibleSpawnPlayers(true)')
pos1=new.index('\t-- Start in the last ten percent');pos2=new.index('\t-- Face a runner',pos1)
new=new[:pos1]+'''\t-- The barrier is life-scoped. A revive or temporarily missing living root
\t-- during a deferred clearance retry must not inherit an earlier crossing.
\tfor _, player in ipairs(Players:GetPlayers()) do
\t\tif player.Parent == Players and player:GetAttribute("InRound") == true
\t\t\tand player:GetAttribute("Escaped") ~= true then
\t\t\tlocal character = player.Character
\t\t\tlocal humanoid = character and character:FindFirstChildOfClass("Humanoid")
\t\t\tif character and character.Parent and humanoid and humanoid.Health > 0 then
\t\t\t\tlocal root = character:FindFirstChild("HumanoidRootPart")
\t\t\t\tif not root or not root:IsA("BasePart")
\t\t\t\t\tor character:GetAttribute("Level3_FinalHallCrossedGeneration") ~= generation then return nil end
\t\t\tend
\t\tend
\tend
\t-- Exactly the authored far endpoint; never move the reveal toward a player.
\tlocal position = Vector3.new(hall.EndPoint.X, hall.FloorY, hall.EndPoint.Z)
\tif not spawnVolumeFits(position, spawnOverlapParams(records)) then return nil end
''' +new[pos2:]
c=c[:start]+new+c[end:]
c=edit(c,'\t\t-- Patrol only when no living round participant remains. Hiding players',
'''\t\tif session.FinalHallChase then
\t\t\t-- A finale without a runner holds position; never switch to random mall patrol.
\t\t\tsession.PatrolGoal = nil
\t\t\tsession.PatrolLegUntil = nil
\t\t\tclearGoal(session)
\t\t\tpublishState(session, "WAITING")
\t\t\tpublishTargetTelemetry(session, "NO_LIVING_PLAYER", -1, nil)
\t\t\treturn false
\t\tend
\t\t-- Patrol only when no living round participant remains. Hiding players''')
c=edit(c,'\tlocal ownsTarget = session.Target == player','\tlocal ownsTarget = not session.FinalHallChase and session.Target == player')
c=edit(c,'\tlocal ownsMemory = session.LastKnownPlayer == player','\tlocal ownsMemory = not session.FinalHallChase and session.LastKnownPlayer == player')
c=edit(c,'\tlocal ownsCheck = session.TableCheckTargetPlayer == player','\tlocal ownsCheck = not session.FinalHallChase and session.TableCheckTargetPlayer == player')
c=edit(c,'\t\tsession.AttackCharacter = nil\n\tend\n\tif ownsCheck then',
'''\t\tsession.AttackCharacter = nil
\t\tif session.FinalHallChase and validRound(session) then publishState(session, "CHASE") end
\tend
\tif ownsCheck then''')
c=edit(c,'local function attackLineClear(session: any, player: Player, maximumRange: number): (boolean, Humanoid?)\n',
'''local function attackLineClear(session: any, player: Player, maximumRange: number): (boolean, Humanoid?)
\t-- Finale can face/chase protected runners, but immunity still fences every attack.
\tif PlayerProtection.IsActive(player, player.Character) then return false, nil end
''')
c=edit(c,'\t\t\tsession.ActivatedAt = os.clock() + Tuning.SpawnGraceSeconds','\t\t\tsession.ActivatedAt = os.clock() + (session.FinalHallChase and 0 or Tuning.SpawnGraceSeconds)')
c=edit(c,'\tlocal target = Vector3.new(facePosition.X, rootPosition.Y, facePosition.Z)\n\tmodel:PivotTo(CFrame.lookAt(rootPosition, target))',
'''\tlocal target = Vector3.new(facePosition.X, rootPosition.Y, facePosition.Z)
\tif (target - rootPosition).Magnitude <= .001 then
\t\t-- A runner may stand exactly at the fixed endpoint. Keep the authored
\t\t-- position and face back down the hall instead of constructing a zero look vector.
\t\tlocal hall = manifest.FinalHall
\t\tlocal forward = type(hall) == "table" and hall.Forward
\t\tlocal direction = forward and Vector3.new(-forward.X, 0, -forward.Z) or Vector3.new(0, 0, -1)
\t\tif direction.Magnitude <= .001 then direction = Vector3.new(0, 0, -1) end
\t\ttarget = rootPosition + direction.Unit
\tend
\tmodel:PivotTo(CFrame.lookAt(rootPosition, target))''')
save(name,b,c,record)
(r/'candidate-manifest-v2.json').write_text(json.dumps({'changes':rows},indent=2)+'\n')
print(json.dumps(rows,indent=2))
