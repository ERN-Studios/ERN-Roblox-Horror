from pathlib import Path

root = Path(__file__).resolve().parents[2]
path = root / 'ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua'
text = path.read_text(encoding='utf-8')
text = text.replace('{ z = -5.7, title = "LUMEN KIT", subtitle = "FIELD LIGHT // MK II", accent = cyan }', '{ z = -5.7, title = "SPEED POTION", subtitle = "FIELD SUPPLY // TOKENS", accent = cyan }')
text = text.replace('{ z = 0, title = "SIGNAL KIT", subtitle = "TEAM COMMS // SYNC", accent = amber }', '{ z = 0, title = "ROUTE MARKERS", subtitle = "TEAM DIRECTIONS // TOKENS", accent = amber }')
start = text.index('\t-- Physical product silhouettes.\n\tlocal flashlightBody')
end = text.index('\tlocal recoveryCase = shopPart(', start)
text = text[:start] + '\t-- The first two bays receive the real token-product crates and inspect\n\t-- interactions from LobbyShopDisplay. Recovery keeps its existing silhouette.\n' + text[end:]
text = text.replace('\t-- Recessed merchandise bays use recognizable field gear instead of colored\n\t-- blocks. The displays are deliberately non-interactive; the real purchase\n\t-- entry point remains the single audited terminal below.', '\t-- Recessed supply bays share the existing audited purchase paths.\n\t-- LobbyShopDisplay adds interactive Speed Potion and Route Marker crates.')
path.write_text(text, encoding='utf-8')
