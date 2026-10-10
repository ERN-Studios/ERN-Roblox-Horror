# Level 2 audio — state after 2026-10-10, and what is owed

Owner: `Main RBLX GAME DEV` (Claude), Studio owner. The pilot order that stood here (3–5 sounds first) was replaced by
the owner the same evening: "Færdiggør følgende punkter" — the whole pack was to go in. It did.

## What is in Studio

- `ReplicatedStorage.Level2Poolrooms`: plan `poolrooms-audio-20261010-v3`, 65 Sound templates (9 from 2026-10-09 kept).
  15 beds, 6 loops, 46 one-shot rows. Built by `tools/poolrooms_audio_20261010/make_plan.py`, installed by `install.py`
  (re-runnable; refuses a `Plan.Value` it does not know).
- Client `Level 2 Poolrooms Ambience` (`AUDIO_SECTIONS_20261010`), pushed and recorded in the manifest.
- Own bed: A1, P1, P2, A4, A2, P4, A5, P5, A6, EXIT. Shared: S, P0 and P3 on `bed_service`, A3 on `bed_hall`
  (nobody else uses it now).
- **`bed_p0_stairwell` was removed on the owner's order the same night**, after they heard it ("den konstante lyd når
  man er på vej ned af trappen ... skal så meget fucking fjernes nu"): a buzzing tube-light and extractor-fan bed.
  It is commented out in `make_plan.py`; its template stays in the bank unused. Lesson for the other beds: a harsh,
  buzzing, constant source is what the owner will not have. Expect the same verdict on `bed_p5_doors` (transformer
  hum with a nasal edge) and `bed_a6_atrium` (lamp buzz) until they have been heard and kept.
- Left out, with reason: `bed_a3_nave`, `bed_p3_vent`, `bed_s_desert` failed the high-band floor gate (the "no AI
  static" check) in three ElevenLabs passes, 11 takes each; `shot_a1_stir`, `shot_a1_tile`, `shot_p_hangers` failed QC.
  Do not force them through: write a different source for those three sections instead (not wind/vent noise, which is
  what the gate cannot tell from hiss).

## Evidence

- Offline: `python3 tools/tests/test_poolrooms_audio.py --luau-dir <luau binaries>` → 24 PASS, one of them the shipped
  plan walked through the real client.
- Studio play, solo, muted through a SoundGroup: every section S…A6 reported its bed, loaded sounds, own one-shots,
  `Level2PoolroomsAudioSkipped` empty. Scripts: `~/Projects/stayquiet-session-tools/l2audio/{goto.lua,read.lua,walk.py}`.

## Owed

1. **Nobody has listened to any of it.** Numbers passed; ears have not. The owner's earlier wishes still stand: first
   section's waves very low, quieter wading steps, no quiet static, no abrupt cutoff. First thing to do with sound on.
2. Phone speaker and a second player: untested.
3. Three sections without a bed of their own (above).

Raw takes, mastering tool and job logs: `/Users/zeanjuul4/Projects/stayquiet-l2-codex/audio` (outside the repo, 16
third-pass takes included). Masters, QC, recipes, provenance and ids: `assets/poolrooms-audio-20261010/`.
