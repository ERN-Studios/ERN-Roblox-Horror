# Next task — Level 2 audio pilot

Owner: `Main RBLX GAME DEV` (Claude), currently paused. It retains Studio ownership.
Optional helper: one Codex gpt-6.1-sol Medium/Standard job for file inventory and audio QC only.
No automatic readers/review teams, no helper Studio calls and no further subagents.

Goal: reconcile the existing Level 2 files and choose 3–5 representative sounds.
Then move that small selection through upload, scoped installation and listening before extending the package.

Start at `/Users/zeanjuul4/Projects/stayquiet-poolrooms-audio-20261009`, branch `codex/poolrooms-audio-20261009`.
Check git status and exact live Studio/audio-plan baselines; do not infer installation from filenames.

Existing material to reconcile:

- `assets/poolrooms-audio-20261009/`: older plan, QC, recipes, provenance, sound IDs and upload receipt.
- `assets/poolrooms-audio-20261010/plan.design.json`: newer untracked design, not evidence of installation.
- `tools/poolrooms_audio_20261010/`: untracked make_plan.py, upload.py and install.py.
- `StarterPlayer/StarterPlayerScripts/Level 2 Poolrooms Ambience.LocalScript.lua`: mirrored client; read the live source before editing.
- Check the paused session's saved mastering/generation outputs and job paths; do not regenerate a whole pack by default.

Confirmed context: the 2026-10-10 work produced additional recordings/mastering, but the paused owner's report said those new sounds were not uploaded, installed or heard. Earlier 2026-10-09 receipts are a different batch. Reconcile these separately.
The owner wants the first section's waves at a very low level, quieter wading steps, no quiet AI static and no audible abrupt cutoff.

Deliverables/checks:

1. Save a file inventory with hashes, provenance, section assignment, QC status and any missing source path.
2. Select 3–5 examples covering a bed, a random sound and different relevant sections; justify each briefly.
3. Check clipping, noise/static, fades, loop seam and intended runtime gain. Listen before uploading.
4. Studio owner uploads only this pilot; preserve owner/permissions and record asset receipts/IDs.
5. Install against fresh source/plan baselines with existing safe sync and full readback.
6. Hear the pilot in representative gameplay and inspect client/server logs, loading and sound state.
7. Save evidence and a scoped commit; publish verified game changes under the existing policy.
8. Expand only after the pilot's listening/mixing result is acceptable. Report missing checks exactly.

This is a saved next-task order. The setup optimisation does not start the audio task.
