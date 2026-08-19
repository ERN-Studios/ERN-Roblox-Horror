# Handoff — project-wide code audit, ready to apply to Studio

**Status: finished and pushed. 37 scripts are waiting to go into Studio, and
that step can only run from the Windows PC.**

Branch `claude/roblox-code-audit-di6qxi` · PR #1 · 8 commits · 48 files,
+2029 / −932.

---

## 1. Do this first (5 minutes, on the PC, Studio open)

```
git pull origin claude/roblox-code-audit-di6qxi
tools\apply_to_studio.cmd
```

The script checks the Studio bridge exists, refuses to run with uncommitted
changes, does a read-only classification of all 37 scripts against the live
place, and only writes after you press **Y**. If you'd rather drive it by hand:

```
python tools\push_repo_to_studio.py --audit    # reports, writes nothing
python tools\push_repo_to_studio.py            # applies
```

**Afterwards:** save the place in Studio, then commit the updated
`studio-sync-manifest.json` (the push flips those 37 entries from
`pending-studio-push` to `synced` — that's the record the two sides agree
again). Pre-push copies of every script land in `.studio-push-backups\<time>\`.

### If the audit step reports conflicts

It means Studio's copy of that script changed after the audit was taken, so the
tool refuses to overwrite it and **nothing is written at all**. Options:

- `python tools\push_repo_to_studio.py --skip-conflicts` — apply the clean
  files, leave the conflicted ones for later.
- `python tools\push_repo_to_studio.py --overwrite-conflicts` — you've looked
  and Studio's version isn't wanted; push over it (still race-safe).
- Or paste the audit output to Claude and let it work out what diverged.

**Never run `pull_source_from_studio.py` before the push lands.** The repo
copies are newer than Studio; pulling would overwrite this whole audit with the
old source. The tool now skips pending files by default, but don't `--force` it.

---

## 2. What the audit changed

Full reasoning per item is in the PR #1 description. Summary:

**Bugs that affect live rounds**
- Every Level 2/3 round was silently starting the Level 1 fuse puzzle
  server-side, stalling 15s and then erroring on the missing maze —
  `PuzzleManager` had no level guard.
- The Level 1 entity could disappear permanently: `EntityAI` unanchored it on a
  timer even with no maze under it, so it fell out of the world and later
  rounds ran with no entity. It also stacked duplicate glow lights every round.
- The Mall Manager (Level 3) called a function that doesn't exist whenever it
  got boxed in — a per-frame error.
- Roughly a dozen broken contracts between systems: the pit-shove played the
  wrong animation, fuse messages had no client handler, the re-entry shop had an
  invisible cursor, `G` both danced and dropped a glowstick mid-round, the
  Slidemouth's prop-shove and scream timing read attributes nothing ever wrote,
  and the dev "skip to blackout" button was unwired end to end.

**Cleanup** — ~700 lines removed: Level 3's retired door subsystem (builders,
runtime, tests, sounds, config), dead config keys across all three levels,
write-only attributes, `Spectating` guards nothing ever set (7 files), and
leftovers pointing at the retired `PoolroomsLevel2` world.

**Duplicate work** — the Level 3 Round Adapter's two hand-maintained ~63-entry
attribute lists became one; config values that had silently drifted from
hardcoded copies now fail loudly.

**Performance** — no visual change: Mall Manager navigation params built once
per tick instead of ~50×; spectate camera stopped rescanning the whole character
every frame; fuse relays share one workspace scan instead of 12; the red ALERT
mode stopped rewriting four properties on ~300 lights every 0.08s.

Nothing in-world was touched — no walls, props, or geometry. The two Workspace
test rigs and all `ServerStorage` backups are untouched. Every edited script
passes `luau-analyze` with zero warnings.

---

## 3. Three things waiting on your decision

Each was verified and deliberately left alone, because the right answer is a
design call, not a bug fix:

1. **Teammate flashlights render twice.** Client-side "MateBeam" head lights
   *and* FlashlightSync's replicated workspace mounts both draw every teammate's
   beam (three sources while spectating). Removing either changes how bright
   teammates look. If the replicated mounts are the intended renderer, the
   leftover half is `FlashlightController.LocalScript.lua:462-535`.
2. **Level 3 rooms get no wall art.** `ROOM_ART_COUNTS` / `BUNTING_ROOMS` are
   keyed by retired authored room ids (`PartyA`, `CityPlay`…) while the
   generator emits `L3_S1_R01`-style ids, so no kids drawings, notes, bunting or
   hero balloon ever spawn in a generated room. Corridor art still works.
   Re-keying them would add visuals to live rounds.
3. **The Slidemouth never starts.** The 1,149-line controller has a complete
   `Start`/`Stop` surface that nothing invokes. When you want it live, wire
   `SlidemouthController.Start(manifest, generation)` / `.Stop()` into the
   Level 2 Round Adapter next to Pool Foam.

Also noted: Level 3's music mix has drifted between the client constants and
`Configuration.MusicSequence` (`0.85` vs `1.15` fade, `0.85` vs `0.32` sync
tolerance). The config keys are unread, so the client values are what ships —
worth deciding which is intended.

---

## 4. Sync tooling (new in this branch)

- `tools/push_repo_to_studio.py` — repo → Studio. Two-phase: classifies
  everything first and aborts before writing if anything conflicts; stages each
  source in a ServerStorage buffer, verifies its length, then swaps it in via
  `ScriptEditorService:UpdateSourceAsync`, whose callback re-checks the baseline
  *inside* Studio so a script edited mid-push is refused rather than clobbered.
- `tools/record_pending_push.py` — queues repo-side edits for the next push.
- `tools/tests/test_push_repo_to_studio.py` — 53 assertions running the tool's
  real Luau against a stubbed DataModel, no Studio needed. Run it after any
  change to the push path.
- `CLAUDE.md` — the environment rule (Studio is only reachable from a session on
  the PC) plus the manifest/status model, so future sessions don't rediscover it.

---

## 5. Prompt to hand the local Claude

> Read CLAUDE.md and HANDOFF.md. We're on branch
> `claude/roblox-code-audit-di6qxi` with 37 scripts queued for Studio. Studio is
> open. Run `python tools/push_repo_to_studio.py --audit`, show me the
> classification, and if it's clean apply the push and report which landed. Then
> commit the updated manifest.

---

## 6. After it lands

The roadmap items from README.md are unchanged and still open: finish the Pool
Foam and Slidemouth hostiles, fill the remaining empty audio slots
(`SCREAM_SOUNDS` 1–4, `LUNGE_SOUND`, `ENTITY_STEP_RUN`, `IDLE_SOUNDS`,
`BREATHING_SOUND`, `LOBBY_FOOTSTEP_SOUND`, the Level 2 library slots, and the
Level 3 `ExitUnlocked`/`Escape` cue slots this audit added), build out Level 3,
and do the pre-publish pass on DevCheats. A playtest of Level 1 and Level 2
after the push is worth it — the entity-persistence and puzzle-guard fixes
change behaviour that only shows up across several rounds in one server.
