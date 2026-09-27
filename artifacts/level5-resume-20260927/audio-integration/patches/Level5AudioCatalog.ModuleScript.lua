-- Authored ElevenLabs Level 5 sounds. A zero AssetId is intentionally silent.
-- Fill only with uploaded, experience-permitted audio assets; no fallback assets.
local Catalog = {
	room_hum = {AssetId=0, Volume=.085, Looped=true, Duration=12},
	blackout_roomtone = {AssetId=0, Volume=.065, Looped=true, Duration=12},
	watcher_heartbeat = {AssetId=0, Volume=.13, Looped=true, Duration=4},
	puzzle_click = {AssetId=0, Volume=.22, Duration=.55, Cooldown=.055},
	puzzle_reject = {AssetId=0, Volume=.20, Duration=.9, Cooldown=.5},
	puzzle_unlock = {AssetId=0, Volume=.26, Duration=1.5, Spatial=true, MinDistance=5, MaxDistance=65},
	sliding_gate = {AssetId=0, Volume=.26, Duration=4, Spatial=true, MinDistance=9, MaxDistance=110},
	power_fall = {AssetId=0, Volume=.18, Duration=5},
	power_restart = {AssetId=0, Volume=.16, Duration=3},
	watcher_glass = {AssetId=0, Volume=.14, Duration=2, Spatial=true, MinDistance=5, MaxDistance=85},
	watcher_breath = {AssetId=0, Volume=.09, Duration=4, Spatial=true, MinDistance=4, MaxDistance=50},
	watcher_recede = {AssetId=0, Volume=.13, Duration=2.5, Spatial=true, MinDistance=5, MaxDistance=85},
}
for _, cue in pairs(Catalog) do table.freeze(cue) end
return table.freeze(Catalog)
