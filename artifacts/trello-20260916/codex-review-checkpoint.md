# Codex independent review notes — 16 September
## Ready before integrated Studio QA
- New product textures uploaded: SpeedPotion 73457681182843; RouteMarkerPack 100856675462356. PNGs both RGB 1254 x 1254, fully opaque. See product-texture-validation.json.
- Table-hiding v2 was tested on the actual character, four-second native loop, both entrances, fallback, exit and death. See animation-native-qa.md.
- Reviewed the complete Round Exit Client diff and its GameManager request boundary: hold L / touch shares one pending request, cancellation rechecks modal/round/alive state, and release resets progress. Native key and real touch behavior still belong to integrated QA. Transport is unchanged; no expanded cross-server test is required (#16 skipped).
- Read the shop research report. Roblox monetization-foundations supports contextual product information, consistent shop UI, and an inviting browsing space. Checked the current primary page directly. Current passes docs URL is https://create.roblox.com/docs/production/monetization/passes.
- Trello reread 06:45 UTC: newest card still #102; approved open scope #74,83,84,85,88,89,100,101,102. Moved To Do cards to In Progress and replaced obsolete proposal-only statuses. #74 stays Testing. Exclusions unchanged.

## At Claude handback
Verify native integrated UI screenshots and product image loading. Compile whole Studio place via native command bar if MCP sandbox remains blocked; source audit and independent parity must match. Check that publish version is actually current (Edit PlaceVersion can lag). Save final .rbxl, focused commit and reports; pause Claude heartbeat and LEAVE THE PC ON per the owner's latest instruction.

This is a historical review checkpoint. Final verified publication is v1920; see final-release.md.
