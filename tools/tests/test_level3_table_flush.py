"""Execute real Level 3 table release, collision restore, and grace helpers.

Roblox parts and yawed CFrames are fixtures; production FlushAnchor and its
release path run unchanged. Geometry in the generated map needs a Studio check.
Set LUAU_BIN to the official Luau interpreter, or put luau on PATH.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HIDING = ROOT / "ServerScriptService/Level 3 Systems/Level 3 Hiding Controller.ModuleScript.lua"
CONFIG = ROOT / "ServerScriptService/Level 3 Systems/Level 3 Configuration.ModuleScript.lua"


def function(source, marker):
    start = source.index(marker)
    end = re.search(r"\n(?:local function |function Controller\.)", source[start + 1:])
    assert end, marker
    return source[start:start + 1 + end.start()]


PRELUDE = r'''
local checks = 0
local function check(ok, message) checks += 1; assert(ok, message) end
local serverNow = 100
local Vector3 = {}
local vm = {}
local vmt = {__index = function(v, key)
    if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
    return vm[key]
end, __sub = function(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end,
__add = function(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end}
function Vector3.new(x, y, z) return setmetatable({X=x, Y=y, Z=z}, vmt) end
Vector3.zero = Vector3.new(0, 0, 0)
local Color3 = {fromRGB = function() return {} end}
local cfMethods = {}
local CFrame = {}
local function rotate(yaw, p)
    local c, s = math.cos(yaw), math.sin(yaw)
    return Vector3.new(c*p.X + s*p.Z, p.Y, -s*p.X + c*p.Z)
end
local cmt = {__index=cfMethods, __mul = function(a, b)
    local cf = CFrame.new(a.Position + rotate(a.Yaw, b.Position))
    cf.Yaw = a.Yaw + b.Yaw
    return cf
end}
function CFrame.new(x, y, z)
    return setmetatable({Position=type(x)=="table" and x or Vector3.new(x or 0, y or 0, z or 0), Yaw=0}, cmt)
end
function CFrame.Angles(_, yaw, _) local cf=CFrame.new(); cf.Yaw=yaw; return cf end
function cfMethods:Inverse()
    local cf = CFrame.new(rotate(-self.Yaw, Vector3.new(-self.Position.X, -self.Position.Y, -self.Position.Z)))
    cf.Yaw = -self.Yaw
    return cf
end
function cfMethods:ToObjectSpace(other) return self:Inverse()*other end
function cfMethods:PointToObjectSpace(p) return rotate(-self.Yaw, p-self.Position) end
function cfMethods:PointToWorldSpace(p) return self.Position+rotate(self.Yaw, p) end
local function object(class)
    return {Class=class, Parent=true, Attributes={},
        IsA=function(self, value) return self.Class==value end,
        FindFirstChild=function() return nil end,
        FindFirstChildOfClass=function() return nil end,
        GetAttribute=function(self, key) return self.Attributes[key] end,
        SetAttribute=function(self, key, value) self.Attributes[key]=value end,
        IsDescendantOf=function(self, world) return self.World==world end}
end
local Players={}
local workspace=object("Workspace")
workspace.GetServerTimeNow=function() return serverNow end
local PlayerProtection={IsActive=function(p, character) return p.Shielded==character end}
local Controller={}
local activeSession
local function refreshPrompt(session, anchor)
    anchor.Enabled=#session.Occupants[anchor]<2
    anchor:SetAttribute("Level3_HideOccupiedUserId", session.Occupants[anchor][1] and session.Occupants[anchor][1].UserId or 0)
end
local function updateHiddenCount(session)
    session.HiddenCount=0
    for _ in pairs(session.HiddenPlayers) do session.HiddenCount+=1 end
end
'''


FIXTURES = r'''
local function fixture(count, yaw)
    serverNow=100
    workspace.Attributes={SelectedLevel=3, RoundActive=true}
    local world=object("Model"); world.Parent=workspace; world.Attributes.Level3_Generation=7
    local anchor=object("BasePart"); anchor.World=world
    anchor.CFrame=CFrame.new(10,26.2,-30)*CFrame.Angles(0,yaw or 0,0)
    anchor.Position=anchor.CFrame.Position
    local session={Active=true, World=world, Generation=7, HiddenPlayers={}, Occupants={[anchor]={}},
        AnchorSet={[anchor]=true}, FlushImmuneUntil={}, FlushImmuneCharacters={}}
    activeSession=session
    local players={}
    for i=1,count do
        local p=object("Player"); p.Parent=Players; p.UserId=i; p.Attributes={InRound=true,Level3_Hiding=true}
        local root=object("BasePart"); root.Anchored=true
        root.CFrame=anchor.CFrame*CFrame.new(slotLateral(i),0,0); root.Position=root.CFrame.Position
        root.AssemblyLinearVelocity=Vector3.new(4,5,6); root.AssemblyAngularVelocity=Vector3.new(1,2,3)
        local body=object("BasePart"); body.CanCollide=false; body.CanTouch=false; body.CanQuery=false
        local human={Parent=true, Health=100, AutoRotate=false, WalkSpeed=0, JumpPower=0, JumpHeight=0, DisplayDistanceType="None"}
        local character=object("Model")
        character.FindFirstChildOfClass=function(_, class) return class=="Humanoid" and human or nil end
        character.FindFirstChild=function(_, name) return name=="HumanoidRootPart" and root or nil end
        local offset=CFrame.new(0,-3.49,0)
        character.GetPivot=function() return root.CFrame*offset end
        character.PivotTo=function(_, target) root.CFrame=target*offset:Inverse(); root.Position=root.CFrame.Position end
        p.Character=character
        local track={Stopped=false,Destroyed=false,Stop=function(self) self.Stopped=true end,Destroy=function(self) self.Destroyed=true end}
        local animation={Destroyed=false,Destroy=function(self) self.Destroyed=true end}
        local record={Generation=7, Character=character, Humanoid=human, Root=root, Anchor=anchor, Slot=i,
            ExitCFrame=anchor.CFrame*CFrame.new(slotLateral(i),Tuning.ExitVerticalOffset,Tuning.ExitOffsetZ),
            RootAnchored=false, AutoRotate=true, WalkSpeed=16, JumpPower=50, JumpHeight=7.2, DisplayDistanceType="Viewer",
            CollisionState={{Object=body,CanCollide=true,CanTouch=false,CanQuery=true}},HideTrack=track,HideAnimation=animation}
        p.Body=body; p.Root=root; p.Human=human; p.Track=track; p.Animation=animation
        session.HiddenPlayers[p]=record; table.insert(session.Occupants[anchor],p); table.insert(players,p)
    end
    updateHiddenCount(session)
    return session,anchor,players
end
local function localPosition(anchor, p) return anchor.CFrame:PointToObjectSpace(p.Root.Position) end
local function close(a,b) return math.abs(a-b)<1e-6 end
'''


TESTS = r'''
-- Both players are released once, retain separate lanes, and regain their exact
-- pre-hide controls/collision while the gameplay rig's offset pivot is handled.
for _,yaw in {0,.9,-2.1} do
    local s,a,players=fixture(2,yaw)
    local awayFrom=a.CFrame:PointToWorldSpace(Vector3.new(0,0,12))
    local flushed=Controller.FlushAnchor(a,awayFrom)
    check(#flushed==2 and #s.Occupants[a]==0 and s.HiddenCount==0,"flush must release both occupants despite list removal")
    check(a.Enabled and a:GetAttribute("Level3_HideOccupiedUserId")==0,"flush reopens table and clears occupancy")
    for i,p in players do
        local pos=localPosition(a,p)
        check(close(pos.X,slotLateral(i)) and close(pos.Y,Tuning.ExitVerticalOffset) and close(pos.Z,-Tuning.ExitOffsetZ),
            "root must land in its yawed lane on the opposite side from the entity")
        check(not p.Root.Anchored and p:GetAttribute("Level3_Hiding")==false and p:GetAttribute("Level3_HideTableIndex")==0,
            "flush must unanchor and clear the hiding/camera state")
        check(p.Human.AutoRotate and p.Human.WalkSpeed==16 and p.Human.JumpPower==50 and p.Human.JumpHeight==7.2
            and p.Human.DisplayDistanceType=="Viewer", "flush restores original humanoid controls")
        check(p.Body.CanCollide and not p.Body.CanTouch and p.Body.CanQuery,"flush restores individual collision flags")
        check(p.Root.AssemblyLinearVelocity.Magnitude==0 and p.Root.AssemblyAngularVelocity.Magnitude==0,"flush clears stale anchored velocity")
        check(p.Track.Stopped and p.Track.Destroyed and p.Animation.Destroyed,"flush releases held animation resources")
        check(Controller.IsFlushImmune(p),"successful flush grants attack grace")
    end
    check(#Controller.FlushAnchor(a,awayFrom)==0,"a repeated flush cannot release or extend grace")
    serverNow=100+TableCheckTuning.FlushImmunitySeconds-.001
    check(Controller.IsFlushImmune(players[1]),"flush grace survives until the end of its server-time duration")
    serverNow=100+TableCheckTuning.FlushImmunitySeconds
    check(not Controller.IsFlushImmune(players[1]),"flush grace expires at its exact server-time deadline")
end
do
    local s,a,ps=fixture(1)
    Controller.FlushAnchor(a,a.CFrame:PointToWorldSpace(Vector3.new(0,0,-12)))
    check(close(localPosition(a,ps[1]).Z,Tuning.ExitOffsetZ),"entity on negative side pushes occupant through positive exit")
    ps[1].Character=object("Model")
    check(not Controller.IsFlushImmune(ps[1]),"a respawned avatar cannot inherit another life's flush grace")
end
do
    local s,a,ps=fixture(2)
    ps[1].Shielded=ps[1].Character
    local original=ps[1].Root.CFrame
    local flushed=Controller.FlushAnchor(a,a.CFrame:PointToWorldSpace(Vector3.new(0,0,12)))
    check(#flushed==1 and flushed[1]==ps[2],"mixed table flush skips protected life and releases unprotected occupant")
    check(s.HiddenPlayers[ps[1]]~=nil and ps[1].Root.CFrame==original and ps[1].Root.Anchored
        and #s.Occupants[a]==1 and s.FlushImmuneUntil[ps[1]]==nil,"protected occupant remains untouched and receives no flush grace")
end
for _,reason in {"inactive","wrongLevel","suspended","staleWorld","unregistered","removed","foreign","oldCharacter","oldGeneration","dead","notInRound","escaped","gone","oldRoot"} do
    local s,a,ps=fixture(1); local p=ps[1]
    if reason=="inactive" then workspace:SetAttribute("RoundActive",false)
    elseif reason=="wrongLevel" then workspace:SetAttribute("SelectedLevel",2)
    elseif reason=="suspended" then s.FurnitureSuspended=true
    elseif reason=="staleWorld" then s.World:SetAttribute("Level3_Generation",8)
    elseif reason=="unregistered" then s.AnchorSet[a]=nil
    elseif reason=="removed" then a.Parent=nil
    elseif reason=="foreign" then a.World={}
    elseif reason=="oldCharacter" then p.Character=object("Model")
    elseif reason=="oldGeneration" then s.HiddenPlayers[p].Generation=6
    elseif reason=="dead" then p.Human.Health=0
    elseif reason=="notInRound" then p:SetAttribute("InRound",false)
    elseif reason=="escaped" then p:SetAttribute("Escaped",true)
    elseif reason=="gone" then p.Parent=nil
    else s.HiddenPlayers[p].Root=object("BasePart") end
    check(#Controller.FlushAnchor(a)==0 and s.HiddenPlayers[p]~=nil and #s.Occupants[a]==1
        and s.FlushImmuneUntil[p]==nil,"flush rejects invalid context without mutation: "..reason)
end
do
    local s,a,ps=fixture(1); local p=ps[1]
    local original=s.HiddenPlayers[p].ExitCFrame
    check(releasePlayer(s,p,true),"voluntary exit still releases through normal path")
    check((p.Root.Position-original.Position).Magnitude<1e-6 and not Controller.IsFlushImmune(p),
        "voluntary exit preserves chosen entry-side exit and grants no entity grace")
end
print("Level 3 table flush: "..checks.." checks passed (production release helpers; offline parts)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests executed.")
    source = HIDING.read_text(encoding="utf-8")
    markers = (
        "local function slotLateral(", "local function liveSession(",
        "local function roundAllowsHiding(", "local function characterState(",
        "local function pivotRootTo(", "local function eligible(",
        "local function restoreCollision(", "local function releasePlayer(",
        "local function aiOccupant(", "function Controller.FlushAnchor(",
        "function Controller.IsFlushImmune(",
    )
    pieces = [PRELUDE, "local Configuration=(function()", CONFIG.read_text(encoding="utf-8"), "end)()",
              "local Tuning=Configuration.Hiding\nlocal TableCheckTuning=Configuration.TableCheck"]
    pieces.extend(function(source, marker) for marker in markers)
    pieces.extend([FIXTURES, TESTS])
    with tempfile.TemporaryDirectory(prefix="level3-table-flush-") as directory:
        fixture = Path(directory) / "table_flush.luau"
        fixture.write_text("\n".join(pieces), encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == "__main__":
    main()
