"""Root-only bounded actual-play calls, recorded separately from Edit contracts."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[3]
TASK=ROOT/'tools/optimization_20261009'
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--studio-id',required=True)
    p.add_argument('--dm',required=True,choices=['Client','Server'])
    p.add_argument('--label',required=True)
    p.add_argument('--code',required=True)
    a=p.parse_args()
    assert a.label.replace('-','').replace('_','').isalnum()
    file=(ROOT/a.code).resolve()
    assert file.is_relative_to(TASK)
    code='''assert(game:GetService("RunService"):IsRunning(),"Actual Play required")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong test place/universe")
''' + file.read_bytes().decode()
    c=StudioMcpClient(find_mcp_batch())
    row={'studioId':a.studio_id,'datamodel':a.dm,'label':a.label,'code':a.code,'startedUtc':datetime.now(timezone.utc).isoformat()}
    output=TASK/'runtime/observations'/f'{a.label}.json'
    output.parent.mkdir(exist_ok=True)
    try:
        c.initialize()
        raw=c.call('execute_luau',{'studio_id':a.studio_id,'datamodel_type':a.dm,'code':code})
        try: row['result']=json.loads(raw)
        except json.JSONDecodeError: row['resultText']=raw
        row['completed']=True
        if isinstance(row.get('result'),dict):
            print(json.dumps(row['result'],ensure_ascii=True)[:4500])
        else: print('Recorded',a.label)
    except Exception as error:
        row['completed']=False; row['error']=str(error)
        raise
    finally:
        row['finishedUtc']=datetime.now(timezone.utc).isoformat()
        output.write_text(json.dumps(row,indent=2)+'\n')
        c.close()

if __name__=='__main__':main()
