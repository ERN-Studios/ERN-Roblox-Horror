"""Run RoundUI's actual loading-error helpers/event branches with a fake clock.

The server replays loadfailed after cleanup, and the attribute can arrive on
either side of the remote. Test those real delivery orders, message ownership,
retry generations and absolute expiry; also compile the complete 200-local HUD.
"""

import os
from pathlib import Path
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
    local ctx={Now=100,Timers={},TimerCount=0,CancelCount=0}
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
    function player:GetAttribute(name) assert(name=="RoundLoadingError");return self.Attribute end
    function player:GetAttributeChangedSignal(name) assert(name=="RoundLoadingError");return self.Changed end
    function ctx:SetAttribute(value)
        if player.Attribute~=value then player.Attribute=value;player.Changed.Fire() end
    end
    function ctx:ReplayAttribute() player.Changed.Fire() end
    local workspace={GetAttribute=function() return 1 end}
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
    local elevatorBriefingStarted,levelTwoBriefingStarted=false,false
    local function cancelAllCommandBriefings() ctx.CancelCount+=1 end
    local function hideRoundEnding() end
    local function stopSpectating() end
    local function applyLoadingPalette() end
    local function startLoadingSequence() end
    local function finishLoadingWhenReady() loadingFrame.Visible=false end
    local function playLevelTwoBriefing() end
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
    equal(ctx.Label.Text,"MISSION BRIEF","expected-text guard preserves direct writer")
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
        "__DIRECT_BRIEF__": next(line.strip() for line in source.splitlines() if 'label.Text = "MISSION BRIEF"' in line),
    }
    host = HOST
    for marker, content in replacements.items():
        host = host.replace(marker, content)
    subprocess.run([compiler, "--null", str(SOURCE)], check=True, timeout=20)
    with tempfile.TemporaryDirectory(prefix="round-loading-notice-") as directory:
        path = Path(directory) / "notice.luau"
        path.write_text(host, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)


if __name__ == "__main__":
    main()
