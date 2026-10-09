Level 4 loading investigation, 2026-10-10. The owner requested all work offline
while another session uses Studio. No Play action, Studio write, publication or
new backup belongs to this investigation. A native read-only capture preceded
that restriction; all subsequent review uses that frozen capture and local files.

The capture's 11 relevant Source/editor pairs agreed and matched normalized HEAD
`5a3a06e7`. The Cinema original was present in ServerStorage, with 14,464
descendants and its Collision model's 1,634 children. GameManager, Round Entry
Client, Level 4 Round Client, RoundUI and Lobby Loading Screen were enabled in
the earlier read-only metadata observation. These are capture-time facts,
not proof of the state after another session's later edits.

No specific cause of the owner's failure has been established. Level4RoundGenerator,
LevelWorldStorage, QueueBridge and Round Entry Client are unchanged from the
previously tested lazy-loading change. Later GameManager changes concern
spectator focus. LightDirector's later enabled-state metadata adds no startup wait.
An optimization receipt also records an active Level 4 client with a hidden
loading frame and a real Cinema.Collision floor; this is counterevidence to an
unconditional entry failure, not a reproduction of the reported problem.

| Conditional gate | Evidence to collect during a natural failure |
| --- | --- |
| Generator/system failure | Server LoadStage/WORLD_ERROR and the actual exception; Cinema parent and WorldGenerated |
| Streaming/persistence | Server eligible InRound roster and persistent collision membership; matching client's Cinema presence and entry floor ray |
| Client readiness | Client UI/control flags, game-loaded state and local readiness token; server/client tokens are separate observations |
| Visual asset fetch | Non-success nearby asset IDs and the real `[RoundEntry] could not fetch nearby visual` warnings |
| Shared party timeout | Each actual participant, RoundLoadingDeadline and RoundLoadingError; one missing acknowledgement holds the whole party |

The loading runtime gives the entire attempt 60 seconds, including generation,
character placement and every participant's readiness. The entry client requires
real successful asset callbacks and a collidable floor. It tries each carrier
at most twice. A failed or unreported asset, missing UI/control readiness, or
missing floor can therefore prevent release. These are conditional paths, not
observed causes. The later lobby warm worker can overlap one outstanding engine
request with entry, but source review cannot establish contention or starvation.
The changed global streaming radius/behavior is also a test variable, not an
established explanation. No timeout extension or readiness bypass was prepared.

`observe_loading.py` generates passive Luau for Server or Client. It does not
connect to Studio. It reuses the existing read-only Cinema observer and extracts
only asset discovery from an explicit captured Round Entry source. The client
reads ContentProvider status without warming assets, records a 14-stud entry
floor ray, and bounds its asset census to four seconds/30,000 descendants with
cooperative yields. Door scans and the older observer's geometry census are
removed before generation. It creates no instances/connections and writes no native
attributes, Source, Parents, character state or readiness acknowledgements.
The client asset census runs only while its initial snapshot selects Level 4.

After the owner explicitly releases the test slot, reread current Studio sources
and resolve Source/editor differences before relying on the old capture. Start
a fresh normal Play session, enter through the ordinary public Level 4 queue,
and collect paired Server/Client snapshots during the failure and near the
deadline, plus the actual console warnings. Do not preload assets diagnostically
before the first natural attempt. Capture local UI/control flags on the Client;
their absence on the Server does not establish a failure. A stale preview flag
is worth recording because it excludes the player from collision persistence.

Example offline generation:

```powershell
python artifacts/level4-loading-20261010/observe_loading.py server
python artifacts/level4-loading-20261010/observe_loading.py client --source <fresh-source-file>
```

The snapshot does not observe the entry client's private AssetsReady field,
advertised spawn position, callbacks or pending carrier attempts. Asset fetch
status alone cannot prove callback receipt, renderer readiness or an entry
acknowledgement. The floor ray records geometry beneath the current root; it
does not prove the root is within 16 studs of the advertised spawn. A census
with `assetCensusIncomplete` or a changed character/level is partial evidence.
Descendant-list construction happens before per-item checks; the cooperative
budget cannot cap an individual engine call. Late descendants may arrive after
enumeration, so a complete census describes the observed instances only.
Loading token, state and deadline are also recorded at both ends; a changed
attempt is marked rather than interpreted as one stable observation. The
reused observer rejects duplicate authored paths with an explicit error.
Offline compilation and source review are not gameplay, published-client,
cold-cache, mobile, multiplayer or performance verification.

Local verification: both generated modes compiled with the installed Luau CLI.
The existing actual-source Level 4 lifecycle suite passed 130 checks and rejected
10 deliberate lifecycle mutations. The entry batch suite passed 124 callback,
retry, cancellation and cleanup checks. `offline-checks.json` records source
identities and the limits of these results. No reported loading failure was
reproduced, and no game fix has been installed or published by this investigation.
