"""Level 3: a CD still lying on a hide table owns the table's E prompt (FIRST_CD_PROMPT_20260922).

Runs the REAL `cdOnTable` / `refreshPrompt` pair and the refusal line of
`tryEnter`, sliced out of `Level 3 Hiding Controller` by string markers, against
stub anchors/prompts. Covers: WORLD CD -> HIDE prompt off and tryEnter refuses
CD_ON_TABLE; CARRIED / DROPPED / INSERTED -> prompt back; a table without a CD
is untouched; the occupancy cap still wins.

What still needs Studio: the real first-CD table with seed 1154781618 (the
prompt the engine shows, on desktop and simulated touch). Set LUAU_BIN.
"""

from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HIDING = (ROOT / "ServerScriptService/Level 3 Systems/Level 3 Hiding Controller.ModuleScript.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


PROMPT_RULE = section(HIDING, "local function cdOnTable(", "\nlocal function refreshPrompts(")
REFUSAL = section(HIDING, '\tif #occupants >= Tuning.HideOccupantCap then return false, "OCCUPIED" end',
                  "\n\tlocal now = os.clock()")

SCRIPT = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end

local Tuning = {HideOccupantCap = 2}
local roundAllows = true
local function roundAllowsHiding(_session) return roundAllows end
local function promptFor(anchor) return anchor.prompt end
local function occupantsOf(session, anchor) return session.Occupants[anchor] or {} end

local function anchorStub()
    local attrs = {}
    return {
        prompt = {Enabled = false},
        SetAttribute = function(_, key, value) attrs[key] = value end,
        attrs = attrs,
    }
end
local function modelStub(state)
    local attrs = {Level3_CDState = state}
    return {Parent = {}, GetAttribute = function(_, key) return attrs[key] end, attrs = attrs}
end
''' + PROMPT_RULE + r'''

-- tryEnter's refusal line, with the same locals it reads in the real function
local function enterRefusal(session, anchor)
    local occupants = session.Occupants[anchor]
''' + REFUSAL + r'''
    return true
end

local cdTable, plainTable = anchorStub(), anchorStub()
local cd = modelStub("WORLD")
local session = {Occupants = {[cdTable] = {}, [plainTable] = {}}, CDOnAnchor = {[cdTable] = cd}}

refreshPrompt(session, cdTable); refreshPrompt(session, plainTable)
expect(cdTable.prompt.Enabled, false, 'HIDE is off while the CD lies on the table')
expect(plainTable.prompt.Enabled, true, 'a table without a CD keeps its prompt')
local ok, reason = enterRefusal(session, cdTable)
expect(ok, false, 'the server refuses a hide under the CD table')
expect(reason, "CD_ON_TABLE", 'refusal reason')
expect(enterRefusal(session, plainTable), true, 'the plain table admits')

for _, state in ipairs({"CARRIED", "DROPPED", "INSERTED"}) do
    cd.attrs.Level3_CDState = state
    refreshPrompt(session, cdTable)
    expect(cdTable.prompt.Enabled, true, 'HIDE returns once the CD is ' .. state)
    expect(enterRefusal(session, cdTable), true, 'the server admits once the CD is ' .. state)
end

-- Back in the world (a reset), and the cap still wins over everything
cd.attrs.Level3_CDState = "WORLD"
refreshPrompt(session, cdTable)
expect(cdTable.prompt.Enabled, false, 'HIDE off again after a reset to WORLD')
cd.attrs.Level3_CDState = "CARRIED"
session.Occupants[cdTable] = {{UserId = 1}, {UserId = 2}}
refreshPrompt(session, cdTable)
expect(cdTable.prompt.Enabled, false, 'a full table stays closed regardless of the CD')
expect(cdTable.attrs.Level3_HideOccupiedUserId, 1, 'first occupant still published')
local ok2, reason2 = enterRefusal(session, cdTable)
expect(reason2, "OCCUPIED", 'the cap is checked before the CD rule')

-- A model that left the world (destroyed module) no longer blocks
session.Occupants[cdTable] = {}
cd.attrs.Level3_CDState = "WORLD"; cd.Parent = nil
refreshPrompt(session, cdTable)
expect(cdTable.prompt.Enabled, true, 'a destroyed module does not block the table')

-- No link table at all (older session shape) means no blocking
local bare = {Occupants = {[plainTable] = {}}}
refreshPrompt(bare, plainTable)
expect(plainTable.prompt.Enabled, true, 'no CDOnAnchor map -> no blocking')

-- Round not allowing hiding still wins
roundAllows = false
refreshPrompt(bare, plainTable)
expect(plainTable.prompt.Enabled, false, 'round gate still closes the prompt')

print('Level 3 first-CD prompt: ' .. checks .. ' checks passed (offline; the shown prompt on seed 1154781618 needs Studio)')
'''


def main():
    luau = os.environ.get("LUAU_BIN")
    if not luau:
        raise SystemExit("set LUAU_BIN to a Luau interpreter")
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "first_cd_prompt.luau"
        path.write_text(SCRIPT, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True)
        print(result.stdout.strip())
        if result.returncode != 0:
            raise SystemExit(result.stderr.strip() or result.stdout.strip() or "luau failed")


if __name__ == "__main__":
    main()
