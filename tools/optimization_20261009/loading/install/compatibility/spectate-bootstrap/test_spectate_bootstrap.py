"""Execute exact proposed spectator helpers against isolated engine-boundary mocks.

No Studio calls, runtime source writes, staging, commit, or backup operations.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess

HERE = Path(__file__).resolve().parent


def span(source: str, start: str, end: str) -> str:
    assert source.count(start) == 1, f"ambiguous production start: {start}"
    assert source.count(end) == 1, f"ambiguous production end: {end}"
    first, last = source.index(start), source.index(end)
    assert first < last
    return source[first:last]


SERVER = r'''
local function serverScenario()
 local c = baseScenario()
 local Players, workspace, inRound = c.Players, c.World, c.inRound
 local os = {clock = function() return c.Now end}
 local task = {
  spawn = function(callback) table.insert(c.Tasks, coroutine.create(callback)) end,
  wait = function() coroutine.yield(); return true end,
 }
 local function warn(message) table.insert(c.Warnings, message) end
 local status = {}
 function status:FireClient(player, kind, payload)
  table.insert(c.Messages, {Player = player, Kind = kind, Payload = payload})
 end
__SERVER_SOURCE__
 c.Request, c.Select = requestSpectateCandidates, setSpectateTarget
 c.Reconcile, c.Clear = republishSpectatorCounts, clearSpectatorCounts
 c.Targets, c.Records = spectateTargets, spectateFocus.Records
 function c:LastResponse()
  local message = self.Messages[#self.Messages]
  if not message then return nil end
  assert(message.Kind == "spectatecandidates", "candidate response protocol changed")
  return {Serial = message.Payload.Serial, Ids = message.Payload.UserIds}
 end
 c.RateOwned = function(player) return spectateCandidateRequests[player] ~= nil end
 c:TickTasks() -- prime the unchanged periodic coroutine through its first wait
 return c
end
'''

CLIENT = r'''
local function clientScenario()
 local c = baseScenario()
 local player = c:Player(-1, 0)
 c.LocalPlayer = player
 c.Players.LocalPlayer = player
 local Players, workspace = c.Players, c.World
 local task = {
  spawn = function(callback) table.insert(c.Tasks, coroutine.create(callback)) end,
  wait = function() coroutine.yield(); return true end,
 }
 local remote = {OnClientEvent = signal()}
 function remote:FireServer(kind, argument)
  table.insert(c.Requests, {Kind = kind, Argument = argument})
 end
 local spectating, targets, idx, spectated, snapCam = false, {}, 1, nil, true
 local hidden, hiddenParts, hiddenPartsConn = nil, {}, nil
 local lastBeamProfile, lastOn = nil, nil
 local band = {copy = function(target) c.BandTarget = target end}
 local prevButton, nextButton, exitButton, core, spill, beamMount = {}, {}, {}, {}, {}, {}
 local UIDevice = {SetInteractive = function() end}
 local function applySpectateLayout() end
 local function unhide() c.Unhides = (c.Unhides or 0) + 1 end
__REPORT_SOURCE__
__CLIENT_HELPERS__
__WATCH_SOURCE__
__START_STOP_SOURCE__
__ROUND_END_SOURCE__
__PERIODIC_SOURCE__
 c.Start, c.Stop, c.Tick = startSpectate, stopSpectate, function() c.Now += 1; c:TickTasks() end
 c.Refresh = c.Tick
 c.Cycle = function(offset) watch(idx + offset) end
 function c:SelectedId() return spectated and spectated.UserId end
 function c:RequestCount()
  local total = 0
  for _, request in ipairs(self.Requests) do if request.Kind == "spectatecandidates" then total += 1 end end
  return total
 end
 function c:LastRequestSerial()
  for i = #self.Requests, 1, -1 do
   if self.Requests[i].Kind == "spectatecandidates" then return self.Requests[i].Argument end
  end
 end
 function c:LastTargetId()
  for i = #self.Requests, 1, -1 do
   if self.Requests[i].Kind == "spectatetarget" then return self.Requests[i].Argument end
  end
 end
 function c:TargetReportCount()
  local total = 0
  for _, request in ipairs(self.Requests) do if request.Kind == "spectatetarget" then total += 1 end end
  return total
 end
 function c:Response(serial, ids)
  remote.OnClientEvent:Fire("spectatecandidates", {Serial = serial, UserIds = ids})
 end
 c.RawResponse = function(payload) return receiveSpectateCandidates(payload) end
 c.Respawn = function()
  player.Character = character(c.World, 100)
  onChar(player.Character)
 end
 c.RoundEnded = function() workspace:GetAttributeChangedSignal("RoundActive"):Fire() end
 c:TickTasks() -- prime the exact production one-second loop through its first wait
 return c
end
'''


def build(server: str, client: str) -> tuple[str, dict]:
    for marker in ("-- SPECTATE_BOOTSTRAP_SERVER_BEGIN", "-- SPECTATE_BOOTSTRAP_SERVER_END"):
        assert server.count(marker) == 1, marker
    for marker in ("-- SPECTATE_BOOTSTRAP_CLIENT_BEGIN", "-- SPECTATE_BOOTSTRAP_CLIENT_END"):
        assert client.count(marker) == 1, marker
    assert re.search(r'elseif message == "spectatecandidates" then\s+requestSpectateCandidates\(player, requestSerial\)', server)
    server_source = span(server, "local spectateTargets = {}", "local lobbyBriefingReady")
    sections = {
        "REPORT_SOURCE": span(client, "local reportedTarget = false", 'local gui = Instance.new("ScreenGui")'),
        "CLIENT_HELPERS": span(client, "local watch -- response handler", "-- SPECTATE_BOOTSTRAP_CLIENT_END"),
        "WATCH_SOURCE": span(client, "watch = function(i)", "-- drive the POV camera"),
        "START_STOP_SOURCE": span(client, "local function startSpectate()", "-- C_ONE_SPECTATE_CAMERA"),
        "ROUND_END_SOURCE": span(client, 'workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()', "if player.Character then"),
        "PERIODIC_SOURCE": client[client.index("-- if the teammate you're watching"):],
    }
    client_fixture = CLIENT
    for key, value in sections.items():
        client_fixture = client_fixture.replace(f"__{key}__", value)
    code = (HERE / "fixture_preamble.luau").read_text(encoding="utf-8")
    code += SERVER.replace("__SERVER_SOURCE__", server_source) + client_fixture
    code += (HERE / "server_checks.luau").read_text(encoding="utf-8")
    code += (HERE / "client_checks.luau").read_text(encoding="utf-8")
    code += (HERE / "integration_checks.luau").read_text(encoding="utf-8")
    code += '\nprint("spectator bootstrap contract checks: " .. checks)\nreturn {checks = checks, realGameplayStreamingPerformancePass = false}\n'
    assert not re.search(r"__[A-Z_]+__", code), "unsubstituted fixture section"
    fingerprints = {"server": hashlib.sha256(server_source.encode()).hexdigest()}
    fingerprints.update({key: hashlib.sha256(value.encode()).hexdigest() for key, value in sections.items()})
    return code, fingerprints


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", default=os.environ.get("LUAU_BIN"))
    parser.add_argument("--server-source", type=Path, default=HERE / "GameManager.proposed.luau")
    parser.add_argument("--client-source", type=Path, default=HERE / "SpectateController.proposed.luau")
    args = parser.parse_args()
    if not args.luau:
        raise SystemExit("Supply --luau or LUAU_BIN; no tests executed.")
    raw_server, raw_client = args.server_source.read_bytes(), args.client_source.read_bytes()
    code, sections = build(raw_server.decode("utf-8"), raw_client.decode("utf-8"))
    fixture = HERE / "bootstrap-contract.luau"
    fixture.write_text(code, encoding="utf-8", newline="\n")
    compiler = Path(args.luau).with_name("luau-compile.exe")
    for path in (args.server_source, args.client_source, fixture):
        subprocess.run([str(compiler), "--binary", str(path)], check=True, stdout=subprocess.DEVNULL)
    result = subprocess.run([args.luau, str(fixture)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stderr.strip() or result.stdout.strip() or f"Luau exited {result.returncode}")
    stdout = result.stdout.strip()
    match = re.search(r"spectator bootstrap contract checks: (\d+)", stdout)
    assert match, stdout
    probe = HERE / "offline-contract-probe.luau"
    probe.write_text("return function()\n" + code + "\nend\n", encoding="utf-8", newline="\n")
    subprocess.run([str(compiler), "--binary", str(probe)], check=True, stdout=subprocess.DEVNULL)
    receipt = {
        "kind": "offline exact-production-helper contract",
        "checks": int(match.group(1)), "stdout": stdout,
        "serverSourceSha256": hashlib.sha256(raw_server).hexdigest(),
        "clientSourceSha256": hashlib.sha256(raw_client).hexdigest(),
        "productionSectionSha256": sections,
        "fixtureSha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
        "fullProposedSourcesCompiled": True,
        "nativeProbeRun": False, "realReplicationFocusCalls": False,
        "realGameplayStreamingPerformancePass": False,
    }
    (HERE / "offline-result.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(stdout)


if __name__ == "__main__":
    main()
