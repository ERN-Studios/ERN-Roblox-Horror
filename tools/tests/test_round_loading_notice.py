"""Run RoundUI's actual loading-error helpers/event branches with a fake clock.

The server replays loadfailed after cleanup, and the attribute can arrive on
either side of the remote. Test those real delivery orders, message ownership,
retry generations and absolute expiry; also compile the complete 200-local HUD.

The loading cover itself (owner, 2026-10-08): palettes [1]-[6] in the level
colours, a pure-black opaque cover with no picture, and the LEVEL 2 / LEVEL 5
mystery titles in fixed and random mode, all run from RoundUI's own source.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


HOST = r'''
local checks=0
local function check(value,message) checks+=1;assert(value,message) end
local function equal(actual,expected,message)
    check(actual==expected,message..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function signal()
    local listeners={}
    return {Connect=function(_,fn) table.insert(listeners,fn) end,
        Fire=function() for _,fn in ipairs(listeners) do fn() end end}
end
local function fresh(initialAttribute)
    local ctx={Now=100,Timers={},TimerCount=0,CancelCount=0,PaletteLevels={},SequenceCount=0}
    local task={delay=function(seconds,fn)
        ctx.TimerCount+=1;table.insert(ctx.Timers,{At=ctx.Now+seconds,Fn=fn})
    end}
    local os={clock=function() return ctx.Now end}
    function ctx:Advance(seconds)
        local target=self.Now+seconds
        while true do
            table.sort(self.Timers,function(a,b) return a.At<b.At end)
            if not self.Timers[1] or self.Timers[1].At>target+1e-9 then break end
            local timer=table.remove(self.Timers,1);self.Now=math.max(self.Now,timer.At);timer.Fn()
        end
        self.Now=target
    end
    local Color3={fromRGB=function(r,g,b) return string.format("%d,%d,%d",r,g,b) end}
    local UDim2={new=function(...) return {...} end}
    local Enum={Font={GothamMedium="GothamMedium"}}
    local player={Attribute=initialAttribute,Changed=signal()}
    function player:GetAttribute(name)
        if name=="LoadingLevel" then return self.LoadingLevel end
        assert(name=="RoundLoadingError");return self.Attribute
    end
    function player:GetAttributeChangedSignal(name) assert(name=="RoundLoadingError");return self.Changed end
    function player:SetAttribute(name,value) assert(name=="LoadingLevel");self.LoadingLevel=value end
    function ctx:SetAttribute(value)
        if player.Attribute~=value then player.Attribute=value;player.Changed.Fire() end
    end
    function ctx:ReplayAttribute() player.Changed.Fire() end
    local workspace={Attributes={SelectedLevel=1}}
    function workspace:GetAttribute(name) return self.Attributes[name] end
    ctx.Workspace,ctx.Player=workspace,player
    local gui={};__PERSISTENT_GUI__
    local label={Text="",Visible=false}
    local loadingFrame={Visible=true};ctx.LoadingFrame=loadingFrame
    local loadingTitle,loadingStatus={},{}
    local loadingClock,loadingBaseText,loadingRun=0,"",0
    local serverReadyForEntry,loadingSequenceFinished=false,false
    local queueShade={};local queueStation,queueSubmitting=nil,false
    local dead,shakeScheduled=false,false
    local lobbyBriefing={active=false,pending=false}
    local levelThreeBriefing={started=false,play=function() end}
    local elevatorBriefingStarted=false
    local function cancelAllCommandBriefings() ctx.CancelCount+=1 end
    local function hideRoundEnding() end
    local function stopSpectating() end
    local completion={}
    local dispatchAudio={loadingCards={root={Visible=true,Level=1}}}
    ctx.Cards=dispatchAudio.loadingCards
    local function applyLoadingPalette(level)
        table.insert(ctx.PaletteLevels,level)
        -- The real renderer preserves Root.Visible across SetLevel/remount (also tested in B8).
        local visible=dispatchAudio.loadingCards.root.Visible
        dispatchAudio.loadingCards.root={Visible=visible,Level=level}
    end
    local function startLoadingSequence() ctx.SequenceCount+=1 end
    local function finishLoadingWhenReady() loadingFrame.Visible=false end
    __ENTRY_STATE__
    __MESSAGES__
    function ctx:Dispatch(ev,a,b,c,d,e,f)
        __LOBBY__
        __QUEUE__
        __ENTRY_EVENTS__
        __START__
        end
    end
    __RESTORE__
    ctx.State=entryState;ctx.Label=label;ctx.Gui=gui;ctx.SetMsg=setMsg
    function ctx:DirectBrief() __DIRECT_BRIEF__ end
    return ctx
end

local failed="ROUND LOADING FAILED — PLEASE TRY AGAIN"
local timeout="LOADING TIMED OUT AFTER 60 SECONDS — PLEASE TRY AGAIN"
for _,reason in ipairs({{Remote="BUILD_ERROR",Attribute="failed",Text=failed,Key="failed"},
    {Remote="LOADING_TIMEOUT",Attribute="timeout",Text=timeout,Key="timeout"}}) do
    for _,first in ipairs({"attribute","remote"}) do
        local ctx=fresh()
        if first=="attribute" then ctx:SetAttribute(reason.Attribute) else ctx:Dispatch("loadfailed",reason.Remote) end
        equal(ctx.Label.Text,reason.Text,"first delivery shows canonical explanation")
        equal(ctx.Label.Visible,true,"failure is visible")
        equal(ctx.Label.TextColor3,"255,100,100","failure remains red")
        equal(ctx.State.ErrorExpiresAt,108,"first delivery establishes eight-second deadline")
        ctx:Advance(1)
        if first=="attribute" then ctx:Dispatch("loadfailed",reason.Remote) else ctx:SetAttribute(reason.Attribute) end
        ctx:ReplayAttribute()
        equal(ctx.TimerCount,1,"attribute/remote duplicate owns only one timer")
        equal(ctx.State.ErrorExpiresAt,108,"duplicate does not extend deadline")
        ctx:Advance(6.9);ctx:Dispatch("lobby")
        equal(ctx.Label.Text,reason.Text,"lobby redisplays unexpired explanation")
        equal(ctx.State.ErrorExpiresAt,108,"lobby keeps original deadline")
        ctx:Advance(.11)
        equal(ctx.Label.Text,"","notice expires after original eight seconds")
        equal(ctx.Label.Visible,false,"expired notice is hidden")
        equal(ctx.State.Error,nil,"expired error cannot be restored by lobby")
        equal(ctx.State.ErrorReason,reason.Key,"expired incident stays consumed")
        ctx:Advance(20)
        ctx:Dispatch("lobby");ctx:Dispatch("loadfailed",reason.Remote)
        ctx:ReplayAttribute()
        equal(ctx.Label.Text,"","cleanup remote replay and history do not revive notice")
        equal(ctx.TimerCount,1,"late replay schedules no new timer")
        equal(ctx.Gui.ResetOnSpawn,false,"the HUD survives character respawn")
    end
end
do
    local ctx=fresh("timeout")
    equal(ctx.Label.Text,timeout,"join-time attribute is restored without a remote")
    ctx:Advance(8);ctx:ReplayAttribute();ctx:Dispatch("lobby")
    equal(ctx.Label.Visible,false,"persistent join-time attribute cannot revive dismissed notice")
    equal(fresh("").TimerCount,0,"empty attribute is not a failure")
end
do
    local ctx=fresh();ctx:Dispatch("loadfailed","BUILD_ERROR")
    ctx:Advance(2);ctx:SetAttribute(nil);ctx:SetAttribute("failed")
    ctx:SetAttribute(nil);ctx:SetAttribute("timeout")
    ctx:Dispatch("loadfailed","LOADING_TIMEOUT")
    equal(ctx.Label.Text,failed,"same-attempt category changes do not restart the incident")
    equal(ctx.State.ErrorExpiresAt,108,"late attribute clear does not rearm")
    equal(ctx.TimerCount,1,"late nil and category replay do not add timers")
    ctx:Advance(6);equal(ctx.Label.Text,"","original deadline still expires")
end
do
    local ctx=fresh();ctx:Dispatch("loadfailed","BUILD_ERROR");ctx:Advance(2)
    ctx:Dispatch("queueconfigured",4,"public",2)
    local text=ctx.Label.Text
    check(string.find(text,"PARTY OPEN",1,true)~=nil,"actual queue branch displayed new status")
    ctx:Advance(6)
    equal(ctx.Label.Text,text,"old failure timer preserves newer queue status")
    equal(ctx.State.Error,nil,"failure still retires while queue owns label")
end
do
    local ctx=fresh();ctx:Dispatch("loadfailed","BUILD_ERROR")
    local serial=ctx.State.MessageSerial
    ctx:DirectBrief()
    equal(ctx.State.MessageSerial,serial,"actual direct briefing writer bypasses setMsg")
    ctx:Advance(8)
    equal(ctx.Label.Text,"ANOTHER STATUS","expected-text guard preserves direct writer")
end
do
    local ctx=fresh();ctx:Dispatch("loadfailed","BUILD_ERROR")
    ctx.SetMsg(failed);ctx:Advance(8)
    equal(ctx.Label.Text,failed,"new owner survives even with text identical to old error")
    equal(ctx.State.Error,nil,"ownership does not keep old incident alive")
end
do
    local ctx=fresh("failed");ctx:Advance(4)
    ctx:Dispatch("loadinggame",2)
    equal(ctx.State.Error,nil,"new attempt clears existing notice")
    equal(ctx.State.ErrorArmed,true,"new attempt arms a fresh error")
    equal(ctx.State.Active,true,"entry stays active")
    ctx:ReplayAttribute()
    equal(ctx.Label.Text,"","old unchanged attribute stays consumed on retry")
    ctx:Advance(1);ctx:Dispatch("loadfailed","BUILD_ERROR")
    equal(ctx.State.ErrorExpiresAt,113,"identical error in new attempt receives full lifetime")
    ctx:Advance(3)
    equal(ctx.Label.Text,failed,"previous attempt timer cannot clear the new error")
    ctx:Advance(4.9);equal(ctx.Label.Text,failed,"new error remains visible just before its deadline")
    ctx:Advance(.1);equal(ctx.Label.Text,"","new error expires at its own deadline")
    equal(ctx.TimerCount,2,"one timer per attempt")
end
do
    local ctx=fresh();ctx:Dispatch("loadfailed","BUILD_ERROR");ctx:Advance(1)
    ctx:Dispatch("start")
    equal(ctx.State.ErrorArmed,false,"successful round disarms late failure delivery")
    equal(ctx.State.Error,nil,"successful round clears error")
    ctx.SetMsg("NEW ROUND STATUS");ctx.LoadingFrame.Visible=true
    local cancellations=ctx.CancelCount
    ctx:Dispatch("loadfailed","BUILD_ERROR");ctx:SetAttribute("failed")
    equal(ctx.Label.Text,"NEW ROUND STATUS","late remote/attribute cannot overwrite started round")
    equal(ctx.LoadingFrame.Visible,true,"late failure cannot hide newer loading state")
    equal(ctx.CancelCount,cancellations,"late failure cannot cancel a new briefing")
    ctx:Advance(10);equal(ctx.Label.Text,"NEW ROUND STATUS","invalidated timer remains inert")
    ctx:Dispatch("loadinggame",3);ctx:Dispatch("loadfailed","LOADING_TIMEOUT")
    equal(ctx.Label.Text,timeout,"later genuine attempt rearms after successful start")
end
do
    local ctx=fresh();ctx:Dispatch("loadfailed","BUILD_ERROR")
    ctx.Now=109 -- Delayed task execution must not make a late lobby revive a notice.
    ctx:Dispatch("lobby")
    equal(ctx.Label.Text,"","absolute deadline is checked on lobby redisplay")
    ctx.SetMsg("NEW STATUS");ctx:Advance(0)
    equal(ctx.Label.Text,"NEW STATUS","delayed callback preserves later status")
end
do
    local ctx=fresh();ctx:Dispatch("loadinggame",2)
    ctx:Dispatch("entryprepare",{Token="attempt"});ctx:SetAttribute("failed")
    equal(ctx.Label.Text,"","attribute does not interrupt active party barrier")
    ctx:Dispatch("entrycancel",{Token="attempt"});ctx:Dispatch("loadfailed","BUILD_ERROR")
    equal(ctx.Label.Text,failed,"remote displays error after active attribute was observed")
    equal(ctx.State.Token,nil,"failure retires entry token")
    equal(ctx.TimerCount,1,"active attribute plus cancellation yields one notice")
end
-- First-card delivery races use the real loadinggame event branch above. Presentation collaborators
-- only record the confirmed level and retained Root.Visible; the full B8 fixture owns card rendering.
do
    local ctx=fresh();ctx.LoadingFrame.Visible=false
    ctx.Workspace.Attributes.SelectedLevel=1
    ctx.Player.LoadingLevel=2
    ctx:Dispatch("loadinggame")
    equal(#ctx.PaletteLevels,0,"untyped bootstrap does not guess Level1 or stale LoadingLevel")
    equal(ctx.LoadingFrame.Visible,true,"unknown arrival retains its opaque cover")
    equal(ctx.Cards.root.Visible,false,"unknown arrival keeps imported old card hidden")
    equal(ctx.State.Active,true,"unknown arrival still arms party barrier")
    equal(ctx.State.KnownLevel,nil,"unknown arrival has no confirmed level")
    equal(ctx.Player.LoadingLevel,nil,"unknown arrival retires previous loading metadata")
    equal(ctx.SequenceCount,1,"unknown arrival retains presentation sequence")
    ctx:Dispatch("entryprepare",{Token="unknown-entry"})
    equal(ctx.State.Token,"unknown-entry","unknown arrival still accepts entry token")
    ctx:Dispatch("loadinggame",3)
    equal(ctx.PaletteLevels[1],3,"first painted entry is confirmed Level3")
    equal(ctx.Cards.root.Level,3,"confirmed card belongs to Level3")
    equal(ctx.Cards.root.Visible,true,"confirmation unhides replacement root")
    equal(ctx.State.KnownLevel,3,"confirmed level is stored on active entry")
    equal(ctx.Player.LoadingLevel,3,"confirmation publishes exact level")
end
do
    local ctx=fresh();ctx:Dispatch("loadinggame",3)
    ctx:Dispatch("entryprepare",{Token="confirmed-entry"})
    local errorSerial,sequence=ctx.State.ErrorSerial,ctx.SequenceCount
    ctx:Dispatch("loadinggame")
    equal(ctx.State.Token,"confirmed-entry","late untyped bootstrap preserves prepared token")
    equal(ctx.State.ErrorSerial,errorSerial,"late untyped bootstrap preserves error generation")
    equal(ctx.SequenceCount,sequence,"late untyped bootstrap does not restart sequence")
    equal(#ctx.PaletteLevels,1,"late untyped bootstrap does not repaint")
    equal(ctx.Cards.root.Visible,true,"late untyped bootstrap keeps confirmed card")
    equal(ctx.State.KnownLevel,3,"late untyped bootstrap keeps exact level")
end
do
    local ctx=fresh();ctx:Dispatch("loadinggame",2);ctx:Dispatch("start")
    ctx.Workspace.Attributes.SelectedLevel=2
    ctx:Dispatch("loadinggame")
    equal(ctx.State.KnownLevel,nil,"new unknown entry cannot reuse completed Level2")
    equal(ctx.Cards.root.Visible,false,"new unknown entry hides completed Level2 card")
    equal(ctx.Player.LoadingLevel,nil,"completed Level2 metadata is retired")
    ctx:Dispatch("loadinggame",3)
    equal(ctx.PaletteLevels[2],3,"next confirmed entry paints Level3")
    equal(ctx.Cards.root.Level,3,"replacement is Level3 after previous Level2")
    equal(ctx.Cards.root.Visible,true,"Level3 replacement is visible after hidden old root")
end
for _,malformed in ipairs({false,{},0,7,-1,2.5,"bad",math.huge,0/0}) do
    local ctx=fresh();ctx:Dispatch("loadinggame",malformed)
    equal(#ctx.PaletteLevels,0,"malformed announcement cannot paint a guessed level")
    equal(ctx.Cards.root.Visible,false,"malformed announcement keeps old card hidden")
    equal(ctx.LoadingFrame.Visible,true,"malformed announcement keeps opaque cover")
    ctx:Dispatch("loadinggame",3);ctx:Dispatch("entryprepare",{Token="valid"})
    ctx:Dispatch("loadinggame",malformed)
    equal(ctx.State.Token,"valid","late malformed announcement cannot reset valid entry")
    equal(ctx.State.KnownLevel,3,"late malformed announcement keeps exact level")
end
for level=1,6 do
    local ctx=fresh();ctx:Dispatch("loadinggame",tostring(level))
    equal(ctx.PaletteLevels[1],level,"numeric announced level remains supported")
    equal(ctx.Cards.root.Visible,true,"each confirmed level unhides renderer")
end
for _,terminal in ipairs({"lobby","start","entryreleased","entrycancel","loadfailed"}) do
    local ctx=fresh();ctx:Dispatch("loadinggame",3)
    ctx:Dispatch("entryprepare",{Token="done"})
    ctx:Dispatch(terminal,(terminal=="loadfailed") and "BUILD_ERROR" or {Token="done"})
    equal(ctx.State.KnownLevel,nil,"terminal event retires confirmed entry level")
end
print(string.format("Round loading notice: %d checks passed (real helpers, event branches, attribute fallback, fake-clock delivery races)",checks))
'''

def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests executed.")
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile" + Path(binary).suffix))
    source = SOURCE.read_text(encoding="utf-8")
    replacements = {
        "__PERSISTENT_GUI__": next(line.strip() for line in source.splitlines() if "gui.ResetOnSpawn =" in line),
        "__ENTRY_STATE__": section(source, "local entryState =", "local function finishLoadingWhenReady()"),
        "__MESSAGES__": section(source, "local DEFAULT_TEXT =", "-- Level 1 command briefing."),
        "__LOBBY__": section(source, '\tif ev == "lobby" then', '\telseif ev == "lobbybriefing" then'),
        "__QUEUE__": section(source, '\telseif ev == "queueconfigured" then', '\telseif ev == "queueconfigclosed" then'),
        "__ENTRY_EVENTS__": section(source, '\telseif ev == "loadinggame" then', '\telseif ev == "poolaccess" then'),
        "__START__": section(source, '\telseif ev == "start" then', '\telseif ev == "death" then'),
        "__RESTORE__": source[source.index('do\n\tlocal function restoreLoadingError()'):],
        "__DIRECT_BRIEF__": 'label.Text = "ANOTHER STATUS"',
    }
    host = HOST
    for marker, content in replacements.items():
        host = host.replace(marker, content)
    # The Level 2 briefing is deleted whole (owner, 2026-10-08): no cue, sound,
    # state, function or asset of it may come back with a stale Studio pull.
    for needle in ("levelTwoBriefing", "LevelTwoBriefing", "LevelTwoRadio", "LEVEL_TWO_", "isLevelTwoParticipant",
                   "139075030898721", "121765399252460", "alert an unidentified"):
        assert needle not in source, f"RoundUI still carries the Level 2 briefing: {needle}"
    # Nothing anywhere in RoundUI may hang a picture on the cover (owner G3).
    for child in re.findall(r"^(\w+)\.Parent = loadingFrame$", source, re.M):
        made = re.search(rf'^local {child} = Instance\.new\("(\w+)"\)', source, re.M)
        assert made and made.group(1) == "TextLabel", f"{child} on the loading cover is not a TextLabel"
    subprocess.run([compiler, "--null", str(SOURCE)], check=True, timeout=20)
    with tempfile.TemporaryDirectory(prefix="round-loading-notice-") as directory:
        for name, chunk in (("notice.luau", host),):
            path = Path(directory) / name
            path.write_text(chunk, encoding="utf-8")
            subprocess.run([binary, str(path)], check=True, timeout=20)
    from test_hud_b8 import main as verify_b8
    verify_b8()


if __name__ == "__main__":
    main()
