"""A fake Roblox Studio that really executes the push tool's generated Luau.

Every execute_luau call from push_repo_to_studio.py is run through the REAL luau
interpreter against a stubbed DataModel (game / GetService / FindFirstChild /
Instance.new / .Source / .Value / .Parent / Destroy / ScriptEditorService:
UpdateSourceAsync). DataModel state persists between calls via hex-encoded
records, so chunked transfers, escaping and verification are exercised for real.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import sys
from pathlib import Path

SCRATCH = Path(__file__).resolve().parent
# The real luau interpreter runs the tool's generated code. Point LUAU_BIN at it,
# or drop the binary next to this file:
#   curl -sSL -o luau.zip https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip
#   unzip luau.zip luau
LUAU = Path(os.environ.get("LUAU_BIN") or (SCRATCH / "luau"))

PRELUDE = r"""
-- ── fake Roblox DataModel ────────────────────────────────────────────────
local function fromhex(s)
    return (s:gsub("%x%x", function(cc) return string.char(tonumber(cc, 16)) end))
end
local function tohex(s)
    return (s:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end

local ALL = {}

local function makeInstance(className, name)
    local data = {ClassName = className, Name = name, Source = "", Value = "", Parent = nil}
    local children = {}
    local self
    local methods
    methods = {
        FindFirstChild = function(_, n)
            for _, c in ipairs(children) do if c.Name == n then return c end end
            return nil
        end,
        IsA = function(_, c) return data.ClassName == c end,
        GetService = function(_, n)
            for _, c in ipairs(children) do if c.Name == n then return c end end
            local svc = makeInstance(n, n)
            svc.Parent = self
            return svc
        end,
        GetChildren = function() return children end,
        Destroy = function()
            local p = data.Parent
            if p then p:_removeChild(self) end
            data.Parent = nil
        end,
        _addChild = function(_, c) table.insert(children, c) end,
        _removeChild = function(_, c)
            for i, x in ipairs(children) do
                if x == c then table.remove(children, i) return end
            end
        end,
        _children = function() return children end,
    }
    self = setmetatable({}, {
        __index = function(_, k)
            if methods[k] ~= nil then return methods[k] end
            return data[k]
        end,
        __newindex = function(_, k, v)
            if k == "Parent" then
                if data.Parent then data.Parent:_removeChild(self) end
                data.Parent = v
                if v then v:_addChild(self) end
            else
                data[k] = v
            end
        end,
    })
    table.insert(ALL, self)
    return self
end

game = makeInstance("DataModel", "game")

Instance = {}
function Instance.new(className, parent)
    local inst = makeInstance(className, className)
    if parent then inst.Parent = parent end
    return inst
end

-- ScriptEditorService replacement: the real one takes (script, callback) where
-- the callback receives the old source and returns the new one.
local ses = makeInstance("ScriptEditorService", "ScriptEditorService")
ses.Parent = game
rawset(getmetatable(ses), "__index", (function(previous)
    return function(t, k)
        if k == "UpdateSourceAsync" then
            return function(_, target, callback)
                local newSource = callback(target.Source)
                target.Source = newSource
            end
        end
        return previous(t, k)
    end
end)(getmetatable(ses).__index))

-- ── state restore ───────────────────────────────────────────────────────
local function ensurePath(segments, className)
    local cur = game
    for index, name in ipairs(segments) do
        local nxt = cur:FindFirstChild(name)
        if not nxt then
            nxt = makeInstance(index == #segments and className or "Folder", name)
            nxt.Parent = cur
        end
        cur = nxt
    end
    return cur
end

__STATE_IN__

-- ── the tool's generated code, verbatim ─────────────────────────────────
local function __run()
__CODE__
end
local ok, result = pcall(__run)

-- ── state dump ──────────────────────────────────────────────────────────
local out = {}
local function walk(inst, prefix)
    for _, child in ipairs(inst:_children()) do
        local path = prefix == "" and child.Name or (prefix .. "|" .. child.Name)
        if child.ClassName == "Script" or child.ClassName == "LocalScript"
            or child.ClassName == "ModuleScript" then
            table.insert(out, "S\t" .. path .. "\t" .. child.ClassName .. "\t" .. tohex(child.Source))
        elseif child.ClassName == "StringValue" then
            table.insert(out, "V\t" .. path .. "\t" .. child.ClassName .. "\t" .. tohex(child.Value))
        end
        walk(child, path)
    end
end
walk(game, "")
print("@@STATE@@")
print(table.concat(out, "\n"))
print("@@RESULT@@")
if ok then
    print(tohex(tostring(result == nil and "" or result)))
else
    print("@@ERROR@@" .. tostring(result))
end
"""


class FakeStudio:
    """Persistent fake DataModel; runs each Luau chunk for real."""

    def __init__(self) -> None:
        # path tuple -> (className, source/value, kind)
        self.objects: dict[tuple[str, ...], tuple[str, str, str]] = {}
        self.calls = 0
        self.luau_errors: list[str] = []

    def add_script(self, studio_path: str, class_name: str, source: str) -> None:
        self.objects[tuple(studio_path.split("."))] = (class_name, source, "S")

    def source_of(self, studio_path: str) -> str | None:
        entry = self.objects.get(tuple(studio_path.split(".")))
        return entry[1] if entry else None

    def _state_in(self) -> str:
        lines = []
        for segments, (class_name, payload, kind) in self.objects.items():
            seg_literal = ", ".join('"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')
                                    for s in segments)
            field = "Source" if kind == "S" else "Value"
            lines.append(
                'do local inst = ensurePath({%s}, "%s") inst.%s = fromhex("%s") end'
                % (seg_literal, class_name, field, payload.encode("utf-8").hex())
            )
        return "\n".join(lines)

    def execute(self, code: str) -> str:
        self.calls += 1
        program = PRELUDE.replace("__STATE_IN__", self._state_in()).replace("__CODE__", code)
        # A UNIQUE file under the system temp dir, deleted in a finally.
        #
        # This used to write `tools/tests/_fakestudio_run.luau` -- one fixed path
        # inside the repo, rewritten on every call and never removed. It left a
        # 585 KB scratch program sitting in the working tree (only .gitignore kept
        # it out of commits), and two suites running at once would overwrite each
        # other's program mid-run. A tempfile removes both problems and leaves the
        # checkout clean whether the run passes, fails, or raises.
        handle, temp_path = tempfile.mkstemp(prefix="fakestudio_", suffix=".luau", text=True)
        os.close(handle)
        script = Path(temp_path)
        try:
            script.write_text(program, encoding="utf-8")
            proc = subprocess.run([str(LUAU), str(script)], capture_output=True, text=True)
        finally:
            try:
                script.unlink()
            except OSError:
                pass
        if proc.returncode != 0:
            raise RuntimeError(f"luau failed:\n{proc.stdout}\n{proc.stderr}")
        stdout = proc.stdout
        state_block = stdout.split("@@STATE@@\n", 1)[1].split("\n@@RESULT@@\n", 1)
        state_text, result_text = state_block[0], state_block[1].strip()

        # rebuild state
        self.objects = {}
        for line in state_text.split("\n"):
            if not line.strip():
                continue
            kind, path, class_name, payload = line.split("\t")
            self.objects[tuple(path.split("|"))] = (
                class_name, bytes.fromhex(payload).decode("utf-8"), kind)

        if result_text.startswith("@@ERROR@@"):
            self.luau_errors.append(result_text)
            raise RuntimeError(result_text)
        return bytes.fromhex(result_text).decode("utf-8")


def install(module, studio: FakeStudio) -> None:
    """Point push_repo_to_studio's transport at the fake Studio."""

    class FakeClient:
        def __init__(self, *_args, **_kwargs) -> None:
            pass

        def initialize(self) -> None:
            pass

        def close(self) -> None:
            pass

        def call(self, method, params):
            assert method == "execute_luau", f"unexpected MCP method: {method}"
            assert params["datamodel_type"] == "Edit", params
            assert params["studio_id"] == "fake-studio-id", params
            return studio.execute(params["code"])

    module.StudioMcpClient = FakeClient
    module.find_mcp_batch = lambda: Path("/fake/mcp.bat")
    # The real select_studio returns the whole studio RECORD (a dict), not an id.
    module.select_studio = lambda *_a, **_k: {
        "id": "fake-studio-id", "name": "Backrooms: No Way Out", "active": True}
