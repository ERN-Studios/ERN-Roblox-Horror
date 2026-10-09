"""Offline exact-identity guards; no Studio, repository mirror or Git writes."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import sys

sys.dont_write_bytecode = True
from install_sources import strict_identity_guard

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--luau', required=True)
    args = parser.parse_args()
    expected = {'path': 'StarterPlayer.StarterPlayerScripts.SpectateController',
        'name': 'SpectateController', 'instanceId': '1_31073', 'parentId': '1_410029',
        'parentPath': 'StarterPlayer.StarterPlayerScripts', 'parentClass': 'StarterPlayerScripts'}
    assert strict_identity_guard(None) == ''
    try:
        strict_identity_guard({'path': expected['path']})
    except AssertionError:
        pass
    else:
        raise AssertionError('Incomplete reviewed metadata accepted')
    encoded = '{' + ','.join(k + '=' + json.dumps(v) for k, v in expected.items()) + '}'
    source = '''local reviewed=%s
local H={JSONDecode=function() return reviewed end}
local function test(changed,okExpected)
 local values=table.clone(reviewed)
 if changed then values[changed]="changed" end
 local parent={ClassName=values.parentClass,GetDebugId=function() return values.parentId end,
  GetFullName=function() return values.parentPath end}
 local node={Name=values.name,Parent=parent,GetDebugId=function() return values.instanceId end,
  GetFullName=function() return values.path end}
 local ok=pcall(function()
%s
 end)
 assert(ok==okExpected,changed or "exact baseline")
end
test(nil,true)
for _,key in {"path","name","instanceId","parentId","parentPath","parentClass"} do test(key,false) end
print("7 exact identity scenarios passed")
''' % (encoded, strict_identity_guard(expected))
    with tempfile.TemporaryDirectory(prefix='optimization-identity-') as directory:
        fixture = Path(directory) / 'identity.luau'
        fixture.write_text(source, encoding='utf-8')
        result = subprocess.run([args.luau, str(fixture)], capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
    print(json.dumps({'offlineChecks': 9, 'passed': True, 'studioMutation': False,
        'nativeBackup': False, 'gitIndexTouched': False}))

if __name__ == '__main__':
    main()
