# Detector artwork and sensitivity follow-up — 2026-09-20

Owner reported missing lobby artwork and late danger readings in Level 1.

- Explicitly map EntityDetector box artwork to existing verified image 134413710349950 on all six faces. Product catalogue icons now precede the shared fallback, so new products with an icon no longer receive generic artwork.
- Double MEDIUM range from 60 to 120 studs and increase HIGH from 22 to 50. Update in-game product and preview descriptions. Cooldown and four-second snapshot behavior are unchanged.
- Native Play visually confirmed the image on the lobby box. All six runtime decals use the image. With a clone of the actual stored Level 1 Entity, server sensing returns HIGH at 0/49/50, MEDIUM at 51/80/120 and LOW at 121 studs. This is a scoped distance check, not a full chase test. The initial probe found no Workspace.Entity because lobby storage removes it; the subsequent probe used the stored model and cleaned up before Stop.
- Both changed scripts compile; all 154 Studio Source/editor buffers match local hashes. No Level 2 entity behavior was modified or tested.
- Native Download a Copy dialog cannot be controlled (disabled Save and noWindowsAvailable/timeouts); owner asked to cancel it and publish. Previous v1947 full native backup remains valid for unchanged non-script data; final two source updates are mirrored here. Owner manually published v1948 at 17:40:08 UTC; publishType=1, PublishSuccessful and v1948 were verified in the Studio log. No live servers were restarted.
