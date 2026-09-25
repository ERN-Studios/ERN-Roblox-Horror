"""Run GameManager's real post-win window and TeleportInitFailed handler offline.

AUDIT_FIX_20260924, two teleport failures that never recovered:
  1. The post-win window never reserved the next-level server, so a retried
     member got ShouldReserveServer again and landed alone in a new server.
     The window must reserve ONCE and hand the code on (never for Level 3).
  2. A station launch holds no transfer claim, so its TeleportInitFailed was
     dropped and the "loadinggame" cover stayed up in the lobby.
The REAL Round Completion Routing module and the REAL GameManager blocks are
sliced in; TeleportService, the remote and the clock are fakes. Real teleports
still need a published-place check. Set LUAU_BIN or put luau on PATH.
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


PRELUDE = r'''
local checks = 0
local function expect(actual, wanted, message)
 checks += 1
 assert(actual == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(actual))
end
local function scheduler()
 local clock = {Now=0, Queue={}, Sequence=0}
 local mainThread = coroutine.running()
 local task = {}
 local function schedule(after, callback)
  clock.Sequence += 1
  table.insert(clock.Queue, {At=clock.Now+after, Order=clock.Sequence, Callback=callback})
 end
 function task.wait(seconds)
  seconds = seconds or .05
  if coroutine.running() ~= mainThread then return coroutine.yield(seconds) end
  local target = clock.Now + seconds
  while true do
   table.sort(clock.Queue, function(a,b) return a.At < b.At or (a.At == b.At and a.Order < b.Order) end)
   local item = clock.Queue[1]
   if not item or item.At > target then break end
   table.remove(clock.Queue, 1)
   clock.Now = item.At
   item.Callback()
  end
  clock.Now = target
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
 return clock, task
end
'''

POST_WIN_HEAD = r'''
local function postWin(level, reserve)
 local clock, task = scheduler()
 local calls = 0
 local TeleportService = {}
 function TeleportService:ReserveServer(placeId)
  calls += 1
  task.wait(.5)
  return reserve(placeId)
 end
 local game = {JobId='offline-source', PlaceId=42}
 local workspace = {}
 function workspace:GetServerTimeNow() return 1000 + clock.Now end
 local Players = {}
 local IS_STUDIO = false
 local postWinSerial, activeLevel, activePostWin = 0, level, nil
 local pendingTeleports = {}
 local print, warn = function() end, function() end
 local function fireGroup() end
 local function publishPostWinChoices() end
 local function publishFinalCohort() end
 local function stillHere(player) return player.Parent == Players end
'''

POST_WIN_TAIL = r'''
 local outcome = runPostWinIntermission({{UserId=1, Parent=Players}, {UserId=2, Parent=Players}}, 30, 2, nil)
 return outcome, calls
end
'''

HANDLER_HEAD = r'''
local function initFailed(options)
 local notices, handler = {}, nil
 local TeleportService = {TeleportInitFailed={}}
 function TeleportService.TeleportInitFailed:Connect(fn) handler = fn end
 local Players = {}
 local IS_RESERVED_ROUND_SERVER = options.Reserved == true
 local inRound = {}
 local transfers = {}
 function transfers:ReportFailure() return options.Claimed and {} or nil end
 local status = {}
 function status:FireClient(_, kind) table.insert(notices, kind) end
 local warn = function() end
'''

HANDLER_TAIL = r'''
 local player = {Name='offline', Parent=Players}
 if options.Gone then player.Parent = nil end
 if options.InRound then inRound[player] = true end
 local packet = options.Packet or {Station=1, LaunchToken='offline:station1:0'}
 local teleportOptions = {GetTeleportData=function() return packet end}
 handler(player, 'Failure', 'offline failure', 42, teleportOptions)
 return notices
end
'''

TESTS = r'''
do
 local outcome, calls = postWin(1, function() return 'CODE-1' end)
 expect(outcome.NextLevel, 2, 'Level 1 continues to Level 2')
 expect(calls, 1, 'the window reserves the next-level server exactly once')
 expect(outcome.AccessCode, 'CODE-1', 'the settled window hands its reservation to every continuer')
end
do
 local outcome, calls = postWin(3, function() return 'CODE-3' end)
 expect(outcome.NextLevel, nil, 'Level 3 has no next level')
 expect(calls, 0, 'a Level 3 window reserves nothing')
 expect(outcome.AccessCode, nil, 'and hands on no code')
end
do
 local outcome, calls = postWin(2, function() error('reservation refused') end)
 expect(calls, 1, 'a refused reservation is tried once')
 expect(outcome.AccessCode, nil, 'and falls back to reserving on dispatch')
end
do
 local notices = initFailed({})
 expect(#notices, 1, 'an unclaimed station failure in the lobby answers once')
 expect(notices[1], 'lobby', 'and lifts the loading cover')
 expect(#initFailed({Claimed=true}), 0, 'a failure the runtime owns is left to the runtime')
 expect(#initFailed({Reserved=true}), 0, 'a stale report on a round server never resets the lobby UI')
 expect(#initFailed({InRound=true}), 0, 'a player in a round is not sent lobby UI')
 expect(#initFailed({Gone=true}), 0, 'a player who already left gets nothing')
end
print('Teleport recovery: ' .. checks .. ' checks passed (real post-win window and TeleportInitFailed handler, fake TeleportService)')
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    manager = (SERVER / "GameManager.Script.lua").read_text(encoding="utf-8-sig")
    routing = (SERVER / "Round Completion Routing.ModuleScript.lua").read_text(encoding="utf-8-sig")
    source = "\n".join([
        "local Routing = (function()\n" + routing + "\nend)()",
        PRELUDE,
        POST_WIN_HEAD,
        section(manager, "local function runPostWinIntermission(", "\nlocal function continueStudioCampaign("),
        POST_WIN_TAIL,
        HANDLER_HEAD,
        section(manager, "TeleportService.TeleportInitFailed:Connect(function(", "\nlocal function runPostWinIntermission("),
        HANDLER_TAIL,
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="teleport-recovery-") as directory:
        fixture = Path(directory) / "teleport_recovery.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=60)


if __name__ == "__main__":
    main()
