"""Run actual GameManager admission/loading/recovery blocks in offline Luau.

The production Loading and Routing modules and host functions are extracted on
every run. Only Roblox services, character/world work and the clock are fakes.
This covers host wiring across the shared deadline; real MemoryStore replication,
TeleportService transport, engine character loading and client streaming still
need Roblox integration tests. Set LUAU_BIN or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "ServerScriptService"


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


COMMON = r'''
local checks = 0
local function expect(actual, wanted, message)
 checks += 1
 assert(actual == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(actual))
end
local function near(actual, wanted, tolerance, message)
 checks += 1
 assert(math.abs(actual - wanted) <= tolerance, message .. ': got ' .. tostring(actual))
end
local function scheduler()
 local clock = {Now=0, Queue={}, Sequence=0, Steps=0}
 local mainThread = coroutine.running()
 local task = {}
 local function schedule(after, callback)
  clock.Sequence += 1
  table.insert(clock.Queue, {At=clock.Now+after, Order=clock.Sequence, Callback=callback})
 end
 function clock:Advance(seconds)
  local target = self.Now + seconds
  while true do
   table.sort(self.Queue, function(a,b) return a.At < b.At or (a.At == b.At and a.Order < b.Order) end)
   local item = self.Queue[1]
   if not item or item.At > target then break end
   table.remove(self.Queue, 1)
   self.Now = item.At
   self.Steps += 1
   assert(self.Steps < 20000, 'bounded scheduler exceeded event budget')
   item.Callback()
  end
  self.Now = target
 end
 function task.wait(seconds)
  seconds = seconds or .05
  if coroutine.running() ~= mainThread then return coroutine.yield(seconds) end
  clock:Advance(seconds)
  return seconds
 end
 function task.spawn(fn, ...)
  local args = table.pack(...)
  local thread = coroutine.create(function() fn(table.unpack(args, 1, args.n)) end)
  local function resume()
   local ok, delay = coroutine.resume(thread)
   assert(ok, delay)
   if coroutine.status(thread) ~= 'dead' then schedule(delay or .05, resume) end
  end
  resume()
  return thread
 end
 function task.delay(seconds, fn) schedule(seconds, function() task.spawn(fn) end) end
 function task.defer(fn) task.delay(0, fn) end
 return clock, task
end
local function vector(x,y,z)
 return setmetatable({X=x,Y=y,Z=z}, {__sub=function(a,b)
  return {Magnitude=math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)}
 end})
end

local function host(options)
 options = options or {}
 local clock, task = scheduler()
 local h = {Clock=clock, Task=task, Notices={}, Returns={}, Holds={}, Reads=0, Builds=0, Spawns=0}
 local destinationArrivalEvidence = {}
 local captureArrival
 local os = {clock=function() return clock.Now end}
 local print, warn = function() end, function() end
 local game = {JobId='offline-host'}
 local workspace = {Attributes={}}
 function workspace:SetAttribute(name, value) self.Attributes[name] = value end
 function workspace:GetServerTimeNow() return 100000 + clock.Now end
 h.Workspace = workspace
 local Players = {Members={}}
 function Players:GetPlayers() return table.clone(self.Members) end
 h.Players = Players
 function h:Player(id, packet)
  local player = {UserId=id, Packet=packet, Attributes={}}
  function player:GetJoinData()
   if self.JoinDataFails then error('join data unavailable') end
   return {TeleportData=self.Packet}
  end
  function player:SetAttribute(name, value) self.Attributes[name] = value end
  function player:GetAttribute(name) return self.Attributes[name] end
  local root = {Position=vector(0,0,0), Anchored=false}
  local humanoid = {Health=100}
  local character = {Parent={}, Root=root, Humanoid=humanoid}
  function character:FindFirstChild(name) return name == 'HumanoidRootPart' and self.Root or nil end
  function character:FindFirstChildOfClass(name) return name == 'Humanoid' and self.Humanoid or nil end
  player.Character = character
  return player
 end
 function h:Add(player)
  player.Parent = Players
  table.insert(Players.Members, player)
  captureArrival(player, player.Packet)
 end
 function h:Remove(player)
  local index = table.find(Players.Members, player)
  if index then table.remove(Players.Members, index) end
  player.Parent = nil
 end
 function h:At(at, fn) task.delay(at-clock.Now, fn) end
 function h:CountNotice(kind)
  local count = 0
  for _, item in ipairs(self.Notices) do if item.Kind == kind then count += 1 end end
  return count
 end
 local IS_RESERVED_ROUND_SERVER = options.Reserved ~= false
 local IS_STUDIO = options.Studio == true
 local failedReservedEntry, roundBusy = false, true
 local recoverFailedEntry, loadingRuntime, activeEntry
 local zyntraReentry = {}
 local loadingFailures, pendingExplicitPlacement, pendingSlideRelease, pendingSlideStream = {}, {}, {}, {}
 local inRound, characterLoadOwner = {}, {}
 local roundEntryMode, LEVEL_TWO_TUBE_ENTRY_MODE = nil, 'tube'
 local Enum = {CameraMode={Classic='Classic'}}
 local Vector3 = {zero=vector(0,0,0)}
 local status = {}
 function status:FireClient(player, kind, payload)
  table.insert(h.Notices, {At=clock.Now, Player=player, Kind=kind, Payload=payload})
  if kind == 'entryprepare' and not options.NoAck then
   task.delay(options.AckDelay or 0, function()
    activeEntry:Acknowledge(player, payload)
   end)
  end
 end
 local function ensureWorld()
  h.Builds += 1
  task.wait(options.BuildDelay or 0)
  if options.BuildError then error('fake builder failed') end
  return options.BuildResult ~= false
 end
 local function spawnGameplayCharacter(player)
  h.Spawns += 1
  task.wait(options.CharacterDelay or 0)
  return player.Parent == Players and player.Character or nil
 end
 local function placeOnLevelEntry() return options.PlacementResult ~= false end
 local function returnGroupToLobby(group)
  table.insert(h.Returns, {At=clock.Now, Group=table.clone(group)})
 end
 local function awaitTransferSettlement()
  return options.TransferSettled ~= false, Players:GetPlayers()
 end
 local function holdCompletedWorld(group, endpoint)
  table.insert(h.Holds, {Group=group, Endpoint=endpoint})
 end
 local cohortMap = {}
 function cohortMap:GetAsync(key)
  h.Reads += 1
  if options.Read then return options.Read(h, key) end
  return h.Snapshot
 end
'''

HOST_END = r'''
 function h:Run(stageOnly)
  self.Attempt = beginGroupLoading({})
  self.Decision, self.Group = stageArrivingParty(self.Attempt)
  self.AdmissionAt = clock.Now
  if not stageOnly and self.Decision == 'admit' then
   self.Prepared = prepareGroupLoading(self.Attempt, self.Group.Members, self.Group.Level, false)
  end
  return self
 end
 function h:State()
  return {FailedReserved=failedReservedEntry, Busy=roundBusy, Reentry=zyntraReentry.OnInvoke,
   Placement=pendingExplicitPlacement, Slide=pendingSlideRelease, Stream=pendingSlideStream}
 end
 function h:SeedPending(player)
  pendingExplicitPlacement[player], pendingSlideRelease[player], pendingSlideStream[player] = true, true, {}
 end
 function h:ReplaceActive() activeEntry = {}; roundBusy = true end
 return h
end
local function packet(expected, final, session, level)
 return Routing.ArrivalPacket({SessionId=session or 'cohort', Level=level or 2,
  Expected=expected, Final=final, Deadline=100015})
end
local function snapshot(ids, session, level)
 return Loading.CohortSnapshot(session or 'cohort', level or 2, ids)
end
'''

TESTS = r'''
do
 local h = host({BuildDelay=5, CharacterDelay=1, AckDelay=.1})
 local a, b = h:Player(1,packet(2,true)), h:Player(2,packet(2,true))
 h:Add(a); h:At(20,function() h:Add(b) end)
 h:Run()
 expect(h.Decision,'admit','final packet waits for both live arrivals')
 near(h.AdmissionAt,20,.21,'full cohort admits before the shared cap')
 expect(h.Prepared,true,'actual host validates both characters and client acknowledgements')
 expect(h.Attempt.State,'ready','host commits readiness')
 expect(h.Attempt.Deadline,60,'admission did not replace the original deadline')
 expect(h.Builds,1,'one group builds one world')
 expect(h.Spawns,2,'each admitted member gets a character')
 expect(h:CountNotice('entryreleased'),2,'both clients receive the common release')
 expect(h.Workspace.Attributes.RoundLoadingState,'ready','host publishes ready state')
 expect(h.Reads,0,'final teleport packets need no MemoryStore read')
 h.Clock:Advance(70)
 expect(h:CountNotice('loadfailed'),0,'old watchdog cannot cancel a committed host')
end
do
 local h = host({BuildDelay=20, TransferSettled=false})
 local a, b = h:Player(1,packet(2,true)), h:Player(2,packet(2,true))
 h:Add(a); h:SeedPending(a); h:At(45,function() h:Add(b) end)
 h:Run()
 near(h.AdmissionAt,45,.21,'late complete cohort may still enter')
 expect(h.Prepared,false,'world work receives only the remaining shared budget')
 expect(h.Attempt.Deadline,60,'generation did not restart sixty seconds')
 expect(h.Attempt.Reason,'LOADING_TIMEOUT','deadline produces timeout reason')
 near(h.Returns[1].At,60,.001,'reserved recovery transfers without waiting for yielding builder')
 expect(h.Attempt.WorldWorkerDone,false,'recovery started while world worker was still yielding')
 expect(h:CountNotice('entrycancel'),2,'each arrived member gets one cancellation')
 expect(h:CountNotice('loadfailed'),2,'timeout notice reaches both clients')
 expect(h:CountNotice('entryreleased'),0,'no partial release after timeout')
 expect(h:State().FailedReserved,true,'failed reserved server rejects further entry')
 expect(h:State().Reentry(),false,'reentry is closed immediately')
 expect(h:State().Placement[a],nil,'failed entry clears placement ownership')
 expect(h:State().Slide[a],nil,'failed entry clears slide release')
 expect(h:State().Stream[a],nil,'failed entry clears stream release')
 expect(#h.Holds,1,'failed fallback settlement holds the stranded group')
 h.Clock:Advance(10)
 expect(h.Attempt.WorldWorkerDone,true,'late builder completion can finish its ownership')
 expect(h.Attempt.State,'failed','late worker cannot revive failed entry')
 expect(h:CountNotice('entryreleased'),0,'late worker cannot release clients')
 expect(#h.Returns,1,'recovery transfer runs once')
end
do
 local h = host({Studio=true, BuildDelay=70})
 local a = h:Player(1,packet(1,true)); h:Add(a)
 h:Run()
 near(h.Clock.Now,60,.1,'Studio timeout ends the host wait at sixty seconds')
 expect(h:CountNotice('lobby'),1,'Studio presents recovery immediately')
 expect(a:GetAttribute('InRound'),false,'Studio recovery removes gameplay membership')
 expect(a.Character.Root.Anchored,true,'existing Studio rig stays protected while builder owns world')
 expect(#h.Returns,0,'Studio defers world restoration while old builder is active')
 h:ReplaceActive()
 h.Clock:Advance(11)
 expect(#h.Returns,1,'Studio restores lobby after builder finishes')
 expect(h:State().Busy,true,'old recovery cannot unlock a newer loading attempt')
end
do
 local h = host({NoAck=true})
 local a = h:Player(1,packet(1,true)); h:Add(a)
 h:Run()
 expect(h.Prepared,false,'missing client readiness cancels actual host barrier')
 near(h.Returns[1].At,60,.001,'client readiness shares the same deadline')
 expect(h:CountNotice('entryreleased'),0,'unready client never receives release')
 expect(a:GetAttribute('RoundLoadingError'),'timeout','host exposes timeout to client')
 expect(h.Workspace.Attributes.LoadStage,'WORLD_ERROR','host exposes loading failure stage')
end
do
 local h = host()
 local a = h:Player(1,packet(2,true)); h:Add(a)
 h:At(59,function() h:Add(h:Player(3,packet(3,true))) end)
 h:Run(true)
 expect(h.Decision,'abandon','a never-arrived continuer prevents partial admission')
 expect(h.Attempt.Reason,'LOADING_TIMEOUT','late arrivals cannot extend the single cap')
 near(h.Returns[1].At,60,.001,'missing member recovery starts at original deadline')
 expect(h.Builds,0,'short final cohort never starts world generation')
end
do
 local h = host()
 local a, b = h:Player(1,packet(2,false)), h:Player(2,packet(2,false))
 h:Add(a); h:Add(b)
 h:At(5,function() h.Snapshot=snapshot({1,2}) end)
 h:Run(true)
 expect(h.Decision,'admit','source final MemoryStore snapshot resolves estimate-only arrivals')
 expect(h.AdmissionAt>=5,true,'matching an estimate alone never admits early')
 expect(h.AdmissionAt<6.5,true,'published final cohort is observed on retry')
 expect(h.Group.Expected,2,'host applies authoritative final headcount')
end
do
 local h = host()
 local a = h:Player(1,packet(2,false)); h:Add(a)
 h:At(3,function() h.Snapshot=snapshot({1}) end)
 h:Run(true)
 expect(h.Decision,'admit','last undecided source member may opt out without final teleport packet')
 expect(#h.Group.Members,1,'source opt-out releases the sole final continuer')
 expect(h.Group.Expected,1,'final metadata replaces stale estimate')
end
do
 local h = host({Read=function(self)
  if self.Clock.Now<2 then return snapshot({1},'wrong-session') end
  if self.Clock.Now<4 then return snapshot({1},'cohort',3) end
  return snapshot({1})
 end})
 local a = h:Player(1,packet(2,false)); h:Add(a)
 h:Run(true)
 expect(h.Decision,'admit','valid metadata is retried after unrelated snapshots')
 expect(h.AdmissionAt>=4,true,'wrong session or level cannot finalize this cohort')
end
do
 local h = host({Read=function(self) self.Task.wait(100); return snapshot({1}) end})
 h:Add(h:Player(1,packet(1,false)))
 h:Run(true)
 expect(h.Decision,'abandon','yielding MemoryStore request does not hold admission beyond cap')
 expect(h.Reads,1,'only one in-flight metadata read is started')
 near(h.Returns[1].At,60,.001,'metadata latency does not postpone recovery')
 h.Clock:Advance(41)
 expect(h.Attempt.State,'failed','late metadata cannot revive timed-out host')
end
do
 local h = host({Read=function() error('transient service failure') end})
 h:Add(h:Player(1,packet(1,false)))
 h:Run(true)
 expect(h.Decision,'abandon','metadata service failures never authorize an estimate')
 expect(h.Reads>1,true,'completed MemoryStore failures are retried')
 expect(h.Reads<=61,true,'failed reads are rate bounded')
 near(h.Returns[1].At,60,.001,'retries use the original timeout')
end
do
 local h = host()
 local a = h:Player(1,packet(2,true))
 local b = h:Player(2,packet(2,false))
 h:Add(a); h:At(1,function() h:Remove(a) end); h:At(4,function() h:Add(b) end)
 h:Run(true)
 expect(h.Decision,'admit','a member that arrived then disconnected does not block survivor')
 near(h.AdmissionAt,4,.21,'disconnect does not waste remaining loading budget')
 expect(h.Group.Final,true,'departed final-packet carrier retains source authority')
 expect(h.Group.Expected,1,'only the observed destination departure is subtracted')
 expect(h.Group.Members[1],b,'remaining member is the admitted participant')
end
do
 local h = host()
 local a = h:Player(1,packet(2,true))
 local b = h:Player(2,packet(2,false))
 h:At(.05,function() h:Add(a) end)
 h:At(.10,function() h:Remove(a) end)
 h:At(3,function() h:Add(b) end)
 h:Run(true)
 expect(h.Decision,'admit','arrival between admission polls is retained by actual setup capture')
 near(h.AdmissionAt,3,.21,'quick departure does not strand later continuer')
 expect(h.Group.Expected,1,'captured destination departure is subtracted once')
end
do
 local h = host()
 local a = h:Player(1,packet(2,false))
 local b = h:Player(2,packet(2,false))
 h:Add(a); h:At(1,function() h:Remove(a) end)
 h:At(4,function() h:Add(b); h.Snapshot=snapshot({1,2}) end)
 h:Run(true)
 expect(h.Decision,'admit','final metadata also respects a confirmed destination disconnect')
 expect(h.Group.Expected,1,'exact cohort subtracts its arrived-then-left member')
end
do
 local h = host()
 local a = h:Player(1,packet(2,false)); h:Add(a)
 h.Snapshot=snapshot({1,2})
 h:Run(true)
 expect(h.Decision,'abandon','never-arrived source continuer remains in final metadata count')
 near(h.Returns[1].At,60,.001,'no guessed source departure admits partial party')
end
do
 local h = host()
 local a, b, c = h:Player(1,packet(3,true)), h:Player(2,packet(3,false)), h:Player(3,packet(3,false))
 h:Add(a); h:At(1,function() h:Remove(a) end)
 local rejoined = h:Player(1,packet(3,false))
 h:At(2,function() h:Add(rejoined) end)
 h:At(3,function() h:Add(b) end); h:At(5,function() h:Add(c) end)
 h:Run(true)
 expect(h.Decision,'admit','rejoined UserId participates in the original final cohort')
 near(h.AdmissionAt,5,.21,'rejoin restores count and still waits for final member')
 expect(h.Group.Expected,3,'rejoin removes its previous departure deduction')
 expect(#h.Group.Members,3,'all current cohort members are preserved')
end
do
 local h = host()
 local a, b = h:Player(1,packet(2,true)), h:Player(2,packet(2,false))
 h:Add(a); h:At(1,function() a.JoinDataFails=true end)
 h:At(3,function() h:Add(b) end)
 h:At(5,function() a.JoinDataFails=false end)
 h:Run(true)
 expect(h.Decision,'admit','temporary join data failure can recover')
 expect(h.AdmissionAt>=5,true,'present member with unreadable packet is not treated as disconnected')
 expect(h.Group.Expected,2,'read error never decrements cohort count')
 expect(#h.Group.Members,2,'both present players are admitted after packet recovery')
end
print('Round loading host: '..checks..' checks passed (actual host blocks; fake Roblox boundaries)')
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    manager = (SERVER / "GameManager.Script.lua").read_text(encoding="utf-8")
    loading = (SERVER / "Round Loading Runtime.ModuleScript.lua").read_text(encoding="utf-8")
    routing = (SERVER / "Round Completion Routing.ModuleScript.lua").read_text(encoding="utf-8")
    source = "\n".join([
        "local Loading = (function()\n" + loading + "\nend)()",
        "local Routing = (function()\n" + routing + "\nend)()",
        COMMON,
        "captureArrival = function(player, packet)\n" + section(
            manager,
            " if IS_RESERVED_ROUND_SERVER then\n  -- PlayerAdded can be followed",
            '\n if type(packet) == "table" and packet.ReturnToLobby',
        ) + "\nend",
        section(manager, "local function fireGroup(group, ...)", "\n-- Level 1 and Level 3"),
        section(manager, "local function livePlayers(group)", "\ncleanupActiveWorld = function()"),
        section(manager, "recoverFailedEntry = function(attempt, reason, arrivals)", "\nlocal playRound"),
        section(manager, "local function arrivalEntries()", "\nif IS_RESERVED_ROUND_SERVER then"),
        HOST_END,
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="round-loading-host-") as directory:
        fixture = Path(directory) / "round_loading_host.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == "__main__":
    main()
