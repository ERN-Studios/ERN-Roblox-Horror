"""Actual generated parent commit/detach/throw port, no native connection."""
from pathlib import Path
import argparse
import hashlib
import json
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--version', choices=('v5', 'v6'), required=True); ap.add_argument('--receipt', type=Path, required=True)
    args = ap.parse_args(); assert not args.receipt.exists()
    here = ROOT / ('artifacts/cleanup-20261010/foundation-next-v1/installer-' + args.version)
    driver = here / 'test_candidate_v3.py'
    text = driver.read_text(encoding='utf8')
    old = 'scenario=="parent-set-commit-error" then setupFaultUsed=true;error("controlled after parenting")'
    new = '(scenario=="parent-set-commit-error" or scenario=="parent-set-commit-detach-error") then setupFaultUsed=true;if scenario=="parent-set-commit-detach-error" then object.Parent=nil end;error("controlled after parenting and optional foreign detach")'
    assert text.count(old) == 1; text = text.replace(old, new)
    old = '"post-source","post-attribute","cleanup-destroy-error"} do'
    new = '"post-source","post-attribute","cleanup-destroy-error","parent-set-commit-detach-error"} do'
    assert text.count(old) == 1; text = text.replace(old, new)
    old = 'elseif scenario=="detached-own"'
    new = 'elseif scenario=="detached-own" or scenario=="parent-set-commit-detach-error"'
    assert text.count(old) == 1; text = text.replace(old, new)
    if args.version == 'v6':
        # A returned before-set error and commit/detach/error have the same
        # observable nil Parent. Once attachment is attempted, retain nil.
        text = text.replace('or scenario=="parent-set-before-error" or scenario=="parent-set-commit-error" then', 'or scenario=="parent-set-commit-error" then')
        text = text.replace('or scenario=="parent-set-commit-detach-error" then', 'or scenario=="parent-set-commit-detach-error" or scenario=="parent-set-before-error" then')
    namespace = {'__file__': str(driver), '__name__': 'combined_parent_probe'}
    exec(compile(text, str(driver), 'exec'), namespace)
    error = None; result = None
    try:
        result = namespace['execute_native_matrix']('ServerScriptService.CombinedParentProbe', namespace['legacy'].NEW, True)
    except AssertionError as caught:
        error = str(caught)
    expected = (args.version == 'v6')
    assert (error is None) is expected, 'Unexpected combined fault verdict'
    if not expected: assert 'preserve foreign detach even without Source mutation' in error
    raw = (here/'tools/install_new_scripts.py').read_bytes()
    value = {'schema': 'actual-generated-parent-commit-detach-fault-v1', 'version': args.version, 'gatePassed': error is None, 'expectedVerdictConfirmed': True,
        'candidateSHA256': hashlib.sha256(raw).hexdigest(), 'testSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'baseDriverSHA256': hashlib.sha256(driver.read_bytes()).hexdigest(),
        'inMemoryPortSHA256': hashlib.sha256(text.encode()).hexdigest(), 'result': result, 'error': error, 'nativeCalls': 0, 'productionWrites': 0,
        'limits': 'Actual generated create payload/callback with explicit native/hash/JSON/property-setter fault boundary. No real Studio object or scheduler certificate.'}
    with args.receipt.open('xb') as stream: stream.write((json.dumps(value, indent=2)+'\n').encode())
    print(json.dumps({'version': args.version, 'gatePassed': error is None, 'expectedVerdictConfirmed': True}))


if __name__ == '__main__': main()
