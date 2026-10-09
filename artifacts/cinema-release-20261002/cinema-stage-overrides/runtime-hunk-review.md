# Cinema runtime staging scope review

This review compares the 26 proposed Cinema runtime paths with HEAD
`59823ba9df1aa97642db65f0755f226d34be6dca`. It does not authorize or perform a
Studio write. Live foreign work remains in the working tree and Studio.

The RoundUI staging override is `RoundUI.LocalScript.lua` in this directory,
SHA256 `d49b08401768e20af59c14f40d5ad1cc30a0ad8a0823412b0302ae214b92c4ea`.
`RoundUI.cinema-only.diff` records its exact HEAD-to-candidate hunks.
`RoundUI.hunk-analysis.json` records HEAD/current/candidate source hashes.
It keeps the exact HEAD lighting region and global cancel-hint wording while
retaining only the Cinema queue choice changes outside that region.

Excluded RoundUI changes are the 81-line `revisedLobbyLighting` enclosed-night
pass inserted after HEAD line 337; its 11 added contains/restore/apply hooks in
`applyPlayerLighting` after HEAD lines 346 and 359; and the two global
`STEP OFF THE PAD TO CANCEL` replacements at HEAD lines 544 and 770. These
change the revised lobby generally and are outside the Cinema staging scope.

Included hunks are the MapPreview button at HEAD 546; touch/desktop split
submit rows at 719/805; trial/preview labels and enablement at 833; replacing
the old single submit callback with a shared mode-bearing submit inside the
existing do block at 854/873; clearing launch modes when closing at 893;
queuehost argument parsing at 4410; and countdown mode labels at 4457.

Two other staging distinctions were found:

- `JumpscareUI.LocalScript.lua` has only one added line at HEAD 137 honoring
  `ReduceCameraShake` in the shared original entity capture. Cinema's new Round
  Client already handles that preference for its own camera. Preserve this
  working-tree hunk for the Level 1 scope; exclude it from the Cinema baseline.
- Current `GameManager.Script.lua` differs from HEAD only by the 11-line
  synchronous Level 1 `ReleaseAnimations` cleanup at HEAD 646. Use the root's
  already prepared Cinema baseline (`ec0d...`), preserving the current mirror
  for the separate Level 1 commit.

The other existing-path diffs are fully Cinema: Level4V4PreviewAccess's
authorized queue launcher and live-round entry lock; Flashlight's prize refill
and Usher beam drain; NoiseReporter's reel carry speed and Level 4 noise;
Round Entry's Level 4 load acknowledgement; Level 4 Lighting's round power
states, stars and spectator ownership. Independent review also found only
Cinema hunks in DeathAdvice, UIRegression, ZyntraConfig, ZyntraRecordsPage,
NoiseRegistry, Round Completion Routing and ZyntraMonetization. Their changed
progression behavior is Level 4 clear/challenge/record support; CampaignComplete
continues to require Levels 1–3.

The eleven new paths are owned Cinema modules/assets: Usher Animations,
Level4RoundGenerator, the six Level 4 Systems modules, Level 4 Round Client,
and the cinema's two authored world scripts. No generic revised-lobby pass
was found in these sources. The preview queue registration is the minimal
existing access bridge for the Cinema trial/map choice.

Validation used the existing actual source-backed queue-choice runner against
this exact RoundUI candidate: 188 server and 31 client assertions passed,
including native mode choices, split layout, default station behavior,
countdown labels and close cleanup. Its full-file official Luau compilation
also passed. This is offline verification and adds no new gameplay claims.

Working-tree RoundUI file SHA256 remained
`ee3f3dccde026bdf1ee9448087af3a614756596b93f90e8177e10081b34ddaf9` after
preparation and tests. No index operation or canonical file modification was
performed by this reviewer. Root must inspect the final staged diff after
applying the override; the override is not a Studio deployment source.
