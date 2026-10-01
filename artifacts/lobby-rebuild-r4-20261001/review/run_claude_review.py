from pathlib import Path
import subprocess, json, time
root=Path(__file__).resolve().parent
start=time.time()
cmd=['/Users/zeanjuul4/.local/bin/claude','--print','--model','claude-opus-5-5','--effort','max','--tools','','--strict-mcp-config','--no-chrome','--disable-slash-commands','--no-session-persistence','--output-format','json']
try:
    r=subprocess.run(cmd,input=(root/'claude-design-prompt.txt').read_text(),capture_output=True,text=True,timeout=180)
    (root/'claude-design-result.json').write_text(r.stdout)
    (root/'claude-design-stderr.log').write_text(r.stderr)
    print(json.dumps({'exit':r.returncode,'elapsed':round(time.time()-start,2),'stdoutBytes':len(r.stdout),'stderrBytes':len(r.stderr),'requestedModel':'claude-opus-5-5','requestedEffort':'max','ultraFlagAvailable':False}))
except subprocess.TimeoutExpired:
    print(json.dumps({'timedOut':True,'elapsed':round(time.time()-start,2)}))
