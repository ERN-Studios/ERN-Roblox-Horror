The revised R4 lobby remains beside the original lobby at (220, 30, -760). These changes were installed against fresh Studio Source/editor baselines, then checked in actual Solo Studio Play with ZenMeister02. Studio is authoritative; these files are downstream evidence and must not be used for a bulk Studio push.

Implemented corrections:

- Concrete, asphalt and sidewalk color, OpenGL normal and roughness maps; a subtler sidewalk joint atlas. Ten private ZenMeister02 image assets have Use permission for this experience.
- Local floor/stage fill and clearer ceiling fixtures, without changing global night lighting. Ten redundant shop lights are disabled; 77 of 87 installed emitters are enabled.
- Both furniture end piles have less regular silhouettes: 16 overlay reposes and 12 upper backing reposes. All 219 meshes, 66 end barriers and base colliders remain.
- All six doorway headers sit over their frames. Horizontal gate signs have labels and arrows on both approaches. The twelve sign viewpoints use ground eye height 35, 27 studs along the tunnel from each gate.
- All 24 existing queue stations have theme props, numbers, idle cues and live state labels. Active queues retain ten hologram bands fading upward from transparency 0.740 to 1.
- Raised DJ stage runner, readable stair nosings and speaker lighting. Two vinyls rotate at approximately 2 RPM; integral tonearms and pickups stay fixed.
- Ten shop products retain keys, art, descriptions and prices, with clearer fixed cards, labels and grouping.

Actual Play evidence is in screenshots/ and root/. Queue 121 was created through the existing UI, counted down and loaded Level 6 with a healthy character; an actual E hold at its existing return prompt returned the character to the original lobby. The stage was climbed with keyboard input, both end barriers resisted walk/jump attempts, and focusing the 20-token card opened its existing 149-Robux offer. No charged purchase was performed.

Final property probes pass 620 server checks and 604 client checks. These are property inspections, not multiplayer gameplay proof. The final bounded five-second road sample recorded p50 16.64 ms and p95 25.55 ms versus before p50 16.68 ms and p95 20.92 ms. The earlier slow after-sample is retained in root/after-performance-first-sample.json. These Solo Studio samples do not establish mobile or multiplayer performance or isolate causal performance changes.

Final actual screenshots:

- screenshots/after-road-final.jpg
- screenshots/after-stage-final.jpg
- screenshots/after-south-final.jpg
- screenshots/dj-vinyls-needles-final.jpg
- screenshots/active-queue.jpg
- screenshots/shop-focus-tokens20.jpg
- screenshots/level-6-approach-north-final.jpg is the settled final recapture. The older level-6-approach-north.jpg retains the transient blank first-frame sign artifact.

Codex used actual Claude Opus 5.5 with maximum effort for implementation advice and a fresh two-image visual review. Longer timed-out attempts remain recorded as failed attempts.

The authoritative before and after full native places were reconstructed and reopened with zero Source/editor conflicts, then copied and hash-verified under /Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-lobby-polish/{before,after}. Raw native places, transfer chunks and complete unrelated Source bodies stay outside Git. fresh-source-after/ exports exactly six task Sources and the full 229-entry hash inventory from capture 4df9e7f4-49ec-434d-abbf-d2607efa9c2a. All six final pins are in root/final-frozen-source-hashes.json.

That historical capture's strict whole-forest audit remains false: another concurrent task changed five Level 1/4 scripts and added two owner-tagged temporary QA scripts. The original ServerLobby fingerprint is unchanged and taskScopeVerified is true. The closed review permits only six-source extraction; it does not grant cleanup or publication. No concurrent work was restored, normalized away or deleted by this task.

The two temporary QA scripts were subsequently removed by their owner; the fresh 12:37:51Z read records qaCount=0 and matching Source/editor hashes for all six lobby scripts and five concurrent scripts. Publication requires a separate fresh native checkpoint and Studio success receipt. root/release-status.current.json is the current release record; root/release-status.json records resolved preinstallation blockers. A local commit, native backup or source export alone does not mean the place is published. No Git remote is configured.
