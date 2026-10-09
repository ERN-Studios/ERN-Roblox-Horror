"""Run the preserved R4 loaders and real isolated Blender authoring QA.

No Studio/network calls or installer execution. Outputs go to a fresh private
checkpoint directory. SOURCE edits are limited to relocating the R4 builder's
single OUT assignment in a test-only AST; all imports retain their actual paths.
"""
from pathlib import Path
import argparse
import ast
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'tools/lobby_reimagined'
COMPILER = Path('C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe')
BLENDER = Path('D:/Blender/blender.exe')


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dest', type=Path, required=True)
    args = parser.parse_args()
    dest = args.dest.resolve()
    assert dest.is_relative_to(ROOT / '.git/mongotv-cleanup-20261009')
    assert not dest.exists(), 'Refuse checkpoint overwrite'
    dest.mkdir(parents=True)
    sys.path.insert(0, str(HERE))
    import serve_r4
    import install_r4
    package, manifest, payload = serve_r4.load_package(serve_r4.DEFAULT)
    # Existing authored textures are inputs to configure_pbr, and are copied
    # into the isolated output just as the normal R4 authoring workflow needs.
    shutil.copytree(package / 'textures', dest / 'r4/textures')
    assert manifest['revision'] == 4
    catalog = json.loads(serve_r4.CATALOG.read_bytes())
    blocked = False
    try:
        serve_r4.load_catalog(package, manifest, dict(payload))
    except AssertionError:
        blocked = True
    # Preserve the currently gated catalog; do not repair/deploy old candidates.
    assert blocked and catalog['sourceCount'] == 8
    plan = {k: catalog[k] for k in (
        'readyForInstaller', 'placeId', 'universeId', 'groupId',
        'sources', 'preservedSources')}
    catalog_bytes = json.dumps(catalog, separators=(',', ':')).encode()
    plan.update(sourceName=catalog['payload']['sourceName'],
                manifestBytes=len(payload['/manifest']),
                manifestSHA256=sha(payload['/manifest']),
                catalogSHA256=sha(catalog_bytes))
    code = install_r4.CODE.replace('__PLAN__', install_r4.long_string(
        json.dumps(plan, separators=(',', ':'))))
    generated = dest / 'installer-compile-only.luau'
    generated.write_text(code, encoding='utf8', newline='\n')
    compiles = []
    for optimization in ('-O0', '-O1'):
        result = subprocess.run([str(COMPILER), '--binary', optimization, str(generated)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        compiles.append({'optimization': optimization, 'bytes': len(result.stdout),
                         'sha256': sha(result.stdout)})
    # Actual quoting helper on strings that require successively larger delimiters.
    for value in ('ordinary', ']=]', ']=] ]==] ]===]', '\nUnicode æøå\n'):
        quoted = install_r4.long_string(value)
        assignment = dest / 'quoted-value.luau'
        assignment.write_text('return ' + quoted, encoding='utf8', newline='\n')
        for optimization in ('-O0', '-O1'):
            result = subprocess.run([str(COMPILER), '--binary', optimization, str(assignment)],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            assert result.returncode == 0, result.stderr.decode(errors='replace')
    wrapper = dest / 'blender-probe.py'
    wrapper.write_text('''from pathlib import Path
import ast, importlib.util, json, os
HERE = Path(__HERE__)
DEST = Path(__DEST__)
spec = importlib.util.spec_from_file_location('actual_props_qa', HERE / 'verify_props.py')
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
qa.OUT = DEST / 'props'
os.environ['LOBBY_PROP_QA_RENDER'] = '0'
qa.main()
import bpy
# Fresh factory state within this test-only background process. Prop QA's
# intentionally retained test objects would otherwise correctly trip R4's
# refusal to overwrite names, before the real standalone workflow can run.
bpy.ops.wm.read_factory_settings(use_empty=False)
source = (HERE / 'build_r4.py').read_text(encoding='utf8')
tree = ast.parse(source)
changed = 0
for node in tree.body:
    if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) and node.targets[0].id == 'OUT':
        node.value = ast.Call(func=ast.Name(id='Path', ctx=ast.Load()), args=[ast.Constant(value=str(DEST / 'r4'))], keywords=[])
        changed += 1
assert changed == 1, 'Only one test-owned OUT relocation allowed'
ast.fix_missing_locations(tree)
namespace = {'__file__': str(HERE / 'build_r4.py'), '__name__': '__main__'}
exec(compile(tree, str(HERE / 'build_r4.py'), 'exec'), namespace)
'''.replace('__HERE__', repr(str(HERE))).replace('__DEST__', repr(str(dest))),
                       encoding='utf8', newline='\n')
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    with (dest / 'blender.log').open('wb') as log:
        completed = subprocess.run([str(BLENDER), '--background', '--factory-startup', '--python-exit-code', '1',
                                    '--python', str(wrapper), '--', '--skip-renders'],
                                   stdout=log, stderr=subprocess.STDOUT, env=environment)
    assert completed.returncode == 0, 'Real Blender authoring port failed; inspect private log'
    prop_report = json.loads((dest / 'props/report.json').read_bytes())
    assert all(v is True for k, v in prop_report['checks'].items()
               if k != 'live_blender_or_studio_mutated')
    assert prop_report['checks']['live_blender_or_studio_mutated'] is False
    # Load and validate the actual freshly generated R4 mesh/PBR package.
    _, generated_manifest, generated_payload = serve_r4.load_package(dest / 'r4')
    receipt = {
        'schema': 'retired-lobby-authoring-active-port-v1', 'pass': True,
        'actualR4Payload': {name: {'bytes': len(raw), 'sha256': sha(raw)}
                            for name, raw in sorted(payload.items())},
        'preservedCatalogGate': {'blocked': blocked, 'sourceCount': catalog['sourceCount'],
                                'catalogSHA256': sha(serve_r4.CATALOG.read_bytes())},
        'generatedInstallerSHA256': sha(code.encode()), 'generatedInstallerCompiles': compiles,
        'quoteCompileChecks': 8, 'props': prop_report,
        'freshR4Payload': {name: {'bytes': len(raw), 'sha256': sha(raw)}
                          for name, raw in sorted(generated_payload.items())},
        'freshR4Counts': {k: generated_manifest[k] for k in
                         ('uniqueTriangles', 'instantiatedTriangles')},
        'scope': 'Actual preserved R4 package/loaders/quoting/generated compile and fresh isolated Blender prop QA + R4 build. No Studio/runtime/gameplay/installer/upload/performance pass.'}
    (dest / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf8', newline='\n')
    print(json.dumps({'pass': True, 'receipt': str(dest / 'receipt.json'),
                      'payloadEndpoints': len(payload), 'freshEndpoints': len(generated_payload),
                      'propsChecks': len(prop_report['checks'])}))


if __name__ == '__main__':
    main()
