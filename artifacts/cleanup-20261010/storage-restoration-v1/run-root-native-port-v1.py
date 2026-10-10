"""Run one frozen native phase once and post its actual completion; no mode changes."""
from pathlib import Path
import hashlib,json,sys,time,urllib.request
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
RUN=HERE/'native-v4-run-v1';SID='1b603e69-7ae1-4572-b210-d5bf05c684ff'
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch,require_edit_state
phase=sys.argv[1];assert phase in ('baseline','probe')
code=(RUN/(phase+'-source.luau')).read_bytes()
pin={'baseline':'df846a007464c2f5bf11284b69eecf32b0c8ecaf4fe776481489483fc7095a2b','probe':'133436198c3b5a7338f9327beb8d8023c14203ee1dbb69372b2287d65b22c31b'}[phase]
assert hashlib.sha256(code).hexdigest()==pin
assert hashlib.sha256((HERE/'receiver.py').read_bytes()).hexdigest()=='4a70b5216d45321461aa9e0c482cefc6391b389ef92e2f905783a60d832267bc'
peer=(HERE.parent/'foundation-next-v1/storage-v4-peer-review-v1.json').read_bytes()
assert hashlib.sha256(peer).hexdigest()=='d7d6c68add3a3aa9a55b9f2269883c3583827c4b5f2a58a7e2db5f22563da1c8' and json.loads(peer)['preparationPeerPassed']
def save(name,raw):
 with (RUN/name).open('xb') as f:f.write(raw)
assert not (RUN/(phase+'-root-api.json')).exists() and not (RUN/(phase+'-root-completion.json')).exists()
client=StudioMcpClient(find_mcp_batch());client.initialize();started=time.monotonic()
try:
 require_edit_state(client,SID)
 print('Root running one pinned native '+phase+' phase; no retry or mode switch',flush=True)
 try:
  response=client._request('tools/call',{'name':'execute_luau','arguments':{'studio_id':SID,'datamodel_type':'Edit','code':code.decode('utf8')}},timeout=600)
 except BaseException as error:
  save(phase+'-unknown-transport.json',(json.dumps({'status':'unknown native outcome; no retry','error':str(error),'executedCodeSHA256':pin,'phase':phase},indent=2)+'\n').encode())
  raise
 save(phase+'-root-api.json',(json.dumps(response,indent=2)+'\n').encode())
 result=response.get('result',{});text='\n'.join(c.get('text','') for c in result.get('content',[]) if c.get('type')=='text')
 assert len(text.encode())<=30000,'Native completion exceeds bounded response'
 assert not result.get('isError'),text
 proof=json.loads(text);raw=text.encode('utf8')
 save(phase+'-root-completion.json',raw)
 save(phase+'-root-provenance.json',(json.dumps({'phase':phase,'executedCodeSHA256':pin,'completionSHA256':hashlib.sha256(raw).hexdigest(),'actualNativeResponse':True,'rootClientWallSeconds':round(time.monotonic()-started,3),'noRetry':True,'limits':'Probe duration is not a performance gain. Native result claims retained unmodified; no synthetic PASS fields.'},indent=2)+'\n').encode())
 endpoint='baseline-completion' if phase=='baseline' else 'completion'
 request=urllib.request.Request('http://127.0.0.1:18916/'+endpoint,data=raw,headers={'Content-Type':'application/json'},method='POST')
 with urllib.request.urlopen(request,timeout=30) as response:
  body=response.read();assert response.status==200 and body==b'saved'
 save(phase+'-root-post-result.json',(json.dumps({'endpoint':endpoint,'status':200,'body':'saved','sentActualCompletionSHA256':hashlib.sha256(raw).hexdigest()},indent=2)+'\n').encode())
 require_edit_state(client,SID)
 print(json.dumps(proof),flush=True)
 if phase=='baseline':
  assert proof['pass'] and proof['originalSourcesUnchanged'] and proof['liveSources']==213
 else:
  verdict=json.loads((RUN/'port-verdict.json').read_bytes())
  assert verdict['recipePassed']==proof['pass'] and not verdict['restorationCertified'] and not verdict['normalizationApplied']
  print(json.dumps(verdict),flush=True)
finally:client.close()
