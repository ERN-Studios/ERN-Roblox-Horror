"""Run the actual Pool Foam audio helpers and event handler in offline Luau.

No Studio, network or asset loading. The Sound stub counts calls so repeated
states, pause, replacement cleanup and Stop cannot accidentally restart/leak a
voice. Client checks exercise real handleClientEvent with presentation stubs.
Set LUAU_BIN to an official luau executable, or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = (ROOT / "ServerScriptService/Level 2 Systems/Level 2 Pool Foam Controller.ModuleScript.lua").read_text(encoding="utf-8")
CLIENT = (ROOT / "StarterPlayer/StarterPlayerScripts/Level 2 Pool Foam Client.LocalScript.lua").read_text(encoding="utf-8")


def section(source, start, end):
    return source[source.index(start):source.index(end)]


PRELUDE = r'''
local created = {}
local methods = {}
function methods:SetAttribute(key, value) self.Attributes[key] = value end
function methods:GetAttribute(key) return self.Attributes[key] end
function methods:Play() self.PlayCount += 1; self.Playing = true end
function methods:Pause() self.PauseCount += 1; self.Playing = false end
function methods:Resume() self.ResumeCount += 1; self.Playing = true end
function methods:Stop() self.StopCount += 1; self.Playing = false end
function methods:Destroy()
    self.Destroyed = true
    for _, child in created do
        if child.Parent == self and not child.Destroyed then child:Destroy() end
    end
    self.Parent = nil
end
local Instance = {}
function Instance.new(class)
    local instance = setmetatable({ClassName=class, Attributes={}, SoundId="",
        PlayCount=0, PauseCount=0, ResumeCount=0, StopCount=0}, {__index=methods})
    table.insert(created, instance)
    return instance
end
local Enum = {RollOffMode={InverseTapered="InverseTapered"}}
local warnings = {}
local function warn(message) table.insert(warnings, message) end
local function finiteNumber(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function numberOr(value, fallback, minimum, maximum)
    if not finiteNumber(value) then value=fallback end
    if minimum then value=math.max(minimum,value) end
    if maximum then value=math.min(maximum,value) end
    return value
end
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local function countSounds()
    local count = 0
    for _, item in created do
        if item.ClassName=="Sound" and not item.Destroyed then count += 1 end
    end
    return count
end
'''

SERVER_TESTS = r'''
local config={Audio={Enabled=true,RollOffMinDistance=12,RollOffMaxDistance=110,
    LoopVolumes={Idle=.06,Walk=.18,Hunt=.24}},AudioIds={Primary={Walk="",Hunt=""}},Attributes={}}
local model=Instance.new("Model")
model.PrimaryPart=Instance.new("Part"); model.PrimaryPart.Parent=model
local entity={Id="Primary_01",SlotId="Primary",Session={Configuration=config},Model=model}
for _, invalid in {"", "0", "rbxassetid://000", "https://example.com/1", "rbxassetid://-5", -4, 1.5, math.huge} do
    config.AudioIds.Primary.Walk=invalid
    setEntityAnimation(entity,"Walk")
end
check(countSounds()==0,"invalid/blank IDs create no sound and never wait")
config.AudioIds.Primary.Walk="123" -- Offline stub ID; never loaded/uploaded.
config.AudioIds.Primary.Hunt="rbxassetid://456"
entity.Animation={SetState=function() error("missing animation") end,Destroy=function() end}
setEntityAnimation(entity,"Walk")
local sound=entity.Audio.Sound
check(sound~=nil and entity.Animation==nil,"audio survives animation failure")
check(sound.Parent.Parent==model.PrimaryPart and sound.Parent.ClassName=="Attachment","point emitter follows root")
check(sound.RollOffMode=="InverseTapered" and sound.RollOffMinDistance==12 and sound.RollOffMaxDistance==110,"rolloff configuration")
for _=1,100 do setEntityAnimation(entity,"Walk",true); setEntityAnimationPaused(entity,false) end
check(countSounds()==1 and sound.PlayCount==1,"same-state churn and animation restarts never restart audio")
setEntityAnimationPaused(entity,true)
for _=1,20 do setEntityAnimationPaused(entity,true) end
check(sound.PauseCount==1 and not sound.Playing,"pause once")
setEntityAnimationPaused(entity,false)
check(sound.ResumeCount==1 and sound.PlayCount==1,"resume preserves loop position")
setEntityAnimation(entity,"Hunt")
check(entity.Audio.Sound==sound and sound.PlayCount==2 and sound.SoundId=="rbxassetid://456","Hunt swaps asset on same voice")
config.AudioIds.Primary.Walk="456"
setEntityAnimation(entity,"Walk")
check(sound.PlayCount==2 and sound.Volume==.18,"shared Walk/Hunt asset preserves playback")
setEntityAnimation(entity,"Idle")
check(not sound.Playing,"blank Idle is quiet")
setEntityAnimation(entity,"Walk")
check(sound.PlayCount==2 and sound.Playing,"leaving silent Idle resumes existing clip")
setEntityAnimationPaused(entity,true)
setEntityAnimation(entity,"Walk")
check(not sound.Playing,"kill pose never starts a paused Walk loop")
local oldAttachment=entity.Audio.Attachment
destroyEntityAudio(entity)
check(oldAttachment.Destroyed and sound.Destroyed and countSounds()==0,"model replacement removes old voice")
local replacement=Instance.new("Model")
replacement.PrimaryPart=Instance.new("Part"); replacement.PrimaryPart.Parent=replacement
entity.Model=replacement; entity.AnimationPaused=false
setEntityAnimation(entity,"Walk")
check(countSounds()==1 and entity.Audio.Sound.Parent.Parent==replacement.PrimaryPart,"replacement gets one fresh voice")
local runtime=Instance.new("Folder"); runtime.Parent={}; replacement.Parent=runtime
local activeSession={Entities={entity},Connections={},ChaseMarks={},RuntimeFolder=runtime}
local Controller={}
local workspace=Instance.new("Workspace")
local Players={GetPlayers=function() return {} end}
local NoiseRegistry={Clear=function() end}
local published=0
local function publishStopped() published += 1 end
'''

AFTER_STOP = r'''
Controller.Stop()
check(entity.Audio==nil and countSounds()==0 and runtime.Destroyed,"Controller.Stop destroys audio")
Controller.Stop()
check(published==2,"Stop is idempotent")
'''

CLIENT_PRELUDE = r'''
local player={UserId=7,Character={}}
local now=100
function workspace:GetServerTimeNow() return now end
workspace:SetAttribute("SelectedLevel",2); workspace:SetAttribute("RoundActive",true)
local PROTOCOL=1
local generation=9
local function currentGeneration() return generation end
local live=false
local function liveLevel2() return live end
local attackGeneration=nil
local lastAttackSerial=0
local revealGeneration=nil
local activeAttackId=nil
local soundCount=0
local effectCount=0
local function playSound() soundCount += 1 end
local function showCaption() end
local function captionFor() return nil end
local function beginEffect() effectCount += 1 end
local function resetPresentation() end
local function matchesAttack() return true end
'''

CLIENT_TESTS = r'''
local function hit(changes)
    local event={Protocol=1,Generation=9,Type="AttackHit",TargetUserId=7,
        TargetCharacter=player.Character,ServerTime=100,Serial=1}
    for key,value in changes or {} do event[key]=value end
    handleClientEvent(event)
end
hit()
check(soundCount==1 and effectCount==0,"real current-body kill sounds after death with no competing visual effect")
hit()
check(soundCount==1,"duplicate kill cannot replay sting")
hit({Serial=2,Generation=8}); hit({Serial=2,TargetUserId=99}); hit({Serial=2,TargetCharacter={}})
hit({Serial=2,ServerTime=90}); hit({Serial=2,ServerTime=110}); hit({Serial=2,ServerTime=0/0})
check(soundCount==1,"stale, wrong-victim, old-body and invalid-time hits rejected")
workspace:SetAttribute("RoundActive",false); hit({Serial=2})
check(soundCount==1,"no late sound after round end")
workspace:SetAttribute("RoundActive",true); live=true; hit({Serial=2})
check(soundCount==2 and effectCount==1,"pre-death hit still presents normally")
generation=nil; hit({Serial=3})
check(soundCount==2,"missing generation fails closed")
'''

RESET_PRELUDE = r'''
local transientSounds={}
local captionSerial=0
local caption={}
local colorGrade={}
local initialGrade={}
local activeEffect=nil
local lastAppliedFov=nil
local ownFovOffset=0
'''

RESET_TESTS = r'''
local hitSound=Instance.new("Sound")
local cueSound=Instance.new("Sound")
transientSounds[hitSound]=true; transientSounds[cueSound]=false
resetPresentation(true)
check(cueSound.Destroyed and not hitSound.Destroyed,"death presentation clears old cues and retains hit tail")
resetPresentation()
check(hitSound.Destroyed and next(transientSounds)==nil,"hard reset destroys every remaining transient")
print("Pool Foam audio: "..tostring(checks).." checks passed (offline Luau; engine loading/mix not exercised)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    source = "\n".join([
        PRELUDE,
        section(CONTROLLER, "local function setModelAttribute", "-- AUDIO RUNTIME BEGIN"),
        section(CONTROLLER, "-- AUDIO RUNTIME BEGIN", "local function configureModel"),
        SERVER_TESTS,
        section(CONTROLLER, "function Controller.Stop()", "function Controller.IsRunning()"),
        AFTER_STOP, CLIENT_PRELUDE,
        section(CLIENT, "local function handleClientEvent", "local function resolveRemotes"),
        CLIENT_TESTS, RESET_PRELUDE,
        section(CLIENT, "local function resetPresentation", "local function normalizedSoundId"),
        RESET_TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="pool-foam-audio-") as directory:
        fixture = Path(directory) / "audio_test.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == "__main__":
    main()
