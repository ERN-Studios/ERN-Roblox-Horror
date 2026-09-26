# Preserved concurrent Studio change

The final native export contains a concurrent change in `ServerScriptService/TunnelLobbyBuilder` (ModuleScript). Its only source difference is the owner-estimate comment and sealed-gate development percentages: Level 4/5/6 change from 60/10/5 to 90/70/30.

This is preserved downstream from authoritative Studio, **not an implementation made by the exit-eyes/outage task**. The original 192-script baseline remains unchanged. `../concurrent-preserved-sources.json` pins both source hashes and the reviewed diff hash. The mirror accepts it only when that allowlist is explicitly supplied and all hashes still match.
