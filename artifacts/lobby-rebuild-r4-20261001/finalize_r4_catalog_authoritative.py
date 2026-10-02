"""Pin captured authoritative Sources and archive exact read-only review evidence.

This script never accesses Studio or deploys repository Sources. The applied R4
GameManager source remains historical; the current mirror preserves concurrent
developer changes captured from the authoritative Studio session.
"""
from pathlib import Path
import datetime
import difflib
import hashlib
import json

TASK = Path(__file__).resolve().parent
ROOT = TASK.parents[1]
SNAPSHOT = Path('/private/tmp/lobby-r4-native-after-20261001')
REVIEW = Path('/private/tmp/lobby-r4-roundui-lighting-review')
GM_APPLIED = '951c6af430bf99d9ece0caf858545d2d00e59683155067d3c5e4d398e9997f34'
GM_ACTUAL = '7e5939fabb1d98732a5bb2138eb5b0a7106e84aa5cb71ecee147ad949649ca9c'
ROUNDUI_ACTUAL = 'ea0e6f929f06cffa7b8e9ffc1b93a7ede1c6a6f8ed3cddd7ffb2acb82166db3c'

def sha(raw): return hashlib.sha256(raw).hexdigest()
def save_exact(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists(): assert path.read_bytes() == raw, str(path)
    else: path.write_bytes(raw)

def main():
    catalog_path = ROOT / 'tools/lobby_reimagined/r4_candidates/install-catalog-r4-final.json'
    catalog_raw = catalog_path.read_bytes()
    catalog = json.loads(catalog_raw)
    gate = json.loads((SNAPSHOT / 'checkpoint-install-gate.json').read_bytes())
    assert gate['verified'] is True
    rows = {r['path']: r for r in json.loads((SNAPSHOT / 'scripts.json').read_bytes())}
    gm = rows['ServerScriptService.GameManager']
    raw = gm['source'].encode()
    assert gm['class'] == 'Script' and len(raw) == 169980 and sha(raw) == GM_ACTUAL
    assert gm['editorMatch'] and gm['editorSourceSha256'] == GM_ACTUAL
    assert sha(rows['StarterPlayer.StarterPlayerScripts.RoundUI']['source'].encode()) == ROUNDUI_ACTUAL
    historical = TASK / 'review/concurrent-studio-20261002/historical-eight-source-catalog-before-authoritative-reconciliation.json'
    if not historical.exists(): save_exact(historical, catalog_raw)
    applied_path = ROOT / 'tools/lobby_reimagined/r4_candidates/ServerScriptService.GameManager.Script.candidate.luau'
    assert sha(applied_path.read_bytes()) == GM_APPLIED
    actual_relative = 'tools/lobby_reimagined/r4_candidates/ServerScriptService.GameManager.Script.authoritative-after.luau'
    save_exact(ROOT / actual_relative, raw)
    before = ROOT / 'tools/lobby_reimagined/r4_candidates/ServerScriptService.GameManager.Script.before.luau'
    diff_relative = 'tools/lobby_reimagined/r4_candidates/ServerScriptService.GameManager.Script.before-to-authoritative-after.diff'
    diff = ''.join(difflib.unified_diff(before.read_text().splitlines(keepends=True), gm['source'].splitlines(keepends=True),
        fromfile='Studio2470-before/GameManager', tofile='Studio-authoritative-final/GameManager'))
    save_exact(ROOT / diff_relative, diff.encode())
    review_dest = TASK / 'review/roundui-lighting-20261002/v6-final-review'
    filenames = ['RoundUI.v6.candidate.luau', 'RoundUI.before-to-v6.diff', 'RoundUI.v4-to-v6.diff',
        'candidate-manifest-v6.json', 'scope-receipt-v6.json', 'compile-v6.luau', 'test-v6.luau',
        'review-fragment-v6.luau', 'syntax-receipt-v6.json', 'mock-lighting-receipt-v6.json',
        'claude-lighting-v6.prompt.md', 'claude-lighting-v6.response.md', 'claude-lighting-v6.receipt.json']
    archived = []
    for filename in filenames:
        content = (REVIEW / filename).read_bytes()
        save_exact(review_dest / filename, content)
        archived.append({'file': str((review_dest / filename).relative_to(ROOT)), 'bytes': len(content), 'sha256': sha(content)})
    scope_receipt = json.loads((review_dest / 'scope-receipt-v6.json').read_bytes())
    claude = json.loads((review_dest / 'claude-lighting-v6.receipt.json').read_bytes())
    assert scope_receipt['candidateSHA256'] == ROUNDUI_ACTUAL and scope_receipt['ClaudeExactV6']['verdict'] == 'PASS FOR ACTUAL PLAY'
    assert claude['exitCode'] == 0 and claude['permissionDenials'] == [] and claude['reportedTools'] == []
    # Separate relocatable tools preserve the original executed tools/receipts.
    for filename in ('compile-v6.luau', 'test-v6.luau'):
        content = (REVIEW / filename).read_text().replace(str(REVIEW), str(review_dest))
        for receipt in ('syntax-receipt-v6.json', 'mock-lighting-receipt-v6.json'):
            content = content.replace(str(review_dest / receipt), str(review_dest / ('reproduced-' + receipt)))
        save_exact(review_dest / ('reproduce-' + filename), content.encode())
    for spec in catalog['sources']:
        observed = rows[spec['path']]
        observed_sha = sha(observed['source'].encode())
        if spec['key'] == 'game-manager':
            assert spec['afterSHA256'] in (GM_APPLIED, GM_ACTUAL)
            spec.update(candidateFile=actual_relative, candidateBytes=len(raw), afterSHA256=GM_ACTUAL,
                observedCandidateSHA256=GM_ACTUAL, sourceURLPath=None,
                appliedTaskSourceSHA256=GM_APPLIED,
                appliedTaskCandidateFile=str(applied_path.relative_to(ROOT)),
                authoritativeAfterSourceFile=actual_relative,
                concurrentDeltaDiffFile='artifacts/lobby-rebuild-r4-20261001/review/concurrent-studio-20261002/GameManager.task-to-authoritative-after.diff',
                concurrentDeveloperChangePreserved=True,
                scope='Authoritative final Studio mirror includes concurrent Level1 developer changes beyond the applied R4 task source951. Original2470 baseline and applied task951 remain historical; this mirror is not a deployment source. Root read-only peer compatibility review and actual original Level1/3 queue launches passed.')
        assert spec['afterSHA256'] == observed_sha and spec['candidateBytes'] == len(observed['source'].encode())
        assert observed['class'] == spec['class'] and observed['editorMatch'] and observed['editorSourceSha256'] == observed_sha
        spec['status'] = 'FINAL_NATIVE_AFTER_SOURCE_EDITOR_EQUAL'
        spec['authoritativeCaptureId'] = gate['captureId']
        if spec['key'] == 'level6-preview':
            spec['scope'] = spec['scope'].replace('actual final Play and native-after pending', 'actual final normal E return and full native-after Source/editor parity passed')
        if spec['key'] == 'round-ui':
            spec['scope'] = spec['scope'].replace('exact v6 Claude and final actual Play/native-after pending', 'exact v6 Claude PASS, actual final nine-property exit/Level4 handoff/natural respawn and native Source/editor parity passed')
            spec['finalReviewDirectory'] = str(review_dest.relative_to(ROOT))
            spec['actualClaudeReview'].update(verdict='PASS FOR ACTUAL PLAY', finalCandidateReviewedByClaude=True,
                reviewedSourceSHA256=ROUNDUI_ACTUAL, elapsedSeconds=claude['elapsedSeconds'],
                receiptFile=str((review_dest / 'claude-lighting-v6.receipt.json').relative_to(ROOT)),
                responseFile=str((review_dest / 'claude-lighting-v6.response.md').relative_to(ROOT)),
                scope='Actual read-only exact supplied v6 critique; no live or multiplayer execution by Claude')
    catalog['readyForHistoricalSevenSourceInstaller'] = False
    catalog['scope'] = 'Cumulative final authoritative native-after preservation catalog; not an installer or deployment baseline'
    catalog['authoritativeAfterCaptureId'] = gate['captureId']
    catalog['authoritativeAfterNativeSHA256'] = gate['nativeSHA256']
    catalog['concurrentChangesPresent'] = True
    catalog['catalogUsage'] = ('Cumulative eight-Source task preservation catalog. Historical seven-Source installer receipt remains separate; '
        'do not replay it against this cumulative catalog. GameManager authoritative7e includes separately recorded concurrent work; '
        'do not replay this catalog against Studio.')
    catalog_path.write_text(json.dumps(catalog, indent=2) + '\n')
    candidates_path = ROOT / 'tools/lobby_reimagined/r4_candidates/candidate-manifest.json'
    candidates = json.loads(candidates_path.read_bytes())
    for item in candidates:
        if item['path'] == 'ServerScriptService.GameManager':
            item.update(candidateFile=Path(actual_relative).name, afterSHA256=GM_ACTUAL, afterBytes=len(raw),
                diffFile=Path(diff_relative).name, appliedTaskSourceSHA256=GM_APPLIED,
                appliedTaskCandidateFile=applied_path.name,
                scope='Captured authoritative Studio Source/editor parity. Concurrent Level1 delta is preserved separately from applied R4 source951; original before and applied task candidate/diff retained. No Studio write by this script.')
        elif item['path'] == 'ServerScriptService.Level6PreviewAccess':
            item['scope'] = item['scope'].replace('final actual Play and fresh native-after parity pending', 'actual final normal E return and fresh native-after parity passed')
    candidates_path.write_text(json.dumps(candidates, indent=2) + '\n')
    receipt = {'schema': 'lobby-r4-authoritative-catalog-reconciliation-v1', 'verified': True,
        'createdAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'captureId': gate['captureId'],
        'nativeSHA256': gate['nativeSHA256'], 'catalogSHA256': sha(catalog_path.read_bytes()),
        'finalSourceCount': 8, 'allSourceEditorEqual': True, 'originalBeforeHashesPreserved': True,
        'gameManagerAppliedTaskSHA256': GM_APPLIED, 'gameManagerAuthoritativeSHA256': GM_ACTUAL,
        'concurrentDeveloperChangePreserved': True, 'actualClaudeExactRoundUIV6': scope_receipt['ClaudeExactV6'],
        'reviewArchiveFiles': archived, 'studioActions': False, 'commitsOrPublication': False}
    (TASK / 'review/concurrent-studio-20261002/authoritative-catalog-reconciliation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'verified': True, 'catalogSHA256': receipt['catalogSHA256'], 'sourceCount': 8, 'gameManagerSHA256': GM_ACTUAL}))

if __name__ == '__main__': main()
