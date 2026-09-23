# Level 2 entity audio

This package records the cleaned ElevenLabs sound integration installed in Roblox Studio on 2026-09-14.

The final bank contains 32 uploaded assets: 24 Foam variations and 8 deliberately selected Slide/Foam essentials. The other 19 generated WAVs remain in the Desktop delivery folder but were not uploaded after the owner requested a smaller set. The client provides positional idle, walk, run, hunt, corridor, alert and attack playback; it crossfades state loops and removes emitters on pause, despawn or round reset.

Runtime verification in Studio covered all 32 assets loading, Foam idle/walk/attack behavior, Foam attack during the kill-animation pause, Slide walk playback, Slide's 0.5-second attack timing, and cleanup to zero emitters/sounds after round stop. The final mirrored Studio sources live under ReplicatedStorage and StarterPlayer/StarterPlayerScripts.
