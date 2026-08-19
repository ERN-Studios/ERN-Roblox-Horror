"""End-to-end test of tools/push_repo_to_studio.py against a fake Studio.

Dev-only: touches nothing in the game and never contacts a real Studio. It runs
the push tool's ACTUAL generated Luau through the real luau interpreter against
a stubbed DataModel, so chunking, escaping, verification, conflict detection,
compare-and-swap and buffer cleanup are all exercised for real.

    LUAU_BIN=/path/to/luau python tools/tests/test_push_repo_to_studio.py


Seeds the fake DataModel with the PRE-EDIT source of every pending script
(taken from git at origin/main, i.e. exactly what the real Studio still holds),
runs the real tool, and verifies Studio ends up byte-identical to the repo.
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRATCH = Path(__file__).resolve().parent
REPO = SCRATCH.parents[1]
# The commit whose content Studio still holds for the pending scripts. Override
# with PUSH_TEST_BASE when re-running this after the audit batch has landed.
BASE_COMMIT = os.environ.get(
    "PUSH_TEST_BASE", "4092c4886ce5a4962783e2821ae632c50c4f62d7")

sys.path.insert(0, str(SCRATCH))
import fakestudio  # noqa: E402

failures: list[str] = []
passes: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    (passes if condition else failures).append(f"{name}{(' — ' + detail) if detail else ''}")
    print(("  PASS  " if condition else "  FAIL  ") + name + (f"  [{detail}]" if detail else ""))


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def git_show(path: str) -> str | None:
    proc = subprocess.run(["git", "-C", str(REPO), "show", f"{BASE_COMMIT}:{path}"],
                          capture_output=True, text=True)
    return proc.stdout if proc.returncode == 0 else None


def load_tool(repo_root: Path):
    """Import push_repo_to_studio with PROJECT_ROOT pointed at a scratch repo."""
    spec = importlib.util.spec_from_file_location(
        "push_repo_to_studio", repo_root / "tools" / "push_repo_to_studio.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["push_repo_to_studio"] = module
    spec.loader.exec_module(module)
    module.PROJECT_ROOT = repo_root
    module.MANIFEST_PATH = repo_root / "studio-sync-manifest.json"
    return module


def fresh_repo() -> Path:
    """A throwaway copy of the repo so tests never mutate the real manifest."""
    workdir = Path(tempfile.mkdtemp(prefix="pushtest-"))
    target = workdir / "repo"
    target.mkdir()
    shutil.copytree(REPO / "tools", target / "tools")
    shutil.copy2(REPO / "studio-sync-manifest.json", target / "studio-sync-manifest.json")
    manifest = json.loads((REPO / "studio-sync-manifest.json").read_text())
    for item in manifest["items"]:
        source = REPO / item["file"]
        if source.exists():
            destination = target / item["file"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
    return target


def pending_items(repo_root: Path) -> list[dict]:
    manifest = json.loads((repo_root / "studio-sync-manifest.json").read_text())
    return [i for i in manifest["items"] if i.get("status") == "pending-studio-push"]


def seed(studio: fakestudio.FakeStudio, items: list[dict], repo_root: Path,
         overrides: dict[str, str] | None = None) -> None:
    overrides = overrides or {}
    for item in items:
        if item["file"] in overrides:
            content = overrides[item["file"]]
        else:
            content = git_show(item["file"])
            if content is None:  # renamed file: use pre-edit name
                content = git_show("ServerScriptService/EntityAnimation.Script.Lua") or ""
        studio.add_script(item["studioPath"], item["className"], content)


print("=" * 72)
print("BASELINE INTEGRITY: does studioSha256Before match what Studio really holds?")
print("=" * 72)
real_manifest = json.loads((REPO / "studio-sync-manifest.json").read_text())
real_pending = [i for i in real_manifest["items"] if i.get("status") == "pending-studio-push"]
print(f"pending entries: {len(real_pending)}")
mismatched = []
for item in real_pending:
    base = git_show(item["file"])
    if base is None and "EntityAnimation" in item["file"]:
        base = git_show("ServerScriptService/EntityAnimation.Script.Lua")
    if base is None:
        mismatched.append((item["file"], "no base content"))
    elif sha(base.replace("\r\n", "\n")) != item.get("studioSha256Before"):
        mismatched.append((item["file"], "hash differs from pre-audit git content"))
check("every studioSha256Before equals the pre-audit (origin/main) content",
      not mismatched, f"{len(mismatched)} mismatched: {mismatched[:3]}")

for item in real_pending:
    on_disk = (REPO / item["file"]).read_text(encoding="utf-8").replace("\r\n", "\n")
    if sha(on_disk) != item["sha256"]:
        mismatched.append((item["file"], "current sha mismatch"))
check("every pending entry's sha256 matches the file on disk",
      all(m[1] != "current sha mismatch" for m in mismatched))

print()
print("=" * 72)
print("TEST 1 — full push of all pending scripts (happy path)")
print("=" * 72)
repo1 = fresh_repo()
tool1 = load_tool(repo1)
studio1 = fakestudio.FakeStudio()
items1 = pending_items(repo1)
seed(studio1, items1, repo1)
fakestudio.install(tool1, studio1)

sys.argv = ["push_repo_to_studio.py"]
exit_code = tool1.main()
check("tool exited 0", exit_code == 0, f"exit={exit_code}")
check("no Luau runtime errors", not studio1.luau_errors, str(studio1.luau_errors[:2]))

wrong = []
for item in items1:
    want = (repo1 / item["file"]).read_text(encoding="utf-8").replace("\r\n", "\n")
    got = studio1.source_of(item["studioPath"])
    if got != want:
        wrong.append(item["file"])
check(f"all {len(items1)} scripts byte-identical in Studio afterwards",
      not wrong, f"{len(wrong)} wrong: {wrong[:3]}")

manifest1 = json.loads((repo1 / "studio-sync-manifest.json").read_text())
still_pending = [i["file"] for i in manifest1["items"] if i.get("status") == "pending-studio-push"]
leftover_baseline = [i["file"] for i in manifest1["items"] if "studioSha256Before" in i]
check("manifest: nothing left pending", not still_pending, str(still_pending[:3]))
check("manifest: studioSha256Before cleared", not leftover_baseline, str(leftover_baseline[:3]))

buffers = [p for p in studio1.objects if p[-1] == "__RepoPushBuffer"]
check("no transfer buffer left behind in ServerStorage", not buffers, str(buffers))

biggest = max(items1, key=lambda i: i["bytes"])
check(f"largest file transferred intact ({biggest['file'].split('/')[-1]}, {biggest['bytes']}B)",
      studio1.source_of(biggest["studioPath"])
      == (repo1 / biggest["file"]).read_text(encoding="utf-8").replace("\r\n", "\n"))
print(f"  (luau invocations: {studio1.calls})")

print()
print("=" * 72)
print("TEST 2 — conflict detection: Studio drifted since the baseline")
print("=" * 72)
repo2 = fresh_repo()
tool2 = load_tool(repo2)
studio2 = fakestudio.FakeStudio()
items2 = pending_items(repo2)
victim = next(i for i in items2 if i["file"].endswith("GameManager.Script.lua"))
drifted = (git_show(victim["file"]) or "") + "\n-- someone edited this in Studio\n"
seed(studio2, items2, repo2, overrides={victim["file"]: drifted})
fakestudio.install(tool2, studio2)
sys.argv = ["push_repo_to_studio.py"]
exit2 = tool2.main()
check("tool signals failure when a file conflicts", exit2 == 1, f"exit={exit2}")
check("conflicting file was NOT overwritten", studio2.source_of(victim["studioPath"]) == drifted)
manifest2 = json.loads((repo2 / "studio-sync-manifest.json").read_text())
conflicted_entry = next(i for i in manifest2["items"] if i["file"] == victim["file"])
check("conflicting entry recorded as studio-push-conflict with baseline kept",
      conflicted_entry.get("status") == "studio-push-conflict"
      and "studioSha256Before" in conflicted_entry,
      str(conflicted_entry.get("status")))
others_ok = all(
    studio2.source_of(i["studioPath"]) == (repo2 / i["file"]).read_text(encoding="utf-8").replace("\r\n", "\n")
    for i in items2 if i["file"] != victim["file"])
check("DEFAULT: nothing at all was written when a conflict exists",
      all(studio2.source_of(i["studioPath"]) == (git_show(i["file"]) or "")
          for i in items2 if i["file"] != victim["file"]),
      "two-phase abort")
_ = others_ok

print()
print("=" * 72)
print("TEST 3 — idempotency: re-running after a successful push")
print("=" * 72)
sys.argv = ["push_repo_to_studio.py"]
exit3 = tool1.main()
check("second run is a clean no-op", exit3 == 0, f"exit={exit3}")

print()
print("=" * 72)
print("TEST 4 — already-applied (Studio already has the new content)")
print("=" * 72)
repo4 = fresh_repo()
tool4 = load_tool(repo4)
studio4 = fakestudio.FakeStudio()
items4 = pending_items(repo4)
seed(studio4, items4, repo4, overrides={
    i["file"]: (repo4 / i["file"]).read_text(encoding="utf-8") for i in items4})
fakestudio.install(tool4, studio4)
sys.argv = ["push_repo_to_studio.py"]
exit4 = tool4.main()
check("already-applied files are accepted, not treated as conflicts", exit4 == 0, f"exit={exit4}")
manifest4 = json.loads((repo4 / "studio-sync-manifest.json").read_text())
check("already-applied entries marked synced",
      not [i for i in manifest4["items"] if i.get("status") == "pending-studio-push"])

print()
print("=" * 72)
print("TEST 5 — hostile content round-trip (unicode, escapes, CRLF, empty, huge)")
print("=" * 72)
repo5 = fresh_repo()
tool5 = load_tool(repo5)
studio5 = fakestudio.FakeStudio()
items5 = pending_items(repo5)
target = next(i for i in items5 if i["file"].endswith("DanceEmote.LocalScript.lua"))

hostile_cases = {
    "unicode + emoji": 'local s = "héllo — 🎃 ✓ ünïcode"\nprint(s)\n',
    "quotes and backslashes": 'local s = "a\\"b\\\\c"\nlocal t = [[raw \\ string]]\nprint(s, t)\n',
    "control chars": 'local s = "tab\\there\\nnewline"\nprint(s)\n',
    "no trailing newline": 'print("no trailing newline")',
    "blank lines + trailing newlines": 'print(1)\n\n\n\nprint(2)\n\n',
    "empty file": "",
    "long single line": 'local x = "' + ("A" * 90000) + '"\n',
    "many lines": "\n".join(f"print({n})" for n in range(4000)) + "\n",
    "percent signs": 'local f = string.format("%d%% of %s", 50, "x")\nprint(f)\n',
    "luau string edge": 'local s = "\\\\" .. "\\"" .. [==[nested ]] here]==]\nprint(s)\n',
}

for label, content in hostile_cases.items():
    repo_case = fresh_repo()
    tool_case = load_tool(repo_case)
    studio_case = fakestudio.FakeStudio()
    items_case = pending_items(repo_case)
    entry = next(i for i in items_case if i["file"] == target["file"])
    # write the hostile content and re-record the manifest entry for it
    (repo_case / entry["file"]).write_text(content, encoding="utf-8")
    entry_index = next(idx for idx, i in enumerate(items_case) if i["file"] == entry["file"])
    manifest_case = json.loads((repo_case / "studio-sync-manifest.json").read_text())
    for item in manifest_case["items"]:
        if item["file"] == entry["file"]:
            item["bytes"] = len(content.encode("utf-8"))
            item["sha256"] = sha(content)
        elif item.get("status") == "pending-studio-push":
            item["status"] = "synced"
            item.pop("studioSha256Before", None)
    (repo_case / "studio-sync-manifest.json").write_text(json.dumps(manifest_case, indent=2) + "\n")

    studio_case.add_script(entry["studioPath"], entry["className"], git_show(entry["file"]) or "")
    fakestudio.install(tool_case, studio_case)
    sys.argv = ["push_repo_to_studio.py"]
    try:
        code = tool_case.main()
        landed = studio_case.source_of(entry["studioPath"])
        check(f"round-trip: {label}", code == 0 and landed == content,
              f"exit={code}, len {len(landed or '')} vs {len(content)}")
    except Exception as error:  # noqa: BLE001
        check(f"round-trip: {label}", False, f"raised {type(error).__name__}: {error}")
    _ = entry_index

print()
print("=" * 72)
print("TEST 6 — script missing from Studio (renamed/deleted)")
print("=" * 72)
repo6 = fresh_repo()
tool6 = load_tool(repo6)
studio6 = fakestudio.FakeStudio()
items6 = pending_items(repo6)
seed(studio6, [i for i in items6 if not i["file"].endswith("EntityKill.Script.lua")], repo6)
fakestudio.install(tool6, studio6)
sys.argv = ["push_repo_to_studio.py", "--file", "ServerScriptService/GameManager.Script.lua"]
try:
    code6 = tool6.main()
    check("--file with a present script still works", code6 == 0, f"exit={code6}")
except Exception as error:  # noqa: BLE001
    check("--file with a present script still works", False, f"raised {error}")

print()
print("=" * 72)
print("TEST 7 — --file with spaces in the path")
print("=" * 72)
repo7 = fresh_repo()
tool7 = load_tool(repo7)
studio7 = fakestudio.FakeStudio()
items7 = pending_items(repo7)
seed(studio7, items7, repo7)
fakestudio.install(tool7, studio7)
spacey = "ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua"
sys.argv = ["push_repo_to_studio.py", "--file", spacey]
code7 = tool7.main()
spacey_item = next(i for i in items7 if i["file"] == spacey)
check("--file handles paths containing spaces", code7 == 0, f"exit={code7}")
check("that one file was pushed",
      studio7.source_of(spacey_item["studioPath"])
      == (repo7 / spacey).read_text(encoding="utf-8").replace("\r\n", "\n"))
untouched = [i for i in pending_items(repo7)]
check("other files left pending (not pushed)", len(untouched) == len(items7) - 1,
      f"{len(untouched)} pending of {len(items7)}")

print()
print("=" * 72)
print("TEST 8 — --list must never write")
print("=" * 72)
repo8 = fresh_repo()
tool8 = load_tool(repo8)
studio8 = fakestudio.FakeStudio()
items8 = pending_items(repo8)
seed(studio8, items8, repo8)
fakestudio.install(tool8, studio8)
before_manifest = (repo8 / "studio-sync-manifest.json").read_text()
sys.argv = ["push_repo_to_studio.py", "--list"]
code8 = tool8.main()
check("--list exits 0", code8 == 0)
check("--list made zero Studio calls", studio8.calls == 0, f"{studio8.calls} calls")
check("--list left the manifest untouched",
      (repo8 / "studio-sync-manifest.json").read_text() == before_manifest)



print()
print("=" * 72)
print("TEST 9 — --skip-conflicts pushes the clean files, leaves the conflict")
print("=" * 72)
repo9 = fresh_repo()
tool9 = load_tool(repo9)
studio9 = fakestudio.FakeStudio()
items9 = pending_items(repo9)
victim9 = next(i for i in items9 if i["file"].endswith("GameManager.Script.lua"))
drift9 = (git_show(victim9["file"]) or "") + "\n-- edited in Studio\n"
seed(studio9, items9, repo9, overrides={victim9["file"]: drift9})
fakestudio.install(tool9, studio9)
sys.argv = ["push_repo_to_studio.py", "--skip-conflicts"]
code9 = tool9.main()
check("--skip-conflicts still reports failure", code9 == 1, f"exit={code9}")
check("conflicting file untouched", studio9.source_of(victim9["studioPath"]) == drift9)
clean_ok = all(
    studio9.source_of(i["studioPath"]) == (repo9 / i["file"]).read_text(encoding="utf-8").replace("\r\n", "\n")
    for i in items9 if i["file"] != victim9["file"])
check("all clean files pushed", clean_ok)
m9 = json.loads((repo9 / "studio-sync-manifest.json").read_text())
c9 = next(i for i in m9["items"] if i["file"] == victim9["file"])
check("conflict recorded as studio-push-conflict (baseline preserved)",
      c9.get("status") == "studio-push-conflict" and "studioSha256Before" in c9,
      str(c9.get("status")))

print()
print("=" * 72)
print("TEST 10 — --overwrite-conflicts")
print("=" * 72)
repo10 = fresh_repo()
tool10 = load_tool(repo10)
studio10 = fakestudio.FakeStudio()
items10 = pending_items(repo10)
victim10 = next(i for i in items10 if i["file"].endswith("GameManager.Script.lua"))
seed(studio10, items10, repo10,
     overrides={victim10["file"]: (git_show(victim10["file"]) or "") + "\n-- drift\n"})
fakestudio.install(tool10, studio10)
sys.argv = ["push_repo_to_studio.py", "--overwrite-conflicts"]
code10 = tool10.main()
check("--overwrite-conflicts succeeds", code10 == 0, f"exit={code10}")
check("drifted file overwritten with repo content",
      studio10.source_of(victim10["studioPath"])
      == (repo10 / victim10["file"]).read_text(encoding="utf-8").replace("\r\n", "\n"))

print()
print("=" * 72)
print("TEST 11 — truncated staged transfer must abort BEFORE writing")
print("=" * 72)
repo11 = fresh_repo()
tool11 = load_tool(repo11)
studio11 = fakestudio.FakeStudio()
items11 = pending_items(repo11)
seed(studio11, items11, repo11)
fakestudio.install(tool11, studio11)

original_execute = studio11.execute
state = {"dropped": False}
def lossy(code):
    # silently drop the payload of one buffer append (simulates a short write)
    if "buffer.Value = buffer.Value .." in code and not state["dropped"]:
        state["dropped"] = True
        code = code.split("buffer.Value = buffer.Value ..")[0] + \
            'buffer.Value = buffer.Value .. ""\nreturn tostring(#buffer.Value)\n'
    return original_execute(code)
studio11.execute = lossy
sys.argv = ["push_repo_to_studio.py", "--file", "ServerScriptService/GameManager.Script.lua"]
code11 = tool11.main()
check("short transfer is detected", code11 == 1, f"exit={code11}")
check("live script NOT overwritten by the truncated body",
      studio11.source_of(next(i for i in items11 if i["file"].endswith("GameManager.Script.lua"))["studioPath"])
      == git_show("ServerScriptService/GameManager.Script.lua"))
studio11.execute = original_execute

print()
print("=" * 72)
print("TEST 12 — compare-and-swap catches drift between check and write")
print("=" * 72)
repo12 = fresh_repo()
tool12 = load_tool(repo12)
studio12 = fakestudio.FakeStudio()
items12 = pending_items(repo12)
seed(studio12, items12, repo12)
fakestudio.install(tool12, studio12)
target12 = next(i for i in items12 if i["file"].endswith("GameManager.Script.lua"))
original12 = studio12.execute
race = {"done": False}
def racy(code):
    # mutate the script in Studio right before the apply lands
    if "UpdateSourceAsync" in code and not race["done"]:
        race["done"] = True
        key = tuple(target12["studioPath"].split("."))
        cls, body, kind = studio12.objects[key]
        studio12.objects[key] = (cls, body + "\n-- sneaked in\n", kind)
    return original12(code)
studio12.execute = racy
sys.argv = ["push_repo_to_studio.py", "--file", "ServerScriptService/GameManager.Script.lua"]
code12 = tool12.main()
check("racing write is refused", code12 == 1, f"exit={code12}")
check("the racer's edit survived (not clobbered)",
      "sneaked in" in (studio12.source_of(target12["studioPath"]) or ""))
studio12.execute = original12

print()
print("=" * 72)
print("TEST 13 — no orphaned transfer buffer after a mid-transfer failure")
print("=" * 72)
buffers13 = [p for p in studio11.objects if p[-1] == "__RepoPushBuffer"]
check("failed push left no __RepoPushBuffer in ServerStorage", not buffers13, str(buffers13))
buffers12 = [p for p in studio12.objects if p[-1] == "__RepoPushBuffer"]
check("refused CAS left no __RepoPushBuffer", not buffers12, str(buffers12))

print()
print("=" * 72)
print("TEST 14 — pre-push backups written")
print("=" * 72)
backup_root = repo10 / ".studio-push-backups"
backups = list(backup_root.rglob("*.lua")) if backup_root.exists() else []
check("pre-push source backed up for every written file",
      len(backups) >= len(items10) - 1, f"{len(backups)} backups")
if backups:
    sample = next((b for b in backups if b.name.startswith("GameManager")), backups[0])
    check("backup holds the PRE-push Studio source, not the new one",
          "-- drift" in sample.read_text() or sample.read_text() == git_show(
              "ServerScriptService/GameManager.Script.lua"))

print()
print("=" * 72)
print("TEST 15 — --file that matches nothing is reported clearly")
print("=" * 72)
repo15 = fresh_repo()
tool15 = load_tool(repo15)
studio15 = fakestudio.FakeStudio()
fakestudio.install(tool15, studio15)
sys.argv = ["push_repo_to_studio.py", "--file", "ServerScriptService/NoSuchFile.lua"]
code15 = tool15.main()
check("unmatched --file exits 2 (not a misleading 'nothing pending')", code15 == 2, f"exit={code15}")
check("unmatched --file contacted Studio zero times", studio15.calls == 0)

print()
print("=" * 72)
print("TEST 16 — backslash paths (Windows tab-completion) still match")
print("=" * 72)
repo16 = fresh_repo()
tool16 = load_tool(repo16)
studio16 = fakestudio.FakeStudio()
items16 = pending_items(repo16)
seed(studio16, items16, repo16)
fakestudio.install(tool16, studio16)
sys.argv = ["push_repo_to_studio.py", "--file",
            "ServerScriptService\\Level 2 Systems\\Level 2 World Builder.ModuleScript.lua"]
code16 = tool16.main()
check("backslash --file path is normalized and matches", code16 == 0, f"exit={code16}")

print()
print("=" * 72)
print("TEST 17 — stale buffer from a previous crash is cleaned at startup")
print("=" * 72)
repo17 = fresh_repo()
tool17 = load_tool(repo17)
studio17 = fakestudio.FakeStudio()
items17 = pending_items(repo17)
seed(studio17, items17, repo17)
studio17.objects[("ServerStorage", "__RepoPushBuffer")] = ("StringValue", "left over junk", "V")
fakestudio.install(tool17, studio17)
sys.argv = ["push_repo_to_studio.py", "--audit"]
code17 = tool17.main()
check("--audit against live Studio classifies without writing", code17 == 0, f"exit={code17}")
check("stale buffer removed at startup",
      ("ServerStorage", "__RepoPushBuffer") not in studio17.objects)
unchanged17 = all(studio17.source_of(i["studioPath"]) == (git_show(i["file"]) or git_show("ServerScriptService/EntityAnimation.Script.Lua"))
                  for i in items17)
check("--audit wrote no script sources", unchanged17)

print()
print("=" * 72)
print(f"RESULT: {len(passes)} passed, {len(failures)} failed")
if failures:
    for failure in failures:
        print("  FAILED: " + failure)
print("=" * 72)
sys.exit(1 if failures else 0)
