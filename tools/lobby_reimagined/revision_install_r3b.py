"""Pin the final cheek geometry as an additive payload; CAS only our RuntimeBake."""
import ast
import json
from pathlib import Path
from serve import load_package, sha
from install import long_string

ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / 'artifacts/lobby-reimagined-r3-20261001'
package = load_package(ROOT / 'assets/models/lobby-reimagined-r3-20261001',
                       source_name='LobbyReimaginedBlenderSource20261001R3B')
plan = package['plan']
previous = json.loads((TASK / 'install_revision_r3.receipt.json').read_text())
baseline = next(v for v in previous['sources'] if v['key'] == 'runtime-bake')
expected = [{'path':baseline['path'], 'class':baseline['class'], 'sourceSha256':baseline['sha256']}]
tree = ast.parse(Path(__file__).with_name('revision_install.py').read_text())
code = next(ast.literal_eval(node.value) for node in tree.body
            if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'code' for t in node.targets))
code = code.replace('R2','R3B').replace('exactly four new preview Sources','only our RuntimeBake Source').replace('Sources=4','Sources=1')
code = code.replace('__PLAN__',long_string(json.dumps(plan,separators=(',',':')))).replace('__EXPECTED__',long_string(json.dumps(expected,separators=(',',':'))))
output = TASK / 'install_revision_r3b.luau'
assert not output.exists() or output.read_text() == code, 'Refusing different final installer'
output.write_text(code)
output.with_suffix('.receipt.json').write_text(json.dumps({'sha256':sha(code.encode()),'manifestSha256':plan['manifestSha256'],'sources':plan['sources'],'expected':expected,
 'scope':'Additive final R3B Blender payload; RuntimeBake Source/editor CAS only; all shared adapters unchanged.'},indent=2)+'\n')
print('Final R3B installer generated',plan['manifestSha256'])
