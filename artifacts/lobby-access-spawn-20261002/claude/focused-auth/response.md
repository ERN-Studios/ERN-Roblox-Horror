**Shown path is consistent (inference; nothing tested):** regular users fail CreateParty, JoinStation, countdown and QueueBridge; Zen passes if the bridge loads and `AllowsPreview` uses the same allowlist.

**Gaps:**
- **From the code:** a Level 5/6 station lacking both `revisionOwned` and `previewQueue` is ungated.
- **From the facts:** "see" is client-enforced only, so cosmetic on a modified client.
- **Not shown:** unchanged general DEV commands and campaign routing may reach Level 5/6 outside `playerInsideZone`.

**Play check:** in a live server, a regular account attempts create, join and Zen's countdown on both levels; confirm exclusion while Zen launches.
