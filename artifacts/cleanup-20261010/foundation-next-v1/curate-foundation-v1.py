"""Pin completed foundation evidence only; no native, production, index or commit writes."""
from pathlib import Path
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUTPUT = HERE / 'CURATION-v1.json'
MARKDOWN = HERE / 'CURATION-v1.md'
assert not OUTPUT.exists() and not MARKDOWN.exists(), 'Preserve prior curation'
SHA = lambda raw: hashlib.sha256(raw).hexdigest()

patterns = {
    'private-key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
    'github-token': re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})'),
    'openai-token': re.compile(rb'\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}'),
    'aws-access-id': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'roblox-cookie': re.compile(rb'_\|WARNING:-DO-NOT-SHARE-THIS\.'),
    'credential-url': re.compile(rb'https?://[^\s"\'<>/:]+:[^\s"\'<>/@]+@'),
    'literal-auth': re.compile(rb'(?i)\b(?:authorization|bearer|api[_-]?key|password|secret|token)\b\s*[:=]\s*["\'][A-Za-z0-9_./+\-=]{16,}["\']'),
}
included, excluded, findings = [], [], []
for path in sorted(HERE.rglob('*')):
    if not path.is_file(): continue
    assert not path.is_symlink(), 'No symlink evidence'
    relative = path.relative_to(HERE)
    label = path.relative_to(ROOT).as_posix()
    raw = path.read_bytes()
    row = {'path': label, 'bytes': len(raw), 'sha256': SHA(raw)}
    if any(part in {'__pycache__', '.cache', 'scratch', '.scratch'} for part in relative.parts) or path.suffix in {'.pyc', '.pyo'}:
        row['reason'] = 'cache/scratch; no evidence value'
        excluded.append(row); continue
    # No generated artifact is excluded merely because it failed. The 35k
    # generated V2 Luau fixture has an actual execution/compile receipt.
    assert len(raw) < 1_000_000, 'Manually classify a large regenerated artifact'
    for category, pattern in patterns.items():
        for match in pattern.finditer(raw):
            findings.append({'path': label, 'category': category,
                             'line': raw[:match.start()].count(b'\n')+1,
                             'matchedBytesSHA256': SHA(match.group()), 'value': 'redacted'})
    row['group'] = 'current-v5-candidate' if relative.parts[0] == 'installer-v5' else (
        'immutable-version-or-failure-history' if relative.parts[0].startswith('installer-v') or 'failed' in relative.name or 'candidate' in relative.name else 'foundation-review/baseline/peer-evidence')
    included.append(row)

assert not findings, 'Secret scan found a candidate; values were not printed'
production = (ROOT/'tools/install_new_scripts.py').read_bytes()
assert SHA(production) == '4e9e6177f602f6b1519e682b70e661cec13928aec7ce3e608365163b3285292f'
frozen = json.loads((HERE/'installer-v5/frozen-pins-v1.json').read_bytes())
for label, pin in frozen['files'].items():
    raw = (HERE/'installer-v5'/label).read_bytes()
    assert (len(raw), SHA(raw)) == (pin['bytes'], pin['sha256']), label
for label, pin in frozen['preservedFailureReceipts'].items():
    raw = (ROOT/label).read_bytes()
    assert (len(raw), SHA(raw)) == (pin['bytes'], pin['sha256']), label

value = {'schema': 'completed-foundation-curation-v1', 'candidateStatus': 'pending native authoring/transport; no promotion',
    'productionInstallerUnchangedSHA256': SHA(production), 'nativeCalls': 0, 'productionWrites': 0,
    'indexWrites': 0, 'commitWrites': 0, 'files': included, 'excluded': excluded,
    'secretScan': {'patterns': sorted(patterns), 'filesScanned': len(included), 'bytesScanned': sum(r['bytes'] for r in included), 'findings': findings,
        'scope': 'Static recognizable credential/private-key/cookie/literal-auth patterns, no runtime environment or private config reads. Not a universal proof against encoded/unknown secrets.'},
    'preservedFailures': frozen['preservedFailureReceipts'], 'v5FrozenPinsSHA256': SHA((HERE/'installer-v5/frozen-pins-v1.json').read_bytes()),
    'limits': 'Exact explicit review/stage paths only; do not git add -A or promote candidate. Prior failed/version files retained, .gitattributes preserves raw bytes. Curation outputs are new evidence; they are not self-pinned.'}
with OUTPUT.open('xb') as stream: stream.write((json.dumps(value, indent=2)+'\n').encode())
text = ('# Completed foundation evidence curation\n\n'
        + f'{len(included)} exact paths / {sum(r["bytes"] for r in included)} bytes are pinned in `CURATION-v1.json`. '
        + f'{len(excluded)} cache/scratch files are excluded; no failure/version receipt was omitted.\n\n'
        + 'The V5 installer is a pending candidate. Native authoring/editor/large-write transport remain unverified. '
        + 'All earlier candidates, negative receipts, replay drivers, pinned helper copies, .gitattributes, review, native plan and concrete diff are included. '
        + 'The generated 35k V2 Luau fixture is retained because it has actual execution/compile evidence.\n\n'
        + 'The static secret scan found zero candidates across seven credential/private-key/cookie/literal-auth patterns. '
        + 'Only these selected artifacts were scanned; no runtime credentials or private configuration were read. '
        + 'This does not prove absence of encoded or unknown secret formats. No credential value is printed.\n\n'
        + 'Root should compare every path/hash immediately before explicit staging, inspect the exact staged diff, '
        + 'and commit these as prepared evidence. Do not include excluded caches, stage unrelated work, or promote production tools from this curation.\n\n'
        + 'CURATION-v1.json SHA256: `' + SHA(OUTPUT.read_bytes()) + '`.\n')
with MARKDOWN.open('xb') as stream: stream.write(text.encode())
print(json.dumps({'pass': True, 'files': len(included), 'bytes': sum(r['bytes'] for r in included), 'excluded': len(excluded), 'secretFindings': len(findings), 'curationSHA256': SHA(OUTPUT.read_bytes()), 'markdownSHA256': SHA(MARKDOWN.read_bytes())}))
