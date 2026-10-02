"""Minimal R4 guard-first re-entry correction from fresh authoritative Edit capture."""
from pathlib import Path
import difflib, hashlib, json

out = Path('tools/level3_promotion_20261002/gameplay_boards/r4-claude-fix')
capture = json.loads((out/'fresh-capture.json').read_text())
assert capture['placeId'] == 131311258779917 and capture['universeId'] == 10559217407
assert capture['path'] == 'ServerScriptService.LobbyReimaginedPreview.Builder'
assert capture['class'] == 'ModuleScript' and capture['sourceEditorMatch']
source, editor = capture['source'], capture['editorSource']
assert source == editor
old = '''\t\tlocal center = existing:GetAttribute("PreviewCenter")
\t\tassert(typeof(center) == "Vector3", "Inspect R4 lobby center before relocating support board")
\t\tlocal transfer = supportBoardTransfer(existing, center)
\t\tlocal ok, failure = pcall(function()
\t\t\tapplySupportBoardTransfer(transfer, existing)
\t\t\trequire(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)
\t\tend)
\t\tif not ok then restoreSupportBoardTransfer(transfer); error(failure) end'''
new = '''\t\t-- Existing Level 5/6 access protection must survive board-relocation failure.
\t\trequire(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)
\t\tlocal transfer
\t\tlocal ok, failure = pcall(function()
\t\t\tlocal center = existing:GetAttribute("PreviewCenter")
\t\t\tassert(typeof(center) == "Vector3", "Inspect R4 lobby center before relocating support board")
\t\t\ttransfer = supportBoardTransfer(existing, center)
\t\t\tapplySupportBoardTransfer(transfer, existing)
\t\tend)
\t\tif not ok then
\t\t\trestoreSupportBoardTransfer(transfer)
\t\t\twarn("[LobbyReimaginedPreview] Existing support-board relocation failed: " .. tostring(failure))
\t\tend'''
assert source.count(old) == 1, 'Reconcile current live existing-model branch before drafting'
candidate = source.replace(old, new, 1)
sha = lambda s: hashlib.sha256(s.encode()).hexdigest()
baseline_file = out/'Builder.fresh.baseline.luau'
candidate_file = out/'Builder.guard-first.candidate.luau'
baseline_file.write_text(source)
candidate_file.write_text(candidate)
(out/'Builder.guard-first.diff').write_text(''.join(difflib.unified_diff(source.splitlines(True),candidate.splitlines(True),fromfile=capture['path']+' fresh Edit baseline',tofile=capture['path']+' scoped guard-first candidate')))
manifest = {
    'operation':'edit', 'placeId':capture['placeId'], 'universeId':capture['universeId'],
    'studioId':'c1e8b040-e549-408a-8a5b-7fe6905c2d55', 'datamodelType':'Edit',
    'targetPath':capture['path'], 'className':capture['class'],
    'capturedAtUTC':capture['capturedAtUTC'], 'beforeHash':sha(source),
    'beforeEditorHash':sha(editor), 'beforeSourceEditorParity':True,
    'beforeSourceBytes':len(source.encode()), 'candidateHash':sha(candidate),
    'baselinePath':str(baseline_file), 'candidatePath':str(candidate_file),
    'scope':'Existing-model Build branch only: restart authoritative guard before protected board relocation; rollback/warn retains existing lobby on transfer failure',
    'writeRequirements':'Root must recheck correct place/path/class, exact fresh Source and editor bodies inside scoped write; reread/reconcile concurrent changes. This agent has made no Studio write.',
    'reviewReceipt':'tools/level3_promotion_20261002/gameplay_boards/claude-review/long/result/receipt.json',
}
(out/'candidate-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({k:manifest[k] for k in ['capturedAtUTC','beforeHash','beforeEditorHash','candidateHash','beforeSourceBytes']}))
