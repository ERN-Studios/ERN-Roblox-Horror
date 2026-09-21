"""Execute the First Entry Guide's RETRY mode in offline Luau.

RETRY_GUIDE_20260921. Same script, same beams, a different bay: after a round
the player did not escape, GameManager publishes RetryGuideLevel and the guide
walks them to that level's pads instead of Level 1's.

The engine boundary is test_first_entry_guide.py's harness, imported rather than
copied -- its lobby already builds a Level 1 bay with four pads AND a Level 2 bay
with one, which is exactly what "point at the level they just failed" needs. That
file's own suite still owns first-entry behaviour; this one only adds the second
mode and the rule that the two never run at once.

What this CANNOT see: real pathfinding, whether the lobby actually holds a bay
for the level the server named, and anything about how the beam looks. Set
LUAU_BIN to an official Luau interpreter.
"""

from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))

from test_first_entry_guide import HARNESS, SOURCE, UISTYLE  # noqa: E402

TESTS = r'''
end
local function fresh(setup)
    local ctx=context()
    -- A player who has played before: the first-entry guide never applies.
    ctx.Player:SetAttribute("ZyntraFirstLogin",false)
    if setup then setup(ctx) end
    boot(ctx)
    return ctx
end
local function titleOf(ctx)
    local billboards=ctx:Kids("BillboardGui")
    if #billboards==0 then return nil end
    for _,child in billboards[1]:GetChildren() do
        if child.Name=="Title" then return child.Text end
    end
    return nil
end

do  -- (1) the attribute is already set when the script starts
    local ctx=fresh(function(c) c.Player:SetAttribute("RetryGuideLevel",2) end)
    ctx:Step(.1)
    check(ctx:Guide()~=nil,"a retry level published before the script runs still opens it")
    check(titleOf(ctx)=="TRY AGAIN \u{00B7} LEVEL 2","the billboard names the level to retry")
    -- LaunchZone5 at (63,30,-853.2) is the only pad in the Level 2 bay.
    check(ctx.LastTarget.X==63,"it walks to the Level 2 bay, not Level 1's")
    check(ctx:EnabledBeams()>0,"the same beam chain is drawn")
end

do  -- (2) the attribute arrives after the lobby has loaded
    local ctx=fresh()
    ctx:Step(.1)
    check(ctx:Guide()==nil,"a returning player with nothing to retry gets nothing")
    ctx.Player:SetAttribute("RetryGuideLevel",1)
    ctx:Step(.1)
    check(ctx:Guide()~=nil,"publishing it later opens the guide")
    check(titleOf(ctx)=="TRY AGAIN \u{00B7} LEVEL 1","level 1 retries read the same way")
    check(ctx.LastTarget.X==-54,"and target the nearest Level 1 pad")
end

do  -- (3) a level the guide cannot make sense of
    for _,value in {0,-2,1.5,"2",true} do
        local ctx=fresh(function(c) c.Player:SetAttribute("RetryGuideLevel",value) end)
        ctx:Step(.1)
        check(ctx:Guide()==nil,"a retry level of "..tostring(value).." opens nothing")
    end
end

do  -- (4) the three refusals the first-entry guide already makes
    local ctx=fresh(function(c)
        c.Workspace:SetAttribute("ReservedRoundServer",true)
        c.Player:SetAttribute("RetryGuideLevel",2)
    end)
    ctx:Step(.1)
    check(ctx:Guide()==nil,"no retry guide on a reserved round server")

    ctx=fresh(function(c)
        c.Player:SetAttribute("InRound",true)
        c.Player:SetAttribute("RetryGuideLevel",2)
    end)
    ctx:Step(.1)
    check(ctx:Guide()==nil,"no retry guide for a player already in a round")
end

do  -- (5) never over the first-entry guide
    local ctx=context()
    boot(ctx)          -- ZyntraFirstLogin is true here: first entry opens
    ctx:Step(.1)
    check(titleOf(ctx)=="LEVEL 1 START HERE","the first-entry guide is up")
    ctx.Player:SetAttribute("RetryGuideLevel",3)
    ctx:Step(.1)
    check(titleOf(ctx)=="LEVEL 1 START HERE","a retry never replaces a live guide")
    check(#ctx:Kids("BillboardGui")==1,"and never builds a second one")
end

do  -- (6) the budget, accumulated from the frame delta
    local ctx=fresh(function(c) c.Player:SetAttribute("RetryGuideLevel",2) end)
    ctx:Step(.1)
    check(ctx:Guide()~=nil,"open")
    for _=1,44 do ctx:Step(1) end
    check(ctx:Guide()~=nil,"still there at 44 seconds")
    ctx:Step(1)
    check(ctx:Guide()==nil,"gone at 45")
    -- And it stays gone: the attribute did not change, so nothing re-opens it.
    ctx:Step(5)
    check(ctx:Guide()==nil,"an expired retry does not come back on its own")
end

do  -- (7) the first-entry guide still has NO budget
    local ctx=context()
    boot(ctx)
    ctx:Step(.1)
    for _=1,60 do ctx:Step(1) end
    check(ctx:Guide()~=nil,"a brand-new player is never abandoned mid-lobby")
end

do  -- (8) every ordinary ending still ends it
    for _,event in {"queuehost","queueconfigured","lobbycountdown","loadinggame"} do
        local ctx=fresh(function(c) c.Player:SetAttribute("RetryGuideLevel",2) end)
        ctx:Step(.1)
        ctx.Remote.OnClientEvent:Fire(event)
        check(ctx:Guide()==nil,event.." ends the retry guide too")
    end
    local ctx=fresh(function(c) c.Player:SetAttribute("RetryGuideLevel",2) end)
    ctx:Step(.1)
    ctx.Player:SetAttribute("InRound",true)
    check(ctx:Guide()==nil,"entering a round ends it")

    ctx=fresh(function(c) c.Player:SetAttribute("RetryGuideLevel",2) end)
    ctx:Step(.1)
    ctx.Root.Position=Vector3.new(63-7,30.4,-853.2)   -- inside r=7.41
    ctx:Step(.1)
    check(ctx:Guide()==nil,"standing on the pad ends it")
end

do  -- (9) a second failed round opens a second guide
    local ctx=fresh(function(c) c.Player:SetAttribute("RetryGuideLevel",2) end)
    ctx:Step(.1)
    ctx.Remote.OnClientEvent:Fire("loadinggame")
    check(ctx:Guide()==nil,"closed by the launch")
    ctx.Player:SetAttribute("RetryGuideLevel",3)
    ctx:Step(.1)
    check(titleOf(ctx)=="TRY AGAIN \u{00B7} LEVEL 3","the guide re-opens for the next failure")
end

do  -- (10) script teardown is final for both modes
    local ctx=fresh(function(c) c.Player:SetAttribute("RetryGuideLevel",2) end)
    ctx:Step(.1)
    ctx.Script.Destroying:Fire()
    check(ctx:Guide()==nil,"teardown destroys it")
    ctx.Player:SetAttribute("RetryGuideLevel",1)
    ctx:Step(.1)
    check(ctx:Guide()==nil,"and nothing re-opens after teardown")
end

print("Retry guide: "..checks.." checks passed (entire actual script, offline Luau)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")
    with tempfile.TemporaryDirectory(prefix="retry-guide-") as directory:
        path = Path(directory) / "retry_guide_test.luau"
        harness = HARNESS.replace("--[[UISTYLE_SOURCE]]",
                                  UISTYLE.read_text(encoding="utf-8"))
        path.write_text(harness + SOURCE.read_text(encoding="utf-8") + TESTS,
                        encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=30)


if __name__ == "__main__":
    main()
