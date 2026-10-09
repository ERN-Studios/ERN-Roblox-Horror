# B17 / T12 — local Obsidian credential ownership

The two vault builders no longer contain a bearer credential. Their actual
request functions lazily resolve it through `tools/vault/vault_auth.py`, first
from an explicit `MONGOTV_OBSIDIAN_MCP_TOKEN` environment override, otherwise
from the existing ignored vault plugin setting `mcpTransport.bearerToken` in
`Backrooms Stay Quiet/.obsidian/plugins/mcp-tools-istefox/data.json`.
The current plugin credential matches the private before baseline and is
compatible with the header validation. Its configuration was unchanged at the
captured gate and was never written by this batch.
No modern Codex broker credential is reused.

The endpoint remains `http://127.0.0.1:27200/mcp`. Request payloads, IDs, headers,
timeouts (300 seconds / 120 seconds), retries and response error handling are
unchanged. AST comparison against the private before sources found only the
credential-assignment removal, helper import, and header resolver call.
No credential is read during module import or the isolated dry branch.
Missing/invalid configuration and unsupported HTTP header characters fail
before Request/HTTP/retry, with bounded messages that exclude token values.

`fix_folders.py` was preserved and its import/request closure tested.
Its CLI still makes a read call even without `--apply`; it was not run.
`graph_cfg.py` was neither imported nor run. No actual builder main, vault
regeneration, Obsidian/MCP/network request, Studio action or publication was run.

## Local generated notes

Before mutation, exact copies of both sources and both ignored generated notes
were saved privately under `.git/mongotv-cleanup-20261009/vault-auth-before/`.
These credential-bearing rollback inputs must never be staged or published.
Each note had exactly one Python fence, byte-equal to its original source,
containing its only occurrence of the credential. The authorized replacement
changed only that fence to the current credential-free source. Both fences now
match current sources, the original credential occurs zero times, and all
outer bytes, links and newlines are unchanged. No helper note was created.
Outer generated metadata was retained; a future authorized regeneration can
refresh it. The ignored vault notes remain local; their safe receipts are here.

## Test port

`offline-tests-final.json`: **18 actual-module tests, zero errors/failures**.
Whole current modules execute against a synthetic repository/vault and fake
`urlopen`; only `build_vault.REPO` is redirected to isolated fixture files.
The actual dry branch is executed in that isolated module with every side
effect guarded, rather than invoking the real builder CLI.

Coverage includes config-free imports, override precedence, credential refresh,
missing/malformed/wrong-shaped configuration, blank and invalid header values,
BOM input, IO/encoding failures, no credential-bearing error text, both actual
request contracts, transport retry success/exhaustion, RPC/tool errors, the
`fix_folders` shared request, and generated tool notes excluding runtime tokens.
All five audited Python files passed AST and compile checks, and the source
files remained unchanged during the tests.

Reproduce the offline gate from the repository root:

```powershell
python -B tools/vault/test_vault_auth.py
# Optional NEW receipt; existing evidence is never overwritten:
python -B tools/vault/test_vault_auth.py --receipt path/to/new-receipt.json
```

`offline-review-proof.json` records exact before/after source and note hashes,
AST scope, fence/outside-byte checks, configuration preservation, final source
hashes and the final test receipt hash. It contains no credential values.

This port certifies the offline authoring boundaries. It does not certify a
live Obsidian connection. The existing credential was not rotated, and Git
history was not rewritten.

Independent review reran all18 actual-module tests successfully and confirmed
the exact HEAD AST delta and local note boundaries. At21:20:29Z the ignored
plugin configuration had changed outside this batch after the captured gate;
its bearer still matched both private originals, port27200 and header checks.
This concurrent change was preserved. The separate observation receipt records
both hashes and the scope of the original unchanged-config claim.

## Exact commit allowlist

- `tools/vault/build_vault.py`
- `tools/vault/build_systems.py`
- `tools/vault/vault_auth.py`
- `tools/vault/test_vault_auth.py`
- `artifacts/cleanup-serverstorage-20261009/vault-auth/REVIEW.md`
- `artifacts/cleanup-serverstorage-20261009/vault-auth/offline-tests-final.json`
- `artifacts/cleanup-serverstorage-20261009/vault-auth/offline-review-proof.json`
- `artifacts/cleanup-serverstorage-20261009/vault-auth/independent-review-observation.json`

The earlier `offline-tests.json` is a superseded 17-test pre-hardening receipt;
it is not part of this allowlist. Do not stage the plugin configuration,
private before checkpoints, ignored vault notes, caches or unrelated files.
