# Corrections before a live patch

These proposals use offline source and historical Level3 exports. Studio authentication and fresh Source/editor/property export remain required before deployment.

- Runtime uses ServerStorage.Level6BlenderSource.AtlasJSON/AtlasPixels and generates static TextureContent. Change only the verified1024 RGBA pixel payload; no upload or ID swap is needed. Preserve all49 mesh payloads and UV/layout metadata.
- Native main floor proxies have exact names: Level 6 Room Floor and Level 6 Corridor Floor. Final candidates use exact name and Part class checks, replacing the Claude area heuristic. Preserve physical repeat and material/collision/navigation state; compare existing texture IDs and StudsPerTile against fresh original Level3.
- Default walls should be orange, City/CityPlay beige/wallpaper, RedParty/RedCelebration red, OrangeBlackParty/OrangeParty orange. Final adapter candidate prioritizes Exit and explicit wallpaper, then aliases, consistent with the offline native builder. Verify against its fresh source.
- ServiceVariant denotes an18x24 pocket, not the whole birthday room. Keep all existing service pockets. Final RoomDressing candidate retains FloorService only for MaintenanceWorkshop. BudgetArcade and PartySupplyStore keep main carpet without removing any partition or props. Historical Maintenance/Janitor IDs are ordinary renamed birthday rooms. No Kitchen variant currently identified offline.
- Palette recommendations are per-key pixels, with no global saturation shader. Skip optional new chair/balloon meshes, slot renames or extra palette slots.36 entries already occupy the grid.
- Preserve existing lamp placement/night control/CD ESP logic. No corresponding modules are edited by these candidates.
- Lighting/performance/visual parity were not tested by these offline reviews.
