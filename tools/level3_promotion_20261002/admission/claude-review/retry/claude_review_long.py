"""Bounded tools-disabled Claude review of explicitly supplied task files only."""
from pathlib import Path
import argparse,collections,datetime,hashlib,json,os,selectors,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--prompt',required=True,type=Path);p.add_argument('--out',required=True,type=Path);p.add_argument('--timeout',type=int,default=180)
a=p.parse_args();assert 30<=a.timeout<=900
a.out.mkdir(parents=True,exist_ok=True)
cli=Path('/Users/zeanjuul4/.local/bin/claude');raw=a.prompt.read_bytes()
arguments=['--print','--safe-mode','--no-chrome','--strict-mcp-config','--mcp-config','{"mcpServers":{}}','--tools','','--permission-mode','dontAsk','--permission-prompts','none','--disable-slash-commands','--no-session-persistence','--model','opus','--effort','max','--input-format','stream-json','--output-format','stream-json','--verbose','--system-prompt','You are a read-only Roblox Luau code-security and game-behavior reviewer. Use only supplied code and facts. You have no tools and cannot inspect or mutate live applications. Distinguish tested facts from inference. Give concise concrete findings within the requested word limit. Do not disclose private internal reasoning.']
message={'type':'user','message':{'role':'user','content':[{'type':'text','text':raw.decode()}]}}
start=datetime.datetime.now(datetime.timezone.utc);clock=time.monotonic()
child=subprocess.Popen([str(cli),*arguments],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
child.stdin.write((json.dumps(message)+'\n').encode());child.stdin.close()
sel=selectors.DefaultSelector();sel.register(child.stdout,selectors.EVENT_READ,'out');sel.register(child.stderr,selectors.EVENT_READ,'err')
pending=b'';stderr=b'';models=set();counts=collections.Counter();text=[];result=None;init=None;timeout=False

def event(line):
 global result,init
 try:v=json.loads(line)
 except (ValueError,UnicodeDecodeError):return
 counts[v.get('type','unknown')]+=1
 if v.get('type')=='system' and v.get('subtype')=='init':init={k:v.get(k) for k in ['model','tools','mcp_servers','permissionMode','claude_code_version']}
 if v.get('type')=='assistant':
  msg=v.get('message',{})
  if msg.get('model'):models.add(msg['model'])
  for c in msg.get('content',[]):
   if c.get('type')=='text':text.append(c['text'])
 if v.get('type')=='result':
  result={k:v.get(k) for k in ['subtype','is_error','result','duration_ms','duration_api_ms','num_turns','total_cost_usd','usage','modelUsage','permission_denials']}
while sel.get_map():
 if time.monotonic()-clock>a.timeout:
  timeout=True;child.terminate()
  try:child.wait(timeout=5)
  except subprocess.TimeoutExpired:child.kill();child.wait(timeout=5)
  break
 for key,_ in sel.select(timeout=.25):
  data=os.read(key.fileobj.fileno(),65536)
  if not data:sel.unregister(key.fileobj);continue
  if key.data=='err':stderr=(stderr+data)[-8000:]
  else:
   pending+=data
   while b'\n' in pending:
    line,pending=pending.split(b'\n',1);event(line)
if pending:event(pending)
if child.poll() is None:child.wait(timeout=5)
visible=result.get('result') if result and result.get('result') else '\n\n'.join(text)
(a.out/'response.md').write_text((visible or '')+'\n')
if stderr:(a.out/'stderr.txt').write_bytes(stderr)
receipt={'schema':'level3-promotion-claude-review-v1','scope':'Read-only explicitly supplied code/facts, tools disabled; no Studio access','commandArguments':arguments,'cliPath':str(cli),'startedAtUTC':start.isoformat(),'finishedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'requestedModel':'opus','reportedCanonicalModel':init.get('model') if init else None,'reportedAssistantModels':sorted(models),'requestedEffort':'max','strictEmptyMcpConfig':True,'reportedTools':init.get('tools') if init else None,'inputPrompt':str(a.prompt),'inputPromptSHA256':hashlib.sha256(raw).hexdigest(),'elapsedSeconds':round(time.monotonic()-clock,3),'hardTimeoutSeconds':a.timeout,'exitCode':child.returncode,'spawnedChildPID':child.pid,'cleanupTarget':'Only directly spawned owned Claude CLI PID','childExitConfirmed':child.poll() is not None,'timedOut':timeout,'status':'success' if result and not result.get('is_error') and child.returncode==0 and not timeout else 'failed','result':result,'eventTypeCounts':dict(counts),'rawInternalStreamSaved':False}
(a.out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({k:receipt[k] for k in ['status','reportedCanonicalModel','reportedAssistantModels','elapsedSeconds','exitCode','timedOut']}))
if receipt['status']!='success':raise SystemExit(1)
