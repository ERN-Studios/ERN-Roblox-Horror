# Queue v6 peer review

PASS for requested source checks; live Source/editor CAS and actual Play checks still required

Read all five exact candidate files and their diffs. No Studio interaction or candidate edits were made. The final-member cancellation race, committing unwind ownership, attempted-join rollback and per-player cleanup gaps are addressed. Campaign/original routing remains scoped out.

Exact candidate SHA256 values:

- `ServerScriptService.LobbyReimaginedPreview.QueueBridge`: `1a5e14256a7725a35b0b13a6d31b6fd4ea47d14875368d46e9593fe365226e08`
- `ServerScriptService.GameManager`: `951c6af430bf99d9ece0caf858545d2d00e59683155067d3c5e4d398e9997f34`
- `ServerScriptService.Level4V4PreviewAccess`: `b4f8fe4aeada5d9eb26e2d0e538889dd7dc10d52c53e5a42f63796831f20ea40`
- `ServerScriptService.Level5PreviewAccess`: `07659b8077f3dc58869113e3371b906bbead0408edbb8d84ad21d746f7ee420f`
- `ServerScriptService.Level6PreviewAccess`: `0829dc2fed34719fde2937a51a7a18f22f7ea64aa5d89ae06cbc2bb54b193868`

The supplied five-source syntax receipt and nine mocked lifecycle tests match these exact hashes and pass. This is a source and receipt review; actual Studio Play, multiplayer streaming, Humanoid movement and publication remain unverified by this reviewer.

Registration assertions are caught, but `r3Bridge()` require is outside that pcall, so arbitrary module require failures are not fully isolated. Committing unwind intentionally waits for the trusted Runtime.Join callback to complete; an indefinitely hung callback would leave that owned station busy. Neither condition is demonstrated in the current exact sources.

Before installation, reread live Source/editor source and recheck them inside each scoped CAS write. The recorded before hashes are from the provided Studio-authoritative native-after baseline and are not permission to overwrite newer live edits.

Repository inspected at local HEAD `14cde8a`. No git remotes are configured, so current remote history could not be inspected. Unrelated dirty/untracked files were preserved.
