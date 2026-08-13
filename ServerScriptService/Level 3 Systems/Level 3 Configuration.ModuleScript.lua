--!strict
-- Level 3 Configuration
-- Production tuning for the abandoned 1990s mall service-space level.
-- Absolute content rule: this level has no entity, NPC, chase, hostile AI,
-- damage source, or entity compatibility marker.

local Configuration = {
	Version = 8,
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
		KidsDrawingsAtlas = "rbxassetid://96115479373798",
		KidsNotesAtlas = "rbxassetid://88220592162381",
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
		{Id="Arrival", Name="Receiving Vestibule", Kind="PartyHall", Decor="SparseWelcome", X=0, Z=0, W=70, D=52, H=12.5},
		{Id="StaffJunction", Name="Service Junction A", Kind="PartyHall", Decor="EmptyTransition", X=100, Z=0, W=56, D=36, H=11.5},
		{Id="BackOffice", Name="Vacant Leasing Office", Kind="City", Decor="KidsCafeteria", X=195, Z=0, W=78, D=48, H=12},
		{Id="BreakRoom", Name="Employee Break Room", Kind="City", Decor="ForgottenPair", X=100, Z=-105, W=60, D=50, H=10.5, Module=true},
		{Id="UtilityWest", Name="West Party Annex", Kind="PartyHall", Decor="DanceFloor", X=100, Z=105, W=80, D=70, H=16},
		{Id="PartySpine", Name="Party Service Gallery", Kind="PartyHall", Decor="SparseGallery", X=300, Z=0, W=98, D=40, H=13},
		{Id="Maintenance", Name="White Celebration Room", Kind="City", Decor="WhiteClassroom", X=195, Z=-105, W=68, D=64, H=11},
		{Id="LoadingStore", Name="Orange Banquet Annex", Kind="Party", Decor="BanquetRows", X=195, Z=105, W=94, D=74, H=15, Module=true},
		{Id="PartyA", Name="Party Room 03", Kind="Party", Decor="BirthdayCenter", X=300, Z=-105, W=108, D=78, H=16},
		{Id="ChairStore", Name="White City Hall", Kind="City", Decor="CityCafe", X=300, Z=105, W=76, D=60, H=12.5},
		{Id="CentralHall", Name="Parallel Party Gallery", Kind="PartyHall", Decor="SparseGallery", X=440, Z=0, W=76, D=44, H=12},
		{Id="CityPlay", Name="Little Streets Room", Kind="City", Decor="KidsCluster", X=440, Z=-105, W=112, D=84, H=15, Module=true},
		{Id="Janitor", Name="Orange Function Room", Kind="Party", Decor="AfterParty", X=440, Z=105, W=66, D=50, H=11.5},
		{Id="LostFound", Name="White Atrium", Kind="City", Decor="WhiteAtrium", X=570, Z=0, W=88, D=62, H=16},
		{Id="PartyB", Name="Abandoned Banquet Hall 07", Kind="Party", Decor="GrandBanquet", X=570, Z=-105, W=148, D=96, H=18, Module=true},
		{Id="Records", Name="Orange Celebration Room", Kind="Party", Decor="AbandonedCelebration", X=570, Z=105, W=84, D=70, H=14, Module=true},
		{Id="SignalHall", Name="East Party Passage", Kind="PartyHall", Decor="EmptyTransition", X=710, Z=0, W=78, D=40, H=11.5},
		{Id="Exit", Name="Freight Elevator Chamber", Kind="Exit", Decor="Exit", X=820, Z=0, W=58, D=52, H=14},
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
