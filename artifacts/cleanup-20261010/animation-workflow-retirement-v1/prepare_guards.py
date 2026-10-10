"""Prepare exact tool archives and narrow retired-entry candidates only.

No production tool, runtime, native, manifest or index mutation. Root review and
actual offline CLI/helper/cache contracts precede any promotion.
"""
from pathlib import Path
import ast
import hashlib
import json
import re
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
MESSAGE = (
    "Retired Studio entity-animation authoring workflow. "
    "Published gameplay IDs, versioned receipts and regeneration inputs are retained. "
    "This entrypoint performs no upload or Studio operation."
)
PINS = {
    'tools/publish_entity_animations.py': 'dbe24a9733e2e9ddeb58f290a9ccbd9acdad63b4580fce965a9dfe90bfbb72a2',
    'tools/export_entity_keyframes_retargeted.py': '79e89584723b1325bb1e40558e9858ec2d12a0052f6afa7fe862da689b307786',
    'tools/export_entity_keyframes.py': 'ab59e31bb5e63646f895c0455c9cdd63d1be4cbd177b06436201bc0dd4d559dc',
    'tools/export_entity_animations.py': '1acc70432b429377158a04c25aca1e445562e139199ad584bc276069144cc2e4',
}
PURE = {
    'tools/publish_entity_animations.py': ('luau_table',),
    'tools/export_entity_keyframes_retargeted.py': (
        'blender_sample_code', 'matrix', 'roblox_local', 'convert_blender',
        'quaternion_xyzw', 'slerp_xyzw',
    ),
    'tools/export_entity_keyframes.py': ('safe_name',),
    'tools/export_entity_animations.py': ('safe_name',),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def save(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        assert stream.write(raw) == len(raw)


def functions(source):
    tree = ast.parse(source)
    return {node.name: ast.dump(node, include_attributes=False)
            for node in tree.body if isinstance(node, ast.FunctionDef)}


def guarded(path, before):
    newline = b'\r\n' if b'\r\n' in before else b'\n'
    anchor = b'from __future__ import annotations' + newline
    assert before.count(anchor) == 1
    declaration = ('# Owner retired this exact Studio authoring workflow, 2026-10-10.\n'
                   'RETIRED_WORKFLOW_MESSAGE = ' + repr(MESSAGE) + '\n').encode().replace(b'\n', newline)
    if path in ('tools/export_entity_keyframes.py', 'tools/export_entity_animations.py'):
        # These two scripts execute bpy/export mutations at import. No supported
        # import caller exists in the current closure; preserving that initializer
        # would retain the retired workflow. Exact original sources remain archived.
        entry = ("if __name__ == '__main__':\n"
                 "    raise SystemExit(RETIRED_WORKFLOW_MESSAGE)\n"
                 "raise RuntimeError(RETIRED_WORKFLOW_MESSAGE)\n").encode().replace(b'\n', newline)
    else:
        entry = ("if __name__ == '__main__':\n"
                 "    raise SystemExit(RETIRED_WORKFLOW_MESSAGE)\n").encode().replace(b'\n', newline)
    candidate = before.replace(anchor, anchor + newline + declaration + entry, 1)
    if path == 'tools/publish_entity_animations.py':
        retired = ('publish_code', 'main')
    elif path == 'tools/export_entity_keyframes_retargeted.py':
        retired = ('studio_rest', 'main')
    else:
        retired = ()
    for name in retired:
        pattern = re.compile(rb'(?m)^def ' + name.encode() + rb'\([^\n]*\):?' + rb'[^\n]*\r?\n')
        matches = list(pattern.finditer(candidate)); assert len(matches) == 1, name
        end = matches[0].end()
        candidate = candidate[:end] + b'    raise RuntimeError(RETIRED_WORKFLOW_MESSAGE)' + newline + candidate[end:]
    old_functions, new_functions = functions(before), functions(candidate)
    assert set(old_functions) == set(new_functions)
    assert all(old_functions[name] == new_functions[name] for name in PURE[path])
    ast.parse(candidate)
    return candidate, retired


def main():
    out = HERE/'proposal-v1'
    assert not out.exists(), 'Prior immutable proposal must remain untouched'
    initial = {path: (ROOT/path).read_bytes() for path in PINS}
    assert all(sha(raw) == PINS[path] for path, raw in initial.items())
    regeneration_path = ROOT/'artifacts/cleanup-20261010/storage-animation-dependency-v1/regeneration-inputs-v1.json'
    regeneration_raw = regeneration_path.read_bytes()
    assert sha(regeneration_raw) == '96a27be05812b23b92355ef74b50b19e18e678ea587d53a078b6f0b3a67171a5'
    regeneration = json.loads(regeneration_raw)
    assert regeneration['currentV10InputFiles'] == 8 and regeneration['versionedPublishedReceipts'] == 11
    retained = {row['file']: (ROOT/row['file']).read_bytes() for row in regeneration['files']}
    assert all(sha(retained[row['file']]) == row['rawSHA256'] for row in regeneration['files'])
    rows = []
    for path, before in initial.items():
        candidate, retired = guarded(path, before)
        save(out/'before'/path, before)
        save(out/'candidate'/path, candidate)
        rows.append({'file': path, 'beforeBytes': len(before), 'beforeSHA256': sha(before),
                     'candidateBytes': len(candidate), 'candidateSHA256': sha(candidate),
                     'retiredCallableEntries': list(retired), 'pureFunctionASTUnchanged': list(PURE[path]),
                     'syntaxPassed': True, 'allOriginalBytesRetainedInArchive': True,
                     'cliGuardBeforeOptionalAndStudioImports': True,
                     'importWorkflowRetired': path in ('tools/export_entity_keyframes.py', 'tools/export_entity_animations.py')})
    assert all((ROOT/path).read_bytes() == raw for path, raw in initial.items())
    assert all((ROOT/path).read_bytes() == raw for path, raw in retained.items())
    value = {'schema': 'mongotv-retired-animation-workflow-guard-proposal-v1', 'status': 'PREPARED ONLY; actual CLI/import/helper/cache ports and Root promotion pending',
             'ownerDecision': 'Root relayed explicit Pensioner de gamle Studio-workflows for both native authoring roots; keep active IDs/upload cache and regeneration sources.',
             'files': rows, 'message': MESSAGE,
             'regenerationInputsPin': {'file': regeneration_path.relative_to(ROOT).as_posix(), 'rawSHA256': sha(regeneration_raw)},
             'retainedInputsAndReceipts': regeneration['files'],
             'closure': 'No production/tool imports or subprocess callers found; README660-663 names the pipeline. Exact tool functions remain archived. Shared Blender builders and generic MCP helpers are retained untouched.',
             'missingGates': ['Actual original/candidate CLI and direct callable retirement fixtures with blocked optional/native/network boundaries.',
                              'Actual imported pure-helper before/candidate behavioral contracts, not only AST comparisons.',
                              'Actual generated old publisher cache/reuse contract with all8 durable v10 IDs and no CreateAsset upload; candidate must reject old entrypoints before client/upload setup.',
                              'Root full native cache/data inventory/archive/reopen and controlled absence/reference proofs; no huge forest deletion approval here.',
                              'Root plan, exact tool diff/README reconciliation, installed local ports, selective commit and final native parity.'],
             'nativeCalls': 0, 'productionToolWrites': 0, 'runtimeWrites': 0, 'manifestWrites': 0, 'indexWrites': 0,
             'limits': 'Only source preparation/AST syntax and exact retention proof are passed. No CLI/helper/publisher/gameplay test is credited yet. Historical bpy exporters have no safe import workflow; imports are intentionally rejected because their old initializer exported files. No runtime clip fallback, current Motion data, asset IDs, receipts, other Blender builders or generic MCP functions are removed.'}
    save(out/'.gitattributes', b'* -text\n')
    save(out/'proposal.json', (json.dumps(value, indent=2)+'\n').encode())
    print(json.dumps({'pass': True, 'preparedTools': len(rows), 'retainedInputReceiptFiles': len(retained), 'productionWrites': 0, 'nativeCalls': 0}))


if __name__ == '__main__':
    main()
