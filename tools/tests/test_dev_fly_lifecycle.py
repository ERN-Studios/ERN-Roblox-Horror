"""Execute production fly/lifecycle code; engine movement is checked separately.

Run with an alternate source to demonstrate that the pre-fix code fails the regression.
Set LUAU_BIN or put luau on PATH. Fixtures are generated outside the repository.
"""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'StarterPlayer/StarterPlayerScripts/DevCheats.LocalScript.lua'
source = source_path.read_text(encoding='utf-8')
fly = source[source.index('-- Noclip fly\n'):source.index('-- Third-person only')]
hooks_start = source.index('player.CharacterRemoving:Connect(') if 'player.CharacterRemoving:Connect(' in source else source.index('player.CharacterAdded:Connect(')
hooks = source[hooks_start:source.index('player:GetAttributeChangedSignal("InRound")', hooks_start)]
setup = r'''
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function signal()
    local s = {callbacks = {}}
    function s:Connect(fn)
        local connection = {Active = true, Callback = fn}
        function connection:Disconnect() self.Active = false end
        table.insert(self.callbacks, connection)
        return connection
    end
    function s:Fire(...) for _, c in ipairs(self.callbacks) do if c.Active then c.Callback(...) end end end
    function s:LiveCount() local n=0; for _, c in ipairs(self.callbacks) do if c.Active then n+=1 end end; return n end
    function s:Queue()
        local callbacks={}; for _, c in ipairs(self.callbacks) do if c.Active then table.insert(callbacks,c.Callback) end end
        return function(...) for _, fn in ipairs(callbacks) do fn(...) end end
    end
    return s
end
local vector = {}
vector.__index = function(v, k)
    if k == 'Magnitude' then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
    if k == 'Unit' then local m=v.Magnitude; return setmetatable({X=v.X/m,Y=v.Y/m,Z=v.Z/m},vector) end
    return vector[k]
end
local function v(x,y,z) return setmetatable({X=x,Y=y,Z=z},vector) end
function vector.__add(a,b) return v(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
function vector.__sub(a,b) return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
function vector.__mul(a,b) return v(a.X*b,a.Y*b,a.Z*b) end
function vector:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
local Vector3 = {new=v,zero=v(0,0,0)}
local Enum = {HumanoidStateType={},KeyCode={}}
for _, k in ipairs({'Dead','FallingDown','Ragdoll','Physics','PlatformStanding','Running','Flying','GettingUp','Freefall'}) do Enum.HumanoidStateType[k]=k end
for _, k in ipairs({'W','S','D','A','Space','LeftControl'}) do Enum.KeyCode[k]=k end
local keys = {}
local UIS = {IsKeyDown=function(_,key) return keys[key] == true end}
local workspace = {CurrentCamera={CFrame={LookVector=v(0,0,-1),RightVector=v(1,0,0)}}}
local RunService = {PreSimulation=signal()}
local attrs, requests, warnings = {}, {}, {}
local player = {CharacterAdded=signal(),CharacterRemoving=signal()}
local function publishState(key,value) attrs[key]=value end
local function fireDev(command,value) table.insert(requests,{command,value}); return true end
local function requestedState(current,requested) return if typeof(requested)=='boolean' then requested else not current end
local function warn(message) table.insert(warnings,message) end
local report = print
local function print() end -- Routine production toggle messages add no assertion evidence.
local function reapplyPerspectiveSoon() end
local function descendantOf(object, ancestor)
    local p=object.Parent; while p do if p==ancestor then return true end; p=p.Parent end; return false
end
local function part(character,name,collide)
    local p={Parent=character,Name=name,CanCollide=collide,Anchored=false,AssemblyLinearVelocity=v(1,2,3),AssemblyAngularVelocity=v(4,5,6),Position=v(0,3.605,0)}
    function p:IsA(class) return class=='BasePart' end
    p.IsDescendantOf=descendantOf
    table.insert(character.Parts,p)
    return p
end
local function body(name)
    local c={Name=name,Parent=workspace,Parts={},Attributes={},DescendantAdded=signal(),Pivots=0}
    c.Root=part(c,'HumanoidRootPart',true)
    c.Leg=part(c,'LeftUpperLeg',true)
    c.Visual=part(c,'char1',false)
    local h={Parent=c,Health=100,AutoRotate=true,PlatformStand=false,MoveDirection=v(0,0,0),Jump=false,State='Running',States={FallingDown=true,Ragdoll=true},Died=signal(),ChangedStates={}}
    function h:GetState() return self.State end
    function h:GetStateEnabled(s) return self.States[s] end
    function h:SetStateEnabled(s,on) self.States[s]=on end
    function h:ChangeState(s) self.State=s; table.insert(self.ChangedStates,s) end
    c.Humanoid=h
    function c:FindFirstChildOfClass(class) return if class=='Humanoid' then self.Humanoid else nil end
    function c:FindFirstChild(name) return if name=='HumanoidRootPart' then self.Root else nil end
    function c:GetAttribute(name) return self.Attributes[name] end
    function c:GetDescendants() return self.Parts end
    function c:GetPivot() return self.Root.Position end
    function c:PivotTo(position) self.Pivots+=1; self.Root.Position=position end
    return c
end
local function snapshot(c)
    return {anchor=c.Root.Anchored,rotate=c.Humanoid.AutoRotate,platform=c.Humanoid.PlatformStand,
        falling=c.Humanoid.States.FallingDown,ragdoll=c.Humanoid.States.Ragdoll,state=c.Humanoid.State,
        rootCollide=c.Root.CanCollide,legCollide=c.Leg.CanCollide,visualCollide=c.Visual.CanCollide,
        velocity=c.Root.AssemblyLinearVelocity,angular=c.Root.AssemblyAngularVelocity,position=c.Root.Position,pivots=c.Pivots,
        statesChanged=#c.Humanoid.ChangedStates}
end
local function unchanged(c,s,message)
    local after=snapshot(c); for k,value in pairs(s) do check(after[k]==value,message..': '..k) end
end
local function tick(dt) RunService.PreSimulation:Fire(dt or 1/60) end
'''
tests = r'''
-- A lifecycle-owned anchored entry must refuse without any mutation or remote.
local anchored=body('entry'); anchored.Root.Anchored=true; player.Character=anchored
local original=snapshot(anchored); local sent=#requests
check(startFlying()==false,'refuses anchored entry rather than saving its transient lock')
unchanged(anchored,original,'anchored entry untouched'); check(#requests==sent,'refusal sends no noclip remote')
stopFlying(); unchanged(anchored,original,'OFF after refusal preserves entry lock')
check(attrs.DevCheatNoclip==false and not flying,'refusal never publishes active fly')

-- Each blocked body is refused before any writes.
for _, reason in ipairs({'dead','platform','slide','ragdollFlag','FallingDown','Ragdoll','Physics','PlatformStanding'}) do
    local c=body(reason); player.Character=c
    if reason=='dead' then c.Humanoid.Health=0
    elseif reason=='platform' then c.Humanoid.PlatformStand=true
    elseif reason=='slide' then c.Attributes.Level2_ForcedSliding=true
    elseif reason=='ragdollFlag' then c.Attributes.Level2_RagdollServerActive=true
    else c.Humanoid.State=reason end
    local before=snapshot(c); local n=#requests
    check(startFlying()==false,'refuses '..reason); unchanged(c,before,reason..' untouched'); check(#requests==n,reason..' no remote')
end

-- Standing ON/OFF, including unusual but legitimate saved false state flags.
local c=body('standing'); player.Character=c
c.Humanoid.States.FallingDown=false
check(startFlying()==true,'standing fly starts')
check(c.Root.Anchored and not c.Leg.CanCollide and not c.Visual.CanCollide,'ON retains anchored noclip')
check(not c.Humanoid.AutoRotate and c.Humanoid.State=='Flying','ON retains flying humanoid behavior')
check(c.DescendantAdded:LiveCount()==1 and c.Humanoid.Died:LiveCount()==1,'one pair of session connections')
local n=#requests; check(startFlying()==true and #requests==n,'duplicate ON is idempotent')
keys.W=true; tick(1); keys.W=false
check(math.abs(c.Root.Position.Z+4.5)<1e-9,'keyboard flight still normalizes and caps delta at 0.05s')
c.Humanoid.MoveDirection=v(1,0,0); tick(); c.Humanoid.MoveDirection=v(0,0,0)
check(math.abs(c.Root.Position.X-1.5)<1e-9,'gamepad/touch fallback retains 90-stud flight')
local late=part(c,'late cosmetic',true); c.DescendantAdded:Fire(late)
check(not late.CanCollide,'late part is noclipped')
stopFlying()
check(not c.Root.Anchored and c.Root.CanCollide and c.Leg.CanCollide and not c.Visual.CanCollide and late.CanCollide,'OFF restores mixed original collision and unanchors')
check(c.Humanoid.AutoRotate and not c.Humanoid.PlatformStand and not c.Humanoid.States.FallingDown and c.Humanoid.States.Ragdoll,'OFF restores exact humanoid flags')
check(c.Humanoid.State=='GettingUp' and c.Root.AssemblyLinearVelocity==Vector3.zero and c.Root.AssemblyAngularVelocity==Vector3.zero,'living owner receives normal get-up and velocity reset')
check(c.DescendantAdded:LiveCount()==0 and c.Humanoid.Died:LiveCount()==0,'OFF disconnects both session connections')
n=#requests; stopFlying(); check(#requests==n,'duplicate OFF does not dispatch twice')

-- CharacterRemoving restores only the departing subject, including false AutoRotate.
local old=body('departing'); old.Humanoid.AutoRotate=false; player.Character=old
check(startFlying(),'departing starts'); player.CharacterRemoving:Fire(old)
check(not flying and not old.Root.Anchored and old.Leg.CanCollide and not old.Humanoid.AutoRotate,'removal restores old body and clears session')
local new=body('replacement'); new.Root.Anchored=true; new.Humanoid.PlatformStand=true
new.Humanoid.States.FallingDown=false; new.Humanoid.States.Ragdoll=false
local before=snapshot(new); player.Character=new; player.CharacterAdded:Fire(new); tick()
unchanged(new,before,'replacement body remains completely untouched after removal')

-- Defensive CharacterAdded also restores old subject when removal did not fire.
old=body('missing removal'); player.Character=old; check(startFlying(),'second old starts')
local queuedAdded=old.DescendantAdded:Queue(); local queuedDied=old.Humanoid.Died:Queue()
new=body('anchored replacement'); new.Root.Anchored=true; new.Humanoid.AutoRotate=false; new.Humanoid.PlatformStand=true
new.Humanoid.States.FallingDown=false; new.Humanoid.States.Ragdoll=false
before=snapshot(new); player.Character=new; player.CharacterAdded:Fire(new)
check(not flying and not old.Root.Anchored and old.Leg.CanCollide and old.Humanoid.AutoRotate,'added fallback restores only old body')
unchanged(new,before,'added fallback never restores old state onto new body')
check(old.DescendantAdded:LiveCount()==0 and old.Humanoid.Died:LiveCount()==0,'old session fully disconnected')
local stalePart=part(old,'queued part',true); queuedAdded(stalePart)
check(stalePart.CanCollide,'already queued old callback cannot noclip a late part')

-- PreSimulation must stop before writing or moving a replacement, even before event delivery.
old=body('tick old'); player.Character=old; check(startFlying(),'tick old starts')
new=body('tick new'); new.Root.Anchored=true; new.Humanoid.PlatformStand=true; before=snapshot(new)
player.Character=new; keys.W=true; tick(); keys.W=false
unchanged(new,before,'tick cannot steal replacement body'); check(not flying and not old.Root.Anchored,'tick releases old subject')

-- Death cleans up immediately and never changes the corpse to GettingUp.
c=body('dies'); player.Character=c; check(startFlying(),'death session starts')
c.Humanoid.Health=0; c.Humanoid.State='Dead'; c.Humanoid.Died:Fire()
check(not flying and not c.Root.Anchored and c.Leg.CanCollide,'Died clears anchor and collision')
check(c.Humanoid.State=='Dead','Died preserves dead state')
check(c.DescendantAdded:LiveCount()==0 and c.Humanoid.Died:LiveCount()==0,'Died disconnects session listeners')

-- Stale notifications from an old session must not affect a new active session.
c=body('fresh session'); player.Character=c; check(startFlying(),'fresh session starts')
queuedDied(); queuedAdded(stalePart); player.CharacterRemoving:Fire(old)
check(flying and c.Root.Anchored and not c.Leg.CanCollide,'stale death/removal cannot stop current session')
check(stalePart.CanCollide,'stale Added cannot alter previous body')
stopFlying(); check(c.DescendantAdded:LiveCount()==0 and c.Humanoid.Died:LiveCount()==0,'final cleanup has no live session listeners')
report('Fly lifecycle: '..checks..' assertions passed; physics requires native Studio checks')
'''
binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
if not binary:
    fallback = Path('/tmp/stayquiet-luau-validation/luau')
    if fallback.is_file():
        binary = str(fallback)
if not binary:
    raise SystemExit('Set LUAU_BIN or install luau; no tests were executed.')
with tempfile.TemporaryDirectory(prefix='stayquiet-fly-lifecycle-') as directory:
    fixture = Path(directory) / 'fly-lifecycle-fixture.luau'
    fixture.write_text('\n'.join([setup, fly, hooks, tests]), encoding='utf-8')
    subprocess.run([binary, str(fixture)], check=True, timeout=30)
