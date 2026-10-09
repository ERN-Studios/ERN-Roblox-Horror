# Pool Foam audio readiness — 9 September 2026

Read-only audit for [Trello 24sCzSO6](https://trello.com/c/24sCzSO6). No audio was generated, uploaded, inserted, published or sent to anybody. No Studio state, code or account setting was changed.

## Owner decision — 9 September 2026

The owner explicitly confirmed there is no ElevenLabs account available and instructed Codex to **skip Pool Foam sounds while the owner's friend produces them**. Status: **Afventer lydleverance fra ejerens ven; sprunget over efter ejerbeslutning 9/9**. The card remains In Progress/incomplete. It does not block the rest of this task, and no further sign-in or generation investigation is required. Retain the existing brief for the friend's delivery, then resume selection, licensing/provenance verification, group upload and integration when the files arrive. The readiness findings below are the audit history preceding this decision.

## Finding

The playback integration is present, but this audit found no delivered Pool Foam Walk/Hunt/Attack set. There is no installed ElevenLabs/SFX generation tool, project generation workflow or ElevenLabs credential in the checked locations. **Root subsequently opened ElevenLabs in the browser and observed a redirect to Sign In: there was no authenticated account available in that browser session.** Plan, credits and existing History remain unknown. Account sign-in or delivery of the agreed files is the concrete remaining access requirement; a paid plan must not be assumed from the sign-in page.

## Evidence checked

- `docs/POOL_FOAM_SFX_BRIEF_2026-09-05.md`: three sounds for all five Primary clones, Walk/Hunt 6–8 second loops and Attack 0.5–1 second one-shot. The agreed first delivery is these three sounds, not twelve assets. Brief requests 2–3 candidate takes, commercial production provenance, audition of each loop five times, then group upload and two-client verification.
- `artifacts/trello-20260909/checklists-snapshot.json`: all eight sound-production checklist items were incomplete at capture. Fresh Trello card read still reports the files/IDs missing; last activity is `2026-09-05T16:06:56.803Z`. The generic card endpoint does not expose attachments or a reliable checklist collection, so that fresh read alone is not proof of no attachments; root already reviewed board attachments in the full audit.
- File discovery used `rg --files --hidden --no-ignore` for WAV/MP3/OGG/FLAC/M4A/AIFF beneath `G:\Roblox`, excluding dependency and Git directories. Found twelve older MP3s in `G:\Roblox\MongoTV\assets\sounds` plus their corresponding vault paths in `G:\Roblox\MongoTV\Backrooms Stay Quiet\06 Assets\media\sounds`. No Pool Foam-named delivery was found. The files are ambience, breathing, death scream, elevator, entity footsteps/running/scream/idle, player running, and Level 3 CD collection; source file timestamps are July 26–28 or August 27. Existing files were not auditioned and are not certified substitutes for the authored wet foam/rubber set.
- Bounded text/file searches in project `tools`, `assets` and `docs` found the brief and planning records but no ElevenLabs SFX generation script or job metadata. Installed tool metadata contains no ElevenLabs, SFX generation or general audio-generation tool. A text-to-speech skill name elsewhere in the session is not evidence of a callable SFX integration.
- Credential **presence only** was checked: no environment variable with `ELEVEN` or `SFX` in its name existed in the current process; the project environment file discovered was `tools/discord_trello_bot/.env` and it had no `ELEVENLABS_API_KEY`, `ELEVEN_API_KEY` or `XI_API_KEY` assignment. No credential values were output. Other account stores, browser credentials, machine/user environment stores and unrelated directories were not inspected.

## Owned Roblox audio inventory

Read-only `search_asset` calls explicitly constrained `scope=group`, `groupId=1039373905`, `assetType=Audio`, `maxResults=20` to **ERN Roblox Studios**. The explicit group ID matters: the proxy's session context incorrectly/ambiguously reported creator ID `0` and type `User`, while each returned owned asset correctly attributed creator ID `1039373905`.

| Query | Result |
| --- | --- |
| `Pool` | 0 |
| `Foam` | 0 |
| `hunt` | 0 |
| `attack` | 0 |
| empty | 20 existing group-owned audio assets, mostly lobby/level speech, radio cues and Level 1 steps; no identified Pool Foam delivery |
| `level 2` | 20 group-owned environmental/player-footstep assets; no identified Pool Foam delivery |

The existing Level 2 inventory includes `Level 2 Pipe Groan` (`116707880665577`), `Level 2 Shallow Footstep 2` (`121310030007635`), drain sounds, water drop, pressure door, room tone and wading steps. Their names show nearby material, but suitability as distinct foam Walk/Hunt/Attack cues and seamless loops was not verified. They were not inserted or substituted. Queries capped at twenty are not a complete inventory enumeration, and naming searches cannot prove that no differently named delivery exists.

## Actual integration

- `ServerScriptService/Level 2 Systems/Level 2 Pool Foam Configuration.ModuleScript.lua:221`: audio enabled; positional movement volumes Walk `0.18`, Hunt `0.24`, rolloff 12–110 studs, Attack volume `0.24`. `AudioIds.Primary.Walk`, `.Hunt` and `.Attack` are all empty. Optional Idle/Caught/Collapse and Secondary are also empty. Animation ID `75270256720943` is a locomotion animation, **not an audio asset**.
- `ServerScriptService/Level 2 Systems/Level 2 Pool Foam Controller.ModuleScript.lua:283`: `updateEntityAudio` creates/reuses one `PoolFoamMovement` looping Sound per entity on a `PoolFoamAudioEmitter` Attachment. It uses InverseTapered rolloff, avoids restarting an unchanged state, switches IDs for Walk/Hunt, pauses/resumes, and cleans up. It deliberately creates no Sound while IDs are blank; an enabled configuration alone does not make the entity audible.
- The controller copies configured IDs into replicated named StringValues and sends AttackHit to the targeted player. `StarterPlayer/StarterPlayerScripts/Level 2 Pool Foam Client.LocalScript.lua:226` accepts known slots, handles the Attack one-shot locally and protects the presentation from stale/duplicate event generations/serials.
- `tools/tests/test_pool_foam_audio.py` exercises this production integration with offline stubs. Earlier project validation records 24 passes. This audit did not rerun unchanged tests or claim engine audio loading, commercial rights, mix or multiple clients were verified.
- `README.md` and the Level 2 README contain stale wider assertions about missing automated tests and other old work. Prefer current source plus dated validation records; their statement that the Pool Foam audio IDs remain empty is still confirmed by current source.

## Concrete next steps

1. Root opened [ElevenLabs Sound Effects](https://elevenlabs.io/app/sound-effects) and was redirected to Sign In. Once the relevant existing production account is signed in, inspect its plan, available credits, SFX feature status and History for existing samples. No new purchase or plan upgrade is implied; account plan and rights are still unverified.
2. If samples already exist, preserve originals and note model, production date and plan/account provenance. If they do not, use the three exact prompts from the brief with Looping on for Walk/Hunt and off for Attack, after confirming production rights. Avoid using speech generation as an SFX substitute.
3. Download candidate originals to the project, audition material/intensity and five repeated loop boundaries, check clipping, choose the three sounds, and record the selection. The agreed brief includes owner-and-Codex audition; do not claim that has happened merely because files exist.
4. Upload the selected files under ERN Roblox Studios, wait for moderation, grant experience `10559217407` access, record real IDs and insert only those three Primary fields. Then verify loading, near/far audibility, Walk/Hunt transitions, stop/cleanup and victim-only Attack with two clients. Publish through the mouse-driven workflow between fixes.

The observed next access step is sign-in to the appropriate existing production account, or delivery of the agreed files with provenance. The browser sign-in redirect establishes that this session cannot currently inspect History or generate through that account; it does not establish that the user has no account, that its plan is free or paid, or that generation is impossible elsewhere.

## Current official workflow references

The [ElevenLabs Sound Effects guide](https://elevenlabs.io/docs/eleven-creative/playground/sound-effects), read September 9, describes duration and Looping controls, four variations per web generation, and History downloads as WAV 48 kHz or MP3 44.1 kHz. Its current settings should be checked in the actual account before generation.

The [ElevenLabs commercial-use explanation](https://help.elevenlabs.io/hc/en-us/articles/13313564601361-Can-I-publish-the-content-I-generate-on-the-platform), read September 9, says paid-plan generations may be used commercially subject to the relevant terms and rights; free-plan generations and Beta Services are excluded. It also distinguishes the subscription status at generation time from later account upgrades. Account-specific compliance was not verified in this audit.
