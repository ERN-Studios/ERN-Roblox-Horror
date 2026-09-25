# Published place v2081 — read-only verification

- Place `131311258779917`, universe `10559217407`.
- At `2026-09-24T16:32:10.9497780Z`, Roblox's place-version-history API returned version `2081` as the latest entry with `isPublished: true` and `publishStatus: 1`. Its `createdTime` is `2026-09-24T16:06:02.833Z`, creator user ID `40920547`. The prior published version `2061` has `publishStatus: 2`.
- Asset Delivery GET for this exact place/version returned a valid binary `<roblox!` RBXL of `9,617,449` bytes, SHA-256 `86f1a680f256d7a47ab26b320cd0b490613ee5452430704689b9f6e99a809cfa`.
- After decompressing the binary's 2,428 data chunks, the exact LF-normalized source bytes of **all 182** current `studio-sync-manifest.json` Lua files were found in the published RBXL (182/182). Each normalized source also matches its manifest SHA-256 (182/182). The 204,565-byte LF version of `ServerScriptService/ZyntraMonetization.Script.lua` is among them, as are Pool Slide animation IDs `100254982019982` and `80850407466977`.

Method: read-only `GET https://apis.roblox.com/place-version-history-api/v1/131311258779917/history` and `GET https://apis.roblox.com/asset-delivery-api/v1/assetId/131311258779917/version/2081`, following the returned signed Asset Delivery location without recording it. The API key and signed URL are absent from this record. The downloaded binary was inspected in memory and held only in a local Temp file, not committed.

Scope: The version history proves a successful current publication as of the check time. A version's `createdTime` is not an independently observed Publish dialog timestamp. Finding source bytes in the RBXL verifies code inclusion, not exact instance-path binding or runtime behavior. Published-server, DataStore, multiplayer, purchase, visual, audio and physical-device acceptance tests remain separate. The open Edit session's `game.PlaceVersion` reports its old loaded base `1999` and is not evidence against v2081.
