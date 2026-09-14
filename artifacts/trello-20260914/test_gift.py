from pathlib import Path
import subprocess
HERE=Path(__file__).resolve().parent
source=(HERE/'gift-integration.luau').read_text(encoding='utf-8')
tests=r'''
end
local profile={Grants={},StaminaLevel=3,BatteryLevel=7,Tokens=2,ReceiptIds={'kept'}}
local function apply(_,fn) return fn(profile) end
reward({UserId=99},apply)
assert(profile.Tokens==2)
reward({UserId=10152463945},apply)
reward({UserId=10152463945},apply)
assert(profile.Tokens==12 and profile.StaminaLevel==4 and profile.BatteryLevel==8)
assert(profile.ReceiptIds[1]=='kept' and profile.Grants.AdvancedEquipment==nil)
print('PASS gift transformation: intended user only, repeat no-op, additive upgrades, receipt/pass flags preserved')
'''
host=HERE/'gift-runtime.luau'
host.write_text('local function reward(player,mutate)\n'+source+tests,encoding='utf-8')
r=subprocess.run([r'C:\Users\mikke\AppData\Local\Temp\codex-luau-0.737\luau.exe',str(host)],text=True,capture_output=True)
print(r.stdout,end='');print(r.stderr,end='');raise SystemExit(r.returncode)
