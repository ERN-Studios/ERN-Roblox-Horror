import sys, json
sys.path.insert(0, 'tools/level6_playground')
import import_to_studio as io
src = open('tools/level5_void/walker.luau').read()
s = io.Studio()
studios = json.loads(s.call('list_roblox_studios', {}))['studios']
for sec in sys.argv[1:]:
    code = src.replace("local SECTIONS = %s", "local SECTIONS = {\"" + sec + "\"}")
    try:
        res = s.request('tools/call', {'name': 'execute_luau', 'arguments': {'studio_id': s.studio_id, 'datamodel_type': 'Client', 'code': code}})
        text = '\n'.join(c.get('text', '') for c in res.get('content', []) if c.get('type') == 'text')
    except SystemExit as e:
        text = 'ERROR ' + str(e)
    print(text, flush=True)
