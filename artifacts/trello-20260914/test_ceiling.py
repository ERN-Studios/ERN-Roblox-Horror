"""Execute the complete proposed ceiling controller against fake engine objects."""
from pathlib import Path
import subprocess
HERE = Path(__file__).resolve().parent
BIN = Path(r'C:\Users\mikke\AppData\Local\Temp\codex-luau-0.737')
SOURCE = HERE / '../../StarterPlayer/StarterPlayerScripts/LobbyCeilingSweeps.LocalScript.lua'
PRELUDE = r'''
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function signal()
 return {Connect=function(self,fn) self.fn=fn; return {Disconnect=function() end} end}
end
local colorMeta = {__mul=function(c,n) return setmetatable({value=c.value*n},getmetatable(c)) end}
colorMeta.__index = {Lerp=function(c,target,alpha) return setmetatable({value=c.value+(target.value-c.value)*alpha},getmetatable(c)) end}
local Color3={fromRGB=function(r,g,b) return setmetatable({value=r+g+b},colorMeta) end, new=function(r,g,b) return setmetatable({value=(r or 0)+(g or 0)+(b or 0)},colorMeta) end}
local Enum={Material={Neon='Neon',SmoothPlastic='SmoothPlastic'}}
local Random={new=function() return {NextNumber=function() return 10 end, NextInteger=function() return 1 end} end}
local fakePlayer={attrs={ReduceFlashing=false}}
function fakePlayer:GetAttribute(k) return self.attrs[k] end
function fakePlayer:GetAttributeChangedSignal() return signal() end
local fakeLobby={attrs={}}
function fakeLobby:GetAttribute(k) return self.attrs[k] end
function fakeLobby:GetAttributeChangedSignal() return signal() end
local fakeLighting={parts={}}
function fakeLighting:GetDescendants() return self.parts end
function fakeLobby:FindFirstChild() return fakeLighting end
local workspace={attrs={}}
function workspace:FindFirstChild() return fakeLobby end
function workspace:GetAttribute(k) return self.attrs[k] end
function workspace:GetAttributeChangedSignal() return signal() end
local game={GetService=function(_,name)
 if name=='Players' then return {LocalPlayer=fakePlayer} end
 return {Heartbeat=signal()}
end}
local script={Destroying=signal()}
for lane=1,2 do for row=0,5 do
 local p={Color=Color3.fromRGB(220,230,240),Material=Enum.Material.Neon,Position={X=lane*10,Z=row*20}}
 p.initialColor=p.Color
 p.light={Color=p.Color,Brightness=1.5,Enabled=true,Parent=p}
 function p:IsA(k) return k=='BasePart' end
 function p:GetAttribute() return true end
 function p:FindFirstChildWhichIsA() return self.light end
 function p:IsDescendantOf(parent) return not self.removed and parent==fakeLighting end
 table.insert(fakeLighting.parts,p)
end end
local originalColor=fakeLighting.parts[1].Color
'''
POSTLUDE = r'''
for pattern=1,5 do
 beginSweep(100)
 active.pattern=pattern
 local offCounts, wasOn, signatures={},{},{}
 for i=1,#fakeLighting.parts do offCounts[i]=0; wasOn[i]=true end
 for tick=0,120 do
  update(100+tick*.05)
  local signature=''
  for i,p in ipairs(fakeLighting.parts) do
   local on=p.light.Enabled
   if wasOn[i] and not on then offCounts[i]+=1 end
   wasOn[i]=on
   check(p.light.Brightness==1.5,'brightness baseline changed')
   check(p.light.Color==p.initialColor,'light color baseline changed')
   check(on or p.Material==Enum.Material.SmoothPlastic,'off fixture still neon')
   signature..=if on then '1' else '0'
  end
  table.insert(signatures,signature)
 end
 for i,p in ipairs(fakeLighting.parts) do
  check(offCounts[i]==1,'pattern '..pattern..' must switch each fixture off exactly once')
  check(p.light.Enabled and p.Material==Enum.Material.Neon,'fixture not restored')
 end
 _G -- no-op removed below
 if pattern==1 then check(signatures[31]~=signatures[91],'sweep did not travel') end
end
beginSweep(200); update(203)
fakePlayer.attrs.ReduceFlashing=true; update(203.05)
for _,p in ipairs(fakeLighting.parts) do check(p.light.Enabled and p.Material=='Neon','accessibility restoration') end
check(active==nil and not allowed,'ReduceFlashing did not stop controller')
fakePlayer.attrs.ReduceFlashing=false; update(204)
beginSweep(205); update(208)
local fixture=fakeLighting.parts[3]
local partyColor=Color3.fromRGB(255,0,0)
fixture.Color=partyColor
fakeLobby.attrs.PartyModeActive=true; update(208.05)
check(fixture.Color==partyColor,'party color overwritten')
for _,p in ipairs(fakeLighting.parts) do check(p.light.Enabled and p.Material=='Neon','party inherited dark fixture') end
fakeLobby.attrs.PartyModeActive=false; update(210)
beginSweep(211); update(214)
fakePlayer.attrs.InRound=true; update(214.05)
check(active==nil and not allowed,'round entry not restored')
fakePlayer.attrs.InRound=false; update(215)
beginSweep(216); update(219)
script.Destroying.fn()
for _,p in ipairs(fakeLighting.parts) do check(p.light.Enabled and p.Material=='Neon','destroy did not restore') end
print('PASS ceiling controller: '..checks..' runtime assertions, all five on/off patterns and lifecycle restoration')
'''.replace(' _G -- no-op removed below\n','')
host = HERE / 'ceiling-runtime.luau'
host.write_text(PRELUDE + '\n' + SOURCE.read_text(encoding='utf-8') + '\n' + POSTLUDE, encoding='utf-8')
result = subprocess.run([str(BIN/'luau.exe'),str(host)],capture_output=True,text=True)
print(result.stdout, end='')
print(result.stderr, end='')
raise SystemExit(result.returncode)
