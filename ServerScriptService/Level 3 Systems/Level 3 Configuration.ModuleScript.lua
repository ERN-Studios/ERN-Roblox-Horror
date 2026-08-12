--!strict
-- Level 3 Configuration
-- Production tuning for the abandoned 1990s mall service-space level.
-- Absolute content rule: this level has no entity, NPC, chase, hostile AI,
-- damage source, or entity compatibility marker.

local Configuration = {
	Version = 4,
	WorldName = "Level 3 Generated World",
	StateFolderName = "Level 3 State",
	RemotesFolderName = "Level 3 Remotes",
	ClientEventName = "ClientEvent",
	WorldOrigin = Vector3.new(6200, 24, 0),
	RoomHeight = 14,
	WallThickness = 1.5,
	FloorThickness = 1,
	CeilingThickness = 1,
	CorridorWidth = 14,
	DoorWidth = 6,
	DoorHeight = 8.5,
	ModuleGoal = 5,
	TextureStuds = {
		PartyCarpet = 28,
		PartyCarpetNeon = 22,
		PartyCarpetRed = 30,
		CityCarpet = 52,
		Wallpaper = 18,
		OrangeWall = 22,
		Tablecloth = 10,
	},
	Textures = {
		PartyCarpet = "rbxassetid://92795890253148",
		PartyCarpetNeon = "rbxassetid://110230144446272",
		PartyCarpetRed = "rbxassetid://108064770913201",
		CityCarpet = "rbxassetid://75635502248205",
		PastelWallpaper = "rbxassetid://96252806287644",
		OrangeWall = "rbxassetid://128270554927663",
		ConfettiTablecloth = "rbxassetid://103412925025303",
		StaffDoor = "rbxassetid://127165696221846",
		FinalExitDoor = "rbxassetid://120063024460642",
	},
	Audio = {
		FluorescentHum = "rbxassetid://92576512092725",
		HVAC = "rbxassetid://9125446543",
		DoorRattle = "rbxassetid://9118901593",
		DoorMovement = "rbxassetid://9119631915",
		ReaderBeep = "rbxassetid://9119103325",
		WaterDrip = "rbxassetid://9126193223",
		PowerDown = "rbxassetid://75561087895749",
		-- Group-owned song uploaded specifically for the synchronized Level 3 sequence.
		RoomListeningSong = "rbxassetid://140244948455675",
	},
	MusicSequence = {
		DurationSeconds = 180.035917,
		BlackoutSeconds = 30,
		PreloadLeadSeconds = 1.5,
		RoomVolume = 0.48,
		CorridorVolume = 0.045,
		RoomFadeDistance = 18,
		VolumeFadeSeconds = 1.15,
		TimelineDriftTolerance = 0.32,
	},
	Colors = {
		Cream = Color3.fromRGB(205, 192, 157),
		AgedWhite = Color3.fromRGB(218, 211, 184),
		Beige = Color3.fromRGB(174, 155, 119),
		DustyPeach = Color3.fromRGB(176, 99, 74),
		MutedOrange = Color3.fromRGB(164, 79, 43),
		OldTeal = Color3.fromRGB(57, 112, 105),
		MutedBlue = Color3.fromRGB(66, 83, 124),
		FadedGreen = Color3.fromRGB(91, 126, 83),
		Burgundy = Color3.fromRGB(92, 43, 49),
		DarkCarpet = Color3.fromRGB(18, 18, 22),
		OfficeCarpet = Color3.fromRGB(78, 68, 61),
		Concrete = Color3.fromRGB(102, 101, 91),
		Linoleum = Color3.fromRGB(147, 145, 119),
		Trim = Color3.fromRGB(74, 67, 56),
		Metal = Color3.fromRGB(70, 73, 72),
		Wood = Color3.fromRGB(103, 65, 42),
		Energon = Color3.fromRGB(66, 244, 218),
		Emergency = Color3.fromRGB(194, 48, 36),
	},
	Reader = {
		UpdateInterval = 0.10,
		MaximumRange = 650,
		AccuracyDegrees = {155, 105, 64, 36, 18, 5},
		DistanceNoise = {0.60, 0.42, 0.27, 0.15, 0.07, 0.0},
	},
	Rooms = {
		{Id="Arrival", Name="Receiving Vestibule", Kind="PartyHall", X=0, Z=0, W=62, D=46},
		{Id="StaffJunction", Name="Service Junction A", Kind="PartyHall", X=88, Z=0, W=52, D=34},
		{Id="BackOffice", Name="Vacant Leasing Office", Kind="City", X=172, Z=0, W=70, D=52},
		{Id="BreakRoom", Name="Employee Break Room", Kind="City", X=88, Z=-88, W=56, D=48, Module=true},
		{Id="UtilityWest", Name="West Party Annex", Kind="PartyHall", X=88, Z=92, W=68, D=54},
		{Id="PartySpine", Name="Party Service Gallery", Kind="PartyHall", X=266, Z=0, W=86, D=38},
		{Id="Maintenance", Name="White Celebration Room", Kind="City", X=172, Z=-88, W=64, D=58, Module=true},
		{Id="LoadingStore", Name="Orange Banquet Annex", Kind="Party", X=172, Z=92, W=82, D=62},
		{Id="PartyA", Name="Party Room 03", Kind="Party", X=266, Z=-88, W=92, D=68, Module=true},
		{Id="ChairStore", Name="White City Hall", Kind="City", X=266, Z=92, W=70, D=56},
		{Id="CentralHall", Name="Parallel Party Gallery", Kind="PartyHall", X=382, Z=0, W=66, D=42},
		{Id="CityPlay", Name="Little Streets Room", Kind="City", X=382, Z=-88, W=96, D=72, Module=true},
		{Id="Janitor", Name="Orange Function Room", Kind="Party", X=382, Z=92, W=62, D=52},
		{Id="LostFound", Name="White Atrium", Kind="City", X=492, Z=0, W=78, D=58},
		{Id="PartyB", Name="Abandoned Banquet Hall 07", Kind="Party", X=492, Z=-88, W=126, D=82},
		{Id="Records", Name="Orange Celebration Room", Kind="Party", X=492, Z=92, W=76, D=60, Module=true},
		{Id="SignalHall", Name="East Party Passage", Kind="PartyHall", X=616, Z=0, W=72, D=38},
		{Id="Exit", Name="Freight Elevator Chamber", Kind="Exit", X=706, Z=0, W=52, D=46},
	},
	Links = {
		{A="Arrival", B="StaffJunction", Door="Open"},
		{A="StaffJunction", B="BackOffice", Door="Open"},
		{A="BackOffice", B="PartySpine", Door="Open"},
		{A="PartySpine", B="CentralHall", Door="Open"},
		{A="CentralHall", B="LostFound", Door="Open"},
		{A="LostFound", B="SignalHall", Door="Open"},
		{A="SignalHall", B="Exit", Door="HiddenExit"},
		{A="StaffJunction", B="BreakRoom", Door="Open"},
		{A="BreakRoom", B="Maintenance", Door="Open"},
		{A="Maintenance", B="PartyA", Door="Open"},
		{A="PartyA", B="CityPlay", Door="Open"},
		{A="CityPlay", B="PartyB", Door="Open"},
		{A="PartyB", B="LostFound", Door="Open"},
		{A="StaffJunction", B="UtilityWest", Door="Open"},
		{A="UtilityWest", B="LoadingStore", Door="Open"},
		{A="LoadingStore", B="ChairStore", Door="Open"},
		{A="ChairStore", B="Janitor", Door="Open"},
		{A="Janitor", B="Records", Door="Open"},
		{A="Records", B="LostFound", Door="Open"},
		{A="BackOffice", B="Maintenance", Door="Open"},
		{A="BackOffice", B="LoadingStore", Door="Open"},
		{A="PartySpine", B="PartyA", Door="Open"},
		{A="PartySpine", B="ChairStore", Door="Open"},
		{A="CentralHall", B="CityPlay", Door="Open"},
		{A="CentralHall", B="Janitor", Door="Open"},
	},
}

table.freeze(Configuration.TextureStuds)
table.freeze(Configuration.Textures)
table.freeze(Configuration.Audio)
table.freeze(Configuration.MusicSequence)
table.freeze(Configuration.Colors)
table.freeze(Configuration.Reader)
for _, room in ipairs(Configuration.Rooms) do table.freeze(room) end
for _, link in ipairs(Configuration.Links) do table.freeze(link) end
table.freeze(Configuration.Rooms)
table.freeze(Configuration.Links)
table.freeze(Configuration)

return Configuration
