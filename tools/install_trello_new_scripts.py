"""Create the four approved new scripts through Studio's supported editor tool.

Verify raw Source before registering the result in the sync manifest.
"""
from pathlib import Path
import json, time
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio
from studio_source_contract import normalize, sha256_of, classify, refresh_trailing_newline_metadata

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ('ReplicatedStorage/UIStyle.ModuleScript.lua', 'ReplicatedStorage.UIStyle', 'ModuleScript'),
    ('ServerScriptService/LobbyShopDisplay.ModuleScript.lua', 'ServerScriptService.LobbyShopDisplay', 'ModuleScript'),
    ('StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua', 'StarterPlayer.StarterPlayerScripts.Shop Display Client', 'LocalScript'),
    ('StarterPlayer/StarterPlayerScripts/Level 1 Cable Current.LocalScript.lua', 'StarterPlayer.StarterPlayerScripts.Level 1 Cable Current', 'LocalScript'),
]

def main():
    client = StudioMcpClient(find_mcp_batch())
    manifest_path = ROOT/'studio-sync-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    try:
        client.initialize(); time.sleep(3)
        studio = select_studio(client, 'BACKROOMS: STAY QUIET [CO-OP HORROR]', 20)
        sid = studio['id']
        for file, path, kind in FILES:
            src = normalize((ROOT/file).read_text(encoding='utf-8'))
            read = 'local c=game;for _,n in '+json.dumps(path.split('.')).replace('[','{').replace(']','}')+' do c=c and c:FindFirstChild(n) end;return game:GetService("HttpService"):JSONEncode(c and {class=c.ClassName,source=c.Source} or {missing=true})'
            live = json.loads(client.call('execute_luau', {'studio_id':sid,'datamodel_type':'Edit','code':read}))
            if live.get('missing'):
                client.call('multi_edit', {'studio_id':sid,'datamodel_type':'Edit','file_path':'game.'+path,'className':kind,'edits':[{'old_string':'','new_string':src}]})
                live = json.loads(client.call('execute_luau', {'studio_id':sid,'datamodel_type':'Edit','code':read}))
            assert live['class']==kind
            actual = normalize(live['source'])
            assert actual in (src,src+'\n'), f'Source mismatch: {path}'
            item = {'studioPath':path,'className':kind,'file':file,'bytes':len(src.encode()),'sha256':sha256_of(src),'status':'synced'}
            if actual==src+'\n': item['studioTrailingNewline']=True
            manifest['items']=[i for i in manifest['items'] if i['file']!=file]+[item]
            manifest['studio'] = studio
            manifest['counts']['scripts']=sum(i['className'] in ('Script','LocalScript','ModuleScript') for i in manifest['items'])
            manifest['counts']['total']=len(manifest['items'])
            refresh_trailing_newline_metadata(manifest)
            manifest_path.write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
            print('VERIFIED',path)
    finally: client.close()

if __name__=='__main__': main()
