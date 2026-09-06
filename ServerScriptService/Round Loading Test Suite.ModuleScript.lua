-- Exercises the production entry runtime with an injected scheduler. No real
-- teleport, character reload, MemoryStore request or sixty-second wait.
local Loading = require(script.Parent:WaitForChild("Round Loading Runtime"))
local Routing = require(script.Parent:WaitForChild("Round Completion Routing"))
local Suite = {}

local function harness()
 local clock = {Now = 0, Queue = {}, Steps = 0}
 local mainThread = coroutine.running()
 local env = {Identity = "test", Notices = {}, Failures = {}, Valid = true}
 local function schedule(after, callback)
  clock.Queue[#clock.Queue + 1] = {At = clock.Now + after, Callback = callback}
 end
 function clock.Advance(seconds)
  local target = clock.Now + seconds
  while true do
   table.sort(clock.Queue, function(a, b) return a.At < b.At end)
   local item = clock.Queue[1]
   if not item or item.At > target then break end
   table.remove(clock.Queue, 1)
   clock.Now = item.At
   clock.Steps += 1
   assert(clock.Steps < 100000, "loading fake clock exceeded its bounded event budget")
   item.Callback()
  end
  clock.Now = target
 end
 env.Now = function() return clock.Now end
 env.Delay = schedule
 env.Wait = function(seconds)
  if coroutine.running() ~= mainThread then return coroutine.yield(seconds or .05) end
  clock.Advance(seconds or .05)
 end
 env.Spawn = function(callback)
  local thread = coroutine.create(callback)
  local function resume()
   local ok, delay = coroutine.resume(thread)
   assert(ok, delay)
   if coroutine.status(thread) ~= "dead" then schedule(delay or .05, resume) end
  end
  resume()
 end
 env.Present = function(member) return not member.Left end
 env.Validate = function(member, expected)
  return env.Valid and member.Character == expected.Character and not member.Dead
 end
 env.Prepare = function(member, attempt, expected)
  env.Notices[#env.Notices + 1] = {Member = member, Token = attempt.Token, Expected = expected}
 end
 env.Failed = function(attempt, reason)
  env.Failures[#env.Failures + 1] = {At = clock.Now, Attempt = attempt, Reason = reason}
 end
 return Loading.New(env), env, clock
end

function Suite.RunAll()
 local checks, failures, lines = 0, 0, {}
 local function check(ok, message)
  checks += 1
  lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. message
  if not ok then failures += 1 end
 end
 local function member() return {Character = {}} end
 local function prepare(attempt, player)
  attempt:Prepare(player, player.Character, 2, {})
 end
 local function ack(attempt, player, token)
  return attempt:Acknowledge(player, {Token = token or attempt.Token, Level = 2, Character = player.Character})
 end
 do
  local rt, env, clock = harness()
  local a, b = member(), member()
  local attempt = rt:Begin({a, b})
  prepare(attempt, a); prepare(attempt, b)
  check(#env.Notices == 2, "preparation is sent immediately, before serial work on other members")
  env.Delay(59, function() ack(attempt, a); ack(attempt, b) end)
  check(attempt:AwaitReady(), "last member ready at 59 seconds releases the whole barrier")
  check(attempt:Commit() and attempt.State == "ready", "readiness commits exactly one entry")
  clock.Advance(2)
  check(#env.Failures == 0, "the original watchdog cannot fail a committed entry")
  check(not attempt:Commit(), "duplicate commit is refused")
 end
 do
  local rt, env, clock = harness()
  local a, b = member(), member()
  local attempt = rt:Begin({a, b})
  prepare(attempt, a); prepare(attempt, b); ack(attempt, a)
  check(not attempt:AwaitReady(), "one missing client fails the entire barrier")
  check(#env.Failures == 1 and env.Failures[1].At == 60, "one shared deadline fails at 60 seconds")
  check(not attempt:Commit() and not ack(attempt, b), "a late client cannot start an expired group")
  clock.Advance(60)
  check(#env.Failures == 1, "failure recovery is requested once")
 end
 do
  local rt, env, clock = harness()
  local a = member()
  local attempt = rt:Begin({a})
  local gate = Loading.NewCharacterGate(env.Wait)
  local owned, finished, workerToken = false, false, nil
  local ok = attempt:Run(function()
   workerToken = gate:Acquire(function() return attempt:IsOpen() end)
   owned = true
   env.Wait(120)
   gate:Release(workerToken)
   owned, finished = false, true
   return a.Character
  end)
  check(not ok and clock.Now >= 60 and clock.Now < 60.2, "a hung engine request cannot delay the caller's error")
  check(owned and not finished, "timeout does not release the still-running worker's lock")
  check(not gate:Release({}) and gate.Owner == workerToken, "foreign cleanup cannot release the engine worker's actual gate")
  check(gate:Acquire(function() return attempt:IsOpen() end) == nil, "an expired queued load never starts an engine operation")
  clock.Advance(61)
  check(not owned and finished, "only actual engine completion releases ownership")
  check(gate.Owner == nil and not gate:Release(workerToken), "the actual gate releases once, only after the worker returns")
  check(attempt.State == "failed" and #env.Failures == 1, "late worker success cannot resurrect the expired entry")
 end
 do
  local rt, env, clock = harness()
  local a = member()
  local attempt = rt:Begin({a})
  local ran, result = attempt:Run(function() env.Wait(45); return "built" end)
  check(ran and result == "built", "a yielding world build completes through the real runtime")
  prepare(attempt, a)
  check(attempt:Remaining() > 14.8 and attempt:Remaining() <= 15, "generation leaves only the remaining shared budget")
  check(not attempt:AwaitReady() and env.Failures[1].At == 60, "client waiting does not reset the group deadline")
 end
 do
  local rt, env, clock = harness()
  local a = member()
  local attempt = rt:Begin({a})
  prepare(attempt, a)
  check(not ack(attempt, a, "old-token"), "stale attempt acknowledgement is refused")
  local old = a.Character
  a.Character = {}
  check(not ack(attempt, a), "a replacement character does not inherit old readiness")
  a.Character = old
  env.Valid = false
  check(not ack(attempt, a), "a client cannot overrule server placement validation")
  env.Valid = true
  check(ack(attempt, a), "matching current character and placement are accepted")
  clock.Advance(2.1)
  check(not attempt:Commit(), "readiness older than two seconds cannot commit")
  check(ack(attempt, a) and attempt:Commit(), "fresh repeated acknowledgement restores valid readiness")
 end
 do
  local rt, env, clock = harness()
  local a, b = member(), member()
  local original = {a, b}
  local attempt = rt:Begin(original)
  table.remove(original)
  check(#attempt.Members == 2, "entry keeps its roster instead of mutating the caller's array")
  prepare(attempt, a); ack(attempt, a); b.Left = true
  check(attempt:AwaitReady() and attempt:Commit(), "a real destination disconnect no longer blocks connected members")
  local empty = rt:Begin({b})
  check(not empty:AwaitReady() and empty.Reason == "PARTY_LEFT", "zero surviving members never starts a round")
  local idle = rt:Begin({a})
  clock.Advance(60)
  check(idle.State == "failed", "deadline runs even when no entry wait is running")
 end
 do
  local rt, env = harness()
  local attempt = rt:Begin({member()})
  check(not attempt:Run(function() error("scripted build error") end), "builder exception uses common recovery")
  check(attempt.Reason == "LOADING_ERROR" and #env.Failures == 1, "an exception cannot bypass terminal failure")
 end
 do
  local snapshot = Loading.CohortSnapshot("source:1", 3, {20, 10, 20})
  local ids, count = Loading.ReadCohort(snapshot, "source:1", 3)
  check(count == 2 and ids[10] and ids[20], "final cohort carries exact deduplicated member identities")
  check(Loading.ReadCohort(snapshot, "other-session", 3) == nil, "another session's metadata is rejected")
  check(Loading.ReadCohort(snapshot, "source:1", 2) == nil, "another level's metadata is rejected")
  snapshot.UserIds = {10, 10}
  check(Loading.ReadCohort(snapshot, "source:1", 3) == nil, "duplicate metadata cannot inflate readiness")
  local roster = Routing.NewRoster({10, 20, 30})
  Routing.RecordDecision(roster, 10, Routing.Continuing)
  Routing.MarkDeparted(roster, 10)
  Routing.NoteDeparture(roster, 10)
  Routing.RecordDecision(roster, 20, Routing.Continuing)
  Routing.RecordDecision(roster, 30, Routing.Returning)
  check(Routing.ExpectedContinuers(roster, function(id) return id ~= 10 end) == 2,
   "immediate departure stays counted and a legitimate opt-out does not")
  local state = {Now = 35, LoadingDeadline = 60, Arrived = 1, Expected = 2, Final = false}
  check(Routing.ArrivalDecision(state) == "wait", "an estimate cannot admit after the old staging cap")
  state.Final = true
  check(Routing.ArrivalDecision(state) == "wait", "a short final cohort cannot admit after the old horizon")
  state.Arrived = 2
  check(Routing.ArrivalDecision(state) == "admit", "an exact complete final cohort admits")
  state.Now = 60
  check(Routing.ArrivalDecision(state) == "abandon", "even final readiness cannot revive an expired loading attempt")
  state.Now, state.Arrived, state.Final = 59, 0, false
  check(Routing.ArrivalDecision(state) == "wait", "missing metadata stays bounded by the one shared deadline")
 end
 do
  local tracker = Loading.NewArrivalTracker(Routing.SelectArrivalSession)
  local a, b = {UserId = 10}, {UserId = 20}
  local function entry(player, final, expected)
   return {Member = player, Data = Routing.ArrivalPacket({
    SessionId = "destination:1", Level = 3, Final = final, Expected = expected,
    Deadline = 15,
   })}
  end
  local first = {entry(a, true, 2)}
  tracker:Observe(first)
  local group = tracker:Apply(Routing.SelectArrivalSession(first))
  check(group.Expected == 2 and #group.Members == 1, "a source departure still in transit remains expected")
  local later = {entry(b, false, 2)}
  tracker:Observe(later)
  local packet = Routing.SelectArrivalSession(later)
  group = tracker:Apply(packet)
  check(group.Final and group.Expected == 1 and #group.Members == 1,
   "a destination departure is deducted and its final packet survives its carrier")
  check(packet.Final == false and packet.Expected == 2,
   "destination accounting does not rewrite the original teleport packet")
  check(tracker:Apply(group).Expected == 1, "repeated polls cannot deduct the same departure twice")
  local reconnect = {UserId = 10}
  local together = {entry(reconnect, false, 2), entry(b, false, 2)}
  tracker:Observe(together)
  group = tracker:Apply(Routing.SelectArrivalSession(together))
  check(group.Expected == 2 and #group.Members == 2, "same-UserId destination reconnect restores the expected member")
  local unreadable = {{Member = reconnect, Data = nil}, entry(b, false, 2)}
  tracker:Observe(unreadable)
  group = tracker:Apply(Routing.SelectArrivalSession(unreadable))
  check(group.Expected == 2 and #group.Members == 1, "GetJoinData failure for a present player is not a departure")
  local missing = Loading.NewArrivalTracker(Routing.SelectArrivalSession)
  missing:Observe({entry(a, true, 3)})
  missing:Observe(later)
  group = missing:Apply(Routing.SelectArrivalSession(later))
  check(group.Expected == 2 and #group.Members == 1,
   "deducting a proven departure never deducts a different never-arrived continuer")
  local metadata = Loading.NewArrivalTracker(Routing.SelectArrivalSession)
  local outsider = {UserId = 99}
  metadata:Observe({entry(a, false, 3), entry(outsider, false, 3)})
  local authoritative = Routing.SelectArrivalSession({entry(a, false, 3)})
  authoritative.Expected, authoritative.Final = 2, true
  authoritative.CohortUserIds = {[10] = true, [20] = true}
  metadata:Apply(authoritative)
  metadata:Observe(later)
  group = metadata:Apply(Routing.SelectArrivalSession(later))
  check(group.Expected == 1 and group.Final,
   "exact metadata deducts only observed departures who belong to that final cohort")
  local quick = Loading.NewArrivalTracker(Routing.SelectArrivalSession)
  quick:RememberArrival(entry(a, true, 2))
  quick:Observe(later)
  group = quick:Apply(Routing.SelectArrivalSession(later))
  check(group.Expected == 1 and group.Final and #group.Members == 1,
   "PlayerAdded evidence preserves a join and departure between admission polls")
 end
 do
  local a, b = {UserId = 10}, {UserId = 20}
  local function entry(player, count, final)
   return {Member = player, Data = {
    BackroomsRound = true, Level = 2, RoundSessionId = "malformed-cohort",
    ExpectedContinuers = count, FinalCohort = final,
   }}
  end
  local incomplete = entry(a, nil, true)
  local valid = entry(b, 3, true)
  local group = Routing.SelectArrivalSession({incomplete})
  check(group and not group.Final and group.Expected == nil,
   "a final flag without a count remains an unconfirmed arrival")
  local ok, recovered = pcall(Routing.SelectArrivalSession, {incomplete, valid})
  check(ok and recovered.Final and recovered.Expected == 3 and #recovered.Members == 2,
   "a valid final packet after missing metadata recovers without a nil comparison")
  group = Routing.SelectArrivalSession({entry(a, 2, false), entry(b, nil, true)})
  check(group and not group.Final and group.Expected == 2,
   "a count-less final flag cannot promote an earlier estimate to exact authority")
  check(Routing.ArrivalDecision({Now = 10, LoadingDeadline = 60,
   Arrived = #group.Members, Expected = group.Expected, Final = group.Final}) == "wait",
   "matching an estimate still waits for exact metadata after a malformed final packet")
  group = Routing.SelectArrivalSession({valid, incomplete})
  check(group.Final and group.Expected == 3,
   "a later malformed packet cannot lower or revoke valid final authority")
  for _, invalid in ipairs({0 / 0, math.huge, -math.huge, -1, 1.5}) do
   group = Routing.SelectArrivalSession({entry(a, invalid, true)})
   check(group and not group.Final and group.Expected == nil,
    "invalid final count stays unconfirmed: " .. tostring(invalid))
  end
  group = Routing.SelectArrivalSession({entry(a, 0, true)})
  check(group.Final and group.Expected == 0 and Routing.ArrivalDecision({
   Now = 10, LoadingDeadline = 60, Arrived = 0, Expected = group.Expected, Final = group.Final,
  }) == "wait", "a valid empty final cohort is retained but never starts an empty round")
  group = Routing.SelectArrivalSession({entry(a, "3", true)})
  check(group.Final and group.Expected == 3, "numeric string counts retain supported packet compatibility")
 end
 for size = 2, 6 do
  local rt, env = harness()
  local party = {}
  for index = 1, size do party[index] = member() end
  local attempt = rt:Begin(party)
  for _, player in ipairs(party) do prepare(attempt, player) end
  env.Delay(1, function()
   for _, player in ipairs(party) do ack(attempt, player) end
  end)
  check(attempt:AwaitReady() and attempt:Commit(),
   tostring(size) .. "-player party enters only after every client acknowledges")

  rt, env = harness()
  attempt = rt:Begin(party)
  for _, player in ipairs(party) do prepare(attempt, player) end
  env.Delay(1, function()
   for index = 1, size - 1 do ack(attempt, party[index]) end
  end)
  check(not attempt:AwaitReady() and #env.Failures == 1 and env.Failures[1].At == 60
   and not ack(attempt, party[size]) and not attempt:Commit(),
   tostring(size) .. "-player party recovers once at 60 seconds when one client never becomes ready")
 end
 local expected = 72
 check(checks == expected, "suite ran its declared " .. expected .. " behavioral checks")
 lines[#lines + 1] = string.format("TOTAL: %d checks, %d failed", checks, failures)
 return table.concat(lines, "\n"), failures
end
return Suite
