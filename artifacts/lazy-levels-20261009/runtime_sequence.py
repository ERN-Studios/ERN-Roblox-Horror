"""Run explicitly selected normal native QA phases in an already running Studio.

No Edit writes, Play lifecycle changes, forced readiness or forced map parking.
Every phase keeps its immutable runtime_probe.py receipt. Failure cleanup never
abandons an engine owner or forces an active round to end.
"""
import argparse
import json
from pathlib import Path
import importlib.util

spec=importlib.util.spec_from_file_location('lazy_native_phases',Path(__file__).with_name('runtime_probe.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)

FLOWS={
 'continue6':('lobby-server','lobby-client','launch5','entry5-server','entry5-client',
  'finish5-server','continue5-client','continue-server','entry6-client','leave6-client',
  'exit6-server','exit-client','launch6','entry6-server','entry6-client','leave6-client',
  'exit6-server','exit-client'),
}

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--session',required=True)
 parser.add_argument('--flow',choices=FLOWS,required=True)
 args=parser.parse_args()
 passed=True
 try:
  for number,phase in enumerate(FLOWS[args.flow],1):
   path,receipt=p.invoke(phase,args.session,'sequence-'+str(number))
   print(json.dumps({'phase':phase,'number':number,'passed':receipt['passed'],'receipt':str(path)}),flush=True)
   if not receipt['passed']:
    passed=False
    break
 finally:
  for phase in ('cleanup-client','cleanup-server'):
   try:
    path,receipt=p.invoke(phase,args.session,'sequence-cleanup')
    print(json.dumps({'phase':phase,'passed':receipt['passed'],'receipt':str(path)}),flush=True)
    passed=passed and receipt['passed']
   except BaseException as error:
    passed=False
    print(json.dumps({'phase':phase,'passed':False,'error':type(error).__name__+': '+str(error)}),flush=True)
 if not passed:raise SystemExit(1)

if __name__=='__main__':main()
