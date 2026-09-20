# Owner-requested balance and UI changes — 2026-09-20

Published to place 131311258779917 / universe 10559217407 as **v1939** at 14:37:24 UTC. Studio reports PublishSuccessful and Place published. No live server restart requested or performed.

## Changes

- LaverSneglen, officially resolved to user ID **9488575949**, has permanent server-authorized in-experience Advanced Equipment entitlement. This does not transfer Roblox marketplace pass ownership or grant other passes.
- Advanced Equipment owners receive **+50% base stamina capacity**, additive to existing upgrade levels. Existing one-time stamina/battery grants are preserved and not repeated. Derived capacity refreshes on ownership refresh even when an old owner already received the grant. Product copy and profile percentage include the bonus. Studio LaverSneglen showed **1.55×**, including the old +5% upgrade.
- Level 1 generates **ceil(round participants / 2)** paired fuseboxes/levers: 1–2 → 1, 3–4 → 2, 5–6 → 3. The count freezes at round start; lobby users do not count. Each accepted lever pull latches permanently until round reset. Removed timeout reset, timed synchronization and death-triggered clutch logic. HUD and objective guide show no time limit.
- The obsolete five-second recorded briefing sentence about the ten-second deadline is muted while its corrected caption remains visible. The rest of the recording is unchanged; no replacement voice was generated.
- The Level 1 spotted scream now uses the actual target's existing server-issued alert serial and plays locally under SoundService. Removed the global workspace-triggered and direct-CHASE fallback playback. Volume is **0.96**, down 20% from 1.20. The positional chase loop is **1.105**, up exactly 30% from 0.85. Other entities and ambient audio are unchanged.
- Team objective feed is centered at the top, with bold centered 20px desktop / 17px touch text, up to 620px width and wrapping. Touch retains only the newest entry; desktop can show three.

## Evidence and limits

- `behavior-checks.luau` executes extracted production logic with isolated mocks: **53 assertions passed**, covering owner/non-owner/explicit grant, repeated capacity application without re-awarding levels, 1–6-player scaling excluding a lobby player, rejected/duplicate lever pulls, permanent progress, and warning eligibility.
- Native Studio Play: LaverSneglen's entitlement is true and stamina multiplier 1.55. A global spotting signal plus CHASE produced zero warnings; the local player's alert serial produced one SoundService warning at 0.9599999785 (Roblox float representation of 0.96).
- Native visual inspection: larger top-center feed on desktop, iPhone 17 Pro landscape and portrait, and iPad Pro M5 (13in), including long usernames. Game orientation is Sensor; feed uses CoreUISafeInsets. No observed clipping. Device simulation stopped and Play stopped afterwards.
- Eight changed runtime scripts compile. All **147 Studio scripts** match local UTF-8 bytes, djb2 hashes and editor buffers. `source-inventory.json` records the fresh check.
- The only console error during checks was a temporary AssistantCommand attempting to use nil `script`; the probe was corrected. A volume probe initially used exact float equality and was corrected to a tolerance. Neither error occurred in a game script.
- Full multiplayer rounds, real paid purchases, live entitlement rejoin and a new audio recording were not exercised. The new entitlement is applied by published server code when the player joins a server running v1939.

## Records

`balance-20260920.rbxl` is the full native Edit backup immediately before publication. Source edits used complete expected-Source/editor comparisons and fresh readbacks; Studio remained authoritative. This release also records the owner's verified manual v1938 publication of the preceding Expedition Pack artwork.

Trello: https://trello.com/c/DR1Isx73 (Level 1/audio), https://trello.com/c/n1yx5OdQ (Advanced Equipment), https://trello.com/c/FAgRQho1 (feed), https://trello.com/c/eigEDZAH (prior texture).
