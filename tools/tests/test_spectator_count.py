"""Actual server spectator-count validation, including stale-report cleanup."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'ServerScriptService/GameManager.Script.lua').read_text(encoding='utf-8')
block = source[source.index('local spectateTargets = {}'):source.index('local lobbyBriefingReady = {}')]
prelude = '''
local Players={}
local roster={}
local inRound={}
local task={spawn=function() end}
function Players:GetPlayers() return roster end
function Players:GetPlayerByUserId(id)
 for _,p in ipairs(roster) do if p.UserId==id then return p end end
end
local function player(id)
 local p={UserId=id,Parent=Players,attrs={},hum={Health=100}}
 function p:GetAttribute(k) return self.attrs[k] end
 function p:SetAttribute(k,v) self.attrs[k]=v end
 p.Character={FindFirstChildOfClass=function() return p.hum end}
 table.insert(roster,p)
 inRound[p]=true
 return p
end
local a,b,c=player(-1),player(-2),player(42)
local checks=0
local function expect(p,n)
 checks+=1
 assert((p:GetAttribute('SpectatorCount') or 0)==n,'check '..checks)
end
'''
tests = '''
setSpectateTarget(b,a.UserId) expect(a,0)
b.attrs.Escaped=true
setSpectateTarget(b,a.UserId) expect(a,1)
setSpectateTarget(b,a.UserId) expect(a,1)
setSpectateTarget(b,c.UserId) expect(a,0) expect(c,1)
setSpectateTarget(b,b.UserId) expect(b,0) expect(c,0)
setSpectateTarget(b,math.huge) expect(a,0)
setSpectateTarget(b,a.UserId+.5) expect(a,0)
setSpectateTarget(b,a.UserId)
a.attrs.Escaped=true
republishSpectatorCounts() expect(a,0)
a.attrs.Escaped=false
setSpectateTarget(b,a.UserId)
a.hum.Health=0
republishSpectatorCounts() expect(a,0)
a.hum.Health=100
setSpectateTarget(b,a.UserId)
b.attrs.Escaped=false
republishSpectatorCounts() expect(a,0)
b.hum.Health=0
setSpectateTarget(b,a.UserId) expect(a,1)
b.Parent=nil
republishSpectatorCounts() expect(a,0)
b.Parent=Players
setSpectateTarget(b,a.UserId)
inRound[a]=false
republishSpectatorCounts() expect(a,0)
inRound[a]=true
setSpectateTarget(b,a.UserId)
clearSpectatorCounts() expect(a,0)
print('Spectator count: '..checks..' checks passed')
'''
with tempfile.TemporaryDirectory() as directory:
    file = Path(directory) / 'count.luau'
    file.write_text(prelude+block+tests, encoding='utf-8')
    subprocess.run([os.environ['LUAU_BIN'],str(file)],check=True)
