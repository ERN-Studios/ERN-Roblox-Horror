-- Cleaned ElevenLabs recordings; provenance and WAV hashes are in the audio asset manifest.
--
-- LEVEL2_GROAN_OWNERSHIP_20260921: `Enabled` is also the handshake that hands the
-- Pool Slide's voice to `Level 2 Entity Audio`. While it is true AND the server
-- publishes Level2_PoolSlideActive, `Level 2 Sound Controller` holds its distant
-- pipe-groan scheduler. Set it false and the distant groans simply keep running
-- as map ambience, so the kill switch never leaves the level silent.
local Bank = {Enabled = true, Version = 2, Mix = {
	Foam = {
		Walk = {Volume = 0.25, Min = 12, Max = 110},
		Run = {Volume = 0.33, Min = 14, Max = 145},
		Idle = {Volume = 0.09, Min = 8, Max = 60},
		Groan = {Volume = 0.4, Min = 18, Max = 220},
		Squeal = {Volume = 0.32, Min = 18, Max = 220},
		Hunt = {Volume = 0.3, Min = 14, Max = 170},
		Attack = {Volume = 0.45, Min = 12, Max = 110},
	},
	Slide = {
		Walk = {Volume = 0.35, Min = 18, Max = 170},
		Run = {Volume = 0.43, Min = 22, Max = 210},
		EnragedRun = {Volume = 0.5, Min = 24, Max = 240},
		Idle = {Volume = 0.14, Min = 12, Max = 100},
		Alert = {Volume = 0.45, Min = 24, Max = 240},
		Attack = {Volume = 0.52, Min = 20, Max = 170},
		-- The periodic mouth groan sits just under Alert so the one spawn
		-- announcement stays the loudest thing the giant ever says. Same
		-- plateau/reach as Alert: direction and distance come from the rolloff.
		Mouth = {Volume = 0.42, Min = 24, Max = 240},
	},
},
Foam = {
	Walk = {{Id = "rbxassetid://109013568497721", Seconds = 8.0}, {Id = "rbxassetid://131416587047046", Seconds = 8.0}, {Id = "rbxassetid://95734756840121", Seconds = 8.0}, {Id = "rbxassetid://121923729659604", Seconds = 8.0}},
	Run = {{Id = "rbxassetid://115069228614516", Seconds = 6.0}, {Id = "rbxassetid://117917218156419", Seconds = 6.0}, {Id = "rbxassetid://83614476896362", Seconds = 6.0}},
	Idle = {{Id = "rbxassetid://132199446080885", Seconds = 6.0}, {Id = "rbxassetid://137911483000290", Seconds = 6.0}, {Id = "rbxassetid://103095013316134", Seconds = 6.0}, {Id = "rbxassetid://94611912970277", Seconds = 6.0}},
	Groan = {{Id = "rbxassetid://135741106151964", Seconds = 8.0}, {Id = "rbxassetid://135920645468915", Seconds = 8.0}, {Id = "rbxassetid://82575067339531", Seconds = 8.0}, {Id = "rbxassetid://76676509241608", Seconds = 8.0}},
	Squeal = {{Id = "rbxassetid://93264987608191", Seconds = 7.0}, {Id = "rbxassetid://137952673555654", Seconds = 7.0}, {Id = "rbxassetid://83765504502332", Seconds = 7.0}, {Id = "rbxassetid://107634849173772", Seconds = 7.0}},
	Hunt = {{Id = "rbxassetid://94640204665606", Seconds = 5.0}, {Id = "rbxassetid://79916026330555", Seconds = 5.0}, {Id = "rbxassetid://74083975196975", Seconds = 5.0}, {Id = "rbxassetid://120244886798443", Seconds = 5.0}},
	Attack = {{Id = "rbxassetid://80660979620978", Seconds = 3.0}},
},
Slide = {
	Walk = {{Id = "rbxassetid://91904848244036", Seconds = 8.0}, {Id = "rbxassetid://110107845829477", Seconds = 8.0}},
	Run = {{Id = "rbxassetid://123647296838245", Seconds = 6.0}, {Id = "rbxassetid://99062204603565", Seconds = 6.0}},
	EnragedRun = {{Id = "rbxassetid://76424104660624", Seconds = 6.0}},
	Idle = {{Id = "rbxassetid://91311095755288", Seconds = 6.0}},
	Alert = {{Id = "rbxassetid://123428540737909", Seconds = 7.0}},
	Attack = {{Id = "rbxassetid://138559499183993", Seconds = 3.0}},
	-- The periodic mouth voice reuses the four authored pipe-groan clips: they
	-- are StringValue slots in ReplicatedStorage["Level 2 Sound Library"], not
	-- ids, so they are named here and resolved on the client. The reveal is that
	-- the groans the party heard from the pipes were always this thing.
	MouthSlots = {
		"Level 2 Distant Monster-Like Pipe Groan 1",
		"Level 2 Distant Monster-Like Pipe Groan 2",
		"Level 2 Distant Monster-Like Pipe Groan 3",
		"Level 2 Distant Monster-Like Pipe Groan 4",
	},
	MouthClipSeconds = 8.0,
	-- Calibration knob for the LAST resort in the mouth lookup (see the client):
	-- a point derived from the model's own bounding box, as a fraction of it, so
	-- it scales with the rig. Only used when the template carries no mouth
	-- Attachment, no mouth/jaw/head Bone and no head/jaw MeshPart.
	MouthOffset = {Height = 0.42, Forward = 0.30},
},
}
local function freeze(value)
	for _, child in pairs(value) do if type(child) == "table" then freeze(child) end end
	table.freeze(value)
end
freeze(Bank)
return Bank
