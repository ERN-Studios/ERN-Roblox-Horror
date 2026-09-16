# Actual-character Level 3 hold — complete, 06:33 UTC

Uploaded animation **119040885264927**, asset type Animation (24), creator **ERN Roblox Studios / group 1039373905**, verified through MarketplaceService. The saved Level 3 configuration uses v2. No place publication performed yet; Claude owns the remaining release work after handover.

## Native evidence

The actual StarterCharacter and folding-table meshes/textures were exported via Studio's Export Selection. The Blender scene binds all 18 real meshes to measured AnimationConstraint attachments. The v2 hold changes the gaze and draws the arms forward; no entry/exit cinematic. A temporary Play-only stage showed the real hazmat under the actual table. All temporary export/staging objects were removed or discarded by Stop.

Then a real Level 3 round was started via Station 9. The real E prompt entered hiding on a generated table (yaw approximately 5 degrees). The server-created uploaded Action track reached Length 4 and Weight 1 on the native client. `animation-native-loop.json` records **253 samples across 4.211 seconds**, all 18 mesh convex hulls:

- Minimum floor clearance **0.04127 stud**.
- Minimum tabletop-collider clearance **0.05386 stud**.
- Maximum lane |X| **1.49071**, maximum depth |Z| **2.02989** (inside the physical table and sight occluder).
- Root drift **0**, track remained playing at Weight 1, hiding stayed true.

Stopped the hold track on the real client to simulate unavailable/not-playing content. The procedural v2 fallback took over: Root position (0, -0.32759175, 0.47159758), rotation matches the authored 11.373-degree pitch; zero uploaded tracks, root anchored, hiding true.

E exit restored hiding=false, cleared the animation-id attribute, unanchored root, WalkSpeed 16, JumpPower 50, AutoRotate true. Entered again from the opposite side using E; server track Length 4, Weight 1. Death while hidden restored hiding=false, cleared id and track, unanchored root, restored movement, ProximityPromptService enabled and hiding GUI disabled.

## Source and checks

Changed only Level 3 Configuration and Level 3 Table Hiding Client. The server controller's existing load/cleanup logic is unchanged. Ordinary crouch keeps its existing pose; hidden fallback has the v2 pose and breathing. Both files compile with official Luau; the existing root-placement suite passes all 5 checks. Native loading/execution also passed.

Two independent live player clients were not run. Server-to-local-client track replication is verified, not a claim of a two-player visual test. Card #16 remains explicitly skipped by the owner.

Original v1 asset and authoring files remain as history. CSV/profile data was not touched. Studio stopped in Edit; final integrated release/publish is still pending.
