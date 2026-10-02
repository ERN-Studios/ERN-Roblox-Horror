from pathlib import Path
import json
p=Path(__file__).resolve().parent
plan=json.loads((p/'plan.json').read_text())
def lua(v):
    if isinstance(v,dict):return '{'+','.join('['+json.dumps(k)+']='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
    if isinstance(v,bool):return 'true' if v else 'false'
    if v is None:return 'nil'
    return str(v)
current=(p/'EndBlockades.ModuleScript.luau').read_text()
start=current.index('local PLAN = ')
end=current.index('\nfunction Module.Add', start)
current=current[:start]+'local PLAN = '+lua(plan)+current[end:]
(p/'EndBlockades.ModuleScript.luau').write_text(current)
