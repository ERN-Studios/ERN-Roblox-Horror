"""Presentation reports cannot write gameplay fields or bypass validation."""
from pathlib import Path
import os
import subprocess
import tempfile
root=Path(__file__).resolve().parents[2]
source=(root/'ServerScriptService/GameManager.Script.lua').read_text(encoding='utf-8')
start=source.index('local spectatorVitalReports =')
block=source[start:source.index('local handlePostWinReturnRequest',start)]
prelude='''
local now=0
local os={clock=function() return now end}
local inRound={}
local p={attrs={},hum={Health=100}}
p.Character={FindFirstChildOfClass=function() return p.hum end}
function p:GetAttribute(k) return self.attrs[k] end
function p:SetAttribute(k,v) self.attrs[k]=v end
inRound[p]=true
local checks=0
local function check(v) checks+=1 assert(v,'check '..checks) end
'''
tests='''
receiveSpectatorVital(p,{Key='Stamina',Value=.4}) check(p.attrs.SpectateStamina==.4)
receiveSpectatorVital(p,{Key='Stamina',Value=.9}) check(p.attrs.SpectateStamina==.4)
receiveSpectatorVital(p,{Key='Battery',Value=.7}) check(p.attrs.SpectateBattery==.7)
now=1
for _,value in ipairs({-1,2,math.huge,0/0,'1'}) do
 receiveSpectatorVital(p,{Key='Stamina',Value=value}) check(p.attrs.SpectateStamina==.4)
end
receiveSpectatorVital(p,{Key='Tokens',Value=1}) check(p.attrs.SpectateTokens==nil)
receiveSpectatorVital(p,{Key='Stamina',Value=.2}) check(p.attrs.SpectateStamina==.2)
now=2
p.attrs.Escaped=true
receiveSpectatorVital(p,{Key='Stamina',Value=.8}) check(p.attrs.SpectateStamina==.2)
p.attrs.Escaped=false
p.hum.Health=0
receiveSpectatorVital(p,{Key='Stamina',Value=.8}) check(p.attrs.SpectateStamina==.2)
p.hum.Health=100
inRound[p]=false
receiveSpectatorVital(p,{Key='Stamina',Value=.8}) check(p.attrs.SpectateStamina==.2)
check(p.attrs.Stamina==nil and p.attrs.Battery==nil and p.attrs.PlayerProtectionActive==nil)
print('Spectator vitals: '..checks..' checks passed')
'''
with tempfile.TemporaryDirectory() as directory:
 file=Path(directory)/'vitals.luau'
 file.write_text(prelude+block+tests,encoding='utf-8')
 subprocess.run([os.environ['LUAU_BIN'],str(file)],check=True)
