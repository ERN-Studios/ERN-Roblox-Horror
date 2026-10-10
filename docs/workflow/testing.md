# Relevant verification, 2026-10-10

Read client and server Output/logs early, then measure the behaviour behind the bug.
Run focused checks and state which environment actually supplied the evidence.
Setup-only changes do not require gameplay tests or beta/security changes.

| Check | Environment/evidence | Limits |
| --- | --- | --- |
| Source/installer | Luau compile, relevant offline checks, exact scoped diff | Does not prove runtime behaviour |
| Solo gameplay | Studio Test, client/server Output, player view | Does not prove party interactions |
| Local multiplayer | Studio Server & Clients; start with two clients | Roblox supports up to eight; bound resource use on this 8 GB Mac |
| Mobile layout/input | Installed Device Simulator or existing ForceTouchUI fallback | New Device Simulator is beta; do not enable/restart current Studio for setup alone |
| Physical device | Phone/tablet in Roblox client | Needed for actual FPS, memory, thermal, touch and sound claims |
| DataStore | Separate published test experience/universe with test data and Studio API access | Another place in production universe is not isolated; API access exposes the same stores |
| MemoryStore | Studio test data is isolated from production | Does not prove the real teleport journey |
| Teleports/reserved travel | Published experience in Roblox client; departure, arrival, roster, return, CONTINUE | DevLiveLevelServer is a simulation, not real cross-server verification |
| Sound quality | Audio QC plus listening in representative gameplay | Statistics do not prove sound quality, seams or mixing |

Restore temporary flags and muted groups. The leaderboard deliberately does not write from Studio.
Mute a SoundGroup for silent logic tests; forcing Sound.Volume=0 breaks volume-driven state.
Preserve AGENTS.md's Level 2 spawn/pump/performance checks where the live mechanics apply.
Keep publication and party isolation policy, and disclose unrun real-client checks.

Official sources checked:

- [Testing modes](https://create.roblox.com/docs/studio/testing-modes)
- [Device Simulator](https://create.roblox.com/docs/studio/device-simulator)
- [Test on hardware](https://create.roblox.com/docs/performance-optimization/test-on-hardware)
- [Data stores](https://create.roblox.com/docs/cloud-services/data-stores)
- [Memory stores](https://create.roblox.com/docs/cloud-services/memory-stores)
- [Teleport between places](https://create.roblox.com/docs/projects/teleport)

These supersede old blanket claims that DataStore, multiplayer or MemoryStore cannot be tested in Studio.
