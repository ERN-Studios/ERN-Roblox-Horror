# Level 6 experience API and image delivery observation

Read-only Creator Dashboard check, 2026-10-01 00:32 UTC. The signed-in account
is LaverSneglen viewing the exact group-owned experience
`10559217407` (`ERN Roblox Studios`, group `1039373905`) at
`https://create.roblox.com/dashboard/creations/experiences/10559217407/configure`.
Under **Content settings → APIs**, **Enable Mesh / Image APIs** is checked
(`Value: 1`) and disabled in this account's UI. The page says ID verification
is required to access the API. No setting was changed; Save Changes remained
disabled. This establishes the displayed stored setting, not production API
behavior.

The underlying group Image IDs `98621799303808` (`carpet_city__color`) and
`131879734824108` (`props__color`) open in Creator Dashboard with the correct
name, group context (`activeTab=Image&groupId=1039373905`), Restricted selected,
Open Use off, and recognizable texture thumbnails. The city carpet preview
loads from `tr.rbxcdn.com` as a 150×150 WebP thumbnail; it is a preview rather
than a full-resolution asset delivery or game-render proof.

The legacy `https://www.roblox.com/asset/?id=98621799303808` route returned a
Roblox 404 in the authenticated browser. Browser access to the documented
`https://assetdelivery.roblox.com/v2/assetId/98621799303808` endpoint was
blocked by the browser client, and the web reader could not access it. Neither
result establishes whether the game can load the image. The root agent's fresh
Studio Play client render and Output check remain the decisive gate.

Roblox documents the
[asset-delivery endpoint](https://create.roblox.com/docs/cloud/reference/domains/assetdelivery)
and [asset moderation](https://create.roblox.com/docs/projects/assets).
