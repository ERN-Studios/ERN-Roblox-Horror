# Published Roblox Player check — 24 September 2026

At about 17:27–17:31 UTC, Roblox Player entered `BACKROOMS: STAY QUIET [CO-OP HORROR]` on the existing developer account. Roblox's version-history API had reported v2083 as the latest published version immediately before this session. The Player UI did not expose the actual running server's place version, so these observations are **published-client behavior**, not proof of a specific server binary.

- The returning-account lobby showed no `LEVEL 1 START HERE`, Field Notes or lobby `TRY AGAIN` guide in the visible view. The first-clear Rewards intro was present and dismissible. Fresh first login and death→lobby remain untested.
- The wheel displayed six sectors: 1 Token 40%, 3 Tokens 20%, Speed Potion 20%, Entity Shield 10%, 2 Speed Potions 5%, and Skin or 3 Tokens 5%. Its X closed the panel. This session did not spin, collect or test UTC rollover.
- The SKINS catalog loaded standing portraits for Baseline Yellow, Pool Service, Suburb Survey, Blacksite Director, Static Wraith and False Sun. The Baseline, Pool Service and Suburb Survey rotating 3D previews showed arms down. The Static Wraith and False Sun thumbnails appeared blank for about two seconds while loading, then rendered normally; this was not a permanent failure.
- **New visual defect:** the separate developer-only Signal Architect catalog portrait is still in a T-pose. [Full Player screenshot](skins-dev-portrait.png). No purchase, equip, two-client visibility or physical touch test was performed.

This does not close the Testing cards that require fresh accounts, purchase/rejoin, multiplayer, physical devices, DataStore persistence or listening. The owner authorized Player-only computer control for this check; Studio was not operated through its UI.

The Signal Architect defect was subsequently addressed in **unpublished Studio Edit**: the group-approved standing Image `139302197163453` is now `ZyntraSkins.SignalArchitect.PreviewImageId`, using the same catalogue presentation as the six ordinary skins. The Player screenshot above remains valid evidence for the published state before that change. A new published Player view is needed to verify the correction.
