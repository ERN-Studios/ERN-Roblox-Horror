# Level 2 entity audio — pending upload approval

This directory is a draft, not an installed Studio mirror. No assets have been uploaded, no Studio sources modified, and nothing published by this task.

Roblox Creator Hub requires acceptance of the Audio Upload License Agreement before the first upload. The account has 1999/2000 uploads available. The first cleaned Foam Walk take is staged in the upload form, named `Level 2 - Pool Foam - Walk - Take 01`. Approval for accepting the agreement and uploading all 51 cleaned effects was requested and is pending.

The 51 source WAV hashes were verified against cleanup version 2. The draft LocalScript compiles through Studio loadstring but has not run in a live round or played real Roblox assets.

## Planned integration

- New ReplicatedStorage ModuleScript: `Level 2 Entity Audio Bank`, built by `build_bank.py` only after every upload-plan entry has a genuine assetId.
- New StarterPlayerScripts LocalScript: `Level 2 Entity Audio` from the client draft.
- Pool Foam: Walk, Run, Idle, Attack, Hunt rasp, corridor Groan and Squeal; variation selection avoids repeating the same take when possible.
- Pool Slide: Walk, Run, EnragedRun, Idle, Alert and Attack.
- Positional emitters on the real rig roots, travel-based footsteps for anchored rigs, 10 Hz update, short movement fades, silence on pause/despawn/round reset, spectator support, bounded asset loading.
- Existing Foam IDs are blank. Leave them blank so they do not double the new sounds. Preserve its existing camera/hit feedback.
- In the fresh `Level 2 Sound Controller`, suppress legacy body-attached monster groans when the new bank is enabled and the actual Slide root is present. Preserve pre-spawn atmospheric groans, pumps and environmental audio.

## Remaining work

1. Receive agreement approval; upload cleaned WAVs under ERN Roblox Studios, record exact IDs and moderation/experience access. Never use original MP3s or fabricate IDs.
2. Finish review and install only against fresh Studio/editor baselines. Save a full native place backup first. Keep other developers’ changes intact.
3. Test real asset loading and playback, transitions/attacks, quiet stopping, spectator/round cleanup, second-pump safe spawn and third-pump same-instance escalation. Record measured CPU/memory and navigation behavior honestly.
4. Export verified sources/asset records, inspect staged diff and commit. Publish current place only after checks pass and record successful receipt.
