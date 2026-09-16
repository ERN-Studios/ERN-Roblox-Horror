"""Verify and record only Codex's two already-applied animation scripts."""
from pathlib import Path
import sys,json,time,hashlib
import difflib
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from sync_from_studio import StudioMcpClient,find_mcp_batch,select_studio
from studio_source_contract import normalize,refresh_trailing_newline_metadata
paths={
 'StarterPlayer/StarterPlayerScripts/Level 3 Table Hiding Client.LocalScript.lua':"game.StarterPlayer.StarterPlayerScripts['Level 3 Table Hiding Client']",
 'ServerScriptService/Level 3 Systems/Level 3 Configuration.ModuleScript.lua':"game.ServerScriptService['Level 3 Systems']['Level 3 Configuration']",
}
client=StudioMcpClient(find_mcp_batch())
try:
 client.initialize();time.sleep(2);select_studio(client,'BACKROOMS: STAY QUIET [CO-OP HORROR]',20)
 verified={}
 for file,expr in paths.items():
  actual=client.call('execute_luau',{'datamodel_type':'Edit','code':'return '+expr+'.Source'})
  repo=(ROOT/file).read_text(encoding='utf-8')
  if normalize(actual).rstrip('\n')!=normalize(repo).rstrip('\n'):
   print('DIFF',file,repr(actual[:100]),len(actual),len(repo))
   print('\n'.join(list(difflib.unified_diff(normalize(repo).splitlines(),normalize(actual).splitlines()))[:35]))
  assert normalize(actual).rstrip('\n')==normalize(repo).rstrip('\n'),file+' drifted'
  assert normalize(actual) in (normalize(repo),normalize(repo)+'\n'),file+' newline mismatch'
  verified[file]=(repo,normalize(actual)==normalize(repo)+'\n')
 manifest_path=ROOT/'studio-sync-manifest.json';manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
 for entry in manifest['items']:
  if entry['file'] not in verified:continue
  repo,extra=verified[entry['file']];data=normalize(repo).encode('utf-8')
  entry.update(bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),status='synced')
  entry.pop('studioSha256Before',None)
  if extra:entry['studioTrailingNewline']=True
  else:entry.pop('studioTrailingNewline',None)
 refresh_trailing_newline_metadata(manifest)
 manifest_path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8',newline='\n')
 report={file:{'sha256':hashlib.sha256(normalize(v[0]).encode()).hexdigest(),'synced':True,'studioExtraNewline':v[1]} for file,v in verified.items()}
 (Path(__file__).parent/'animation-source-parity.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report))
finally:client.close()
