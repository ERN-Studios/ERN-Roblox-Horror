-- ZyntraConfig
-- Central product catalogue and balance values. IDs map to products created
-- under the BACKROOMS: STAY QUIET [CO-OP HORROR] experience in Creator Dashboard.

local TokenPercentPerLevel = 0.05
local PCT = ("+%d%%"):format(math.floor(TokenPercentPerLevel * 100 + 0.5))

return {
	DataStoreName = "ZyntraPlayerData_v1",
	SupportLeaderboardDataStoreName = "ZyntraDonationLeaderboard_v2",
	SupportLeaderboardSize = 10,
	SupportLeaderboardRefreshSeconds = 90,
	TokenPercentPerLevel = TokenPercentPerLevel,
	LevelCompletionTokens = 1,

	Studio = {
		GrantAllPasses = true,
		StartingTokens = 25,
	},

	Passes = {
		Supporter = {
			Id = 1941938256,
			-- The previous asset was hazmat-themed and did not represent Supporter.
			-- Keep it retired until an approved replacement exists; the client renders
			-- this neutral Zyntra monogram instead of inventing or uploading artwork.
			IconId = 0,
			IconText = "Z//S",
			Name = "Zyntra Supporter",
			Price = 99,
			TokenGrant = 10,
			Description = "Receive 10 Research Tokens once and unlock a permanent ZYNTRA SUPPORTER tag.",
		},
		AdvancedEquipment = {
			Id = 1945402536,
			IconId = 82752249741977,
			Name = "Advanced Equipment",
			Price = 149,
			Description = "Permanently unlock the hazmat color picker and receive one " .. PCT .. " upgrade to both Stamina Capacity and Battery Capacity.",
		},
		CosmeticEquipment = {
			Id = 1946086261,
			IconId = 96817218792472,
			Name = "Glowstick Customizer",
			Price = 99,
			Description = "Permanently unlock the glowstick color picker for every glowstick you deploy. Cosmetic only.",
		},
	},

	Products = {
		Tokens4 = {
			Id = 3707755089,
			IconId = 122080898819162,
			Name = "4 Research Tokens",
			Price = 49,
			TokenGrant = 4,
			Description = "Adds 4 Research Tokens to your account. Spend each token on a permanent " .. PCT .. " upgrade to either Stamina Capacity or Battery Capacity.",
		},
		Tokens20 = {
			Id = 3707755233,
			IconId = 85350713730800,
			Name = "20 Research Tokens",
			Price = 149,
			TokenGrant = 20,
			Description = "Adds 20 Research Tokens to your account. Spend each token on a permanent " .. PCT .. " upgrade to either Stamina Capacity or Battery Capacity.",
		},
		EmergencyReentry = {
			Id = 3707755318,
			IconId = 105488216694656,
			Name = "Emergency Re-entry",
			Price = 29,
			ReentryGrant = 1,
			Description = "Adds 1 stored Emergency Re-entry credit. After dying during an active run, use it to rejoin once that round.",
		},
	},

	-- Optional, repeatable donations with no gameplay grant. Keep these separate
	-- from utility Developer Products so only intentional donations reach the
	-- global leaderboard. All six products belong to this experience; any future
	-- entry with a zero ID remains visibly disabled in the client.
	Donations = {
		DonationSignal = {
			Id = 3710116814,
			Order = 1,
			Name = "ZYNTRA Donate — Signal",
			Price = 10,
			Description = "Donate to the continued development of BACKROOMS: STAY QUIET [CO-OP HORROR].",
		},
		DonationSupply = {
			Id = 3710116945,
			Order = 2,
			Name = "ZYNTRA Donate — Supply",
			Price = 50,
			Description = "Donate to the continued development of BACKROOMS: STAY QUIET [CO-OP HORROR].",
		},
		DonationField = {
			Id = 3710117017,
			Order = 3,
			Name = "ZYNTRA Donate — Field",
			Price = 100,
			Description = "Donate to the continued development of BACKROOMS: STAY QUIET [CO-OP HORROR].",
		},
		DonationResearch = {
			Id = 3710117070,
			Order = 4,
			Name = "ZYNTRA Donate — Research",
			Price = 250,
			Description = "Donate to the continued development of BACKROOMS: STAY QUIET [CO-OP HORROR].",
		},
		DonationCommand = {
			Id = 3710117099,
			Order = 5,
			Name = "ZYNTRA Donate — Command",
			Price = 500,
			Description = "Donate to the continued development of BACKROOMS: STAY QUIET [CO-OP HORROR].",
		},
		DonationDirector = {
			Id = 3710117136,
			Order = 6,
			Name = "ZYNTRA Donate — Director",
			Price = 1000,
			Description = "Donate to the continued development of BACKROOMS: STAY QUIET [CO-OP HORROR].",
		},
	},

	-- Roblox badges, created on the Creator Dashboard under this same experience.
	-- 0 means "not created yet" and disables that award completely: no
	-- BadgeService call is made and nothing is recorded, so pasting the real id
	-- in later starts awarding it with no other change. Never invent an id here;
	-- an id that does not belong to this experience fails every award silently.
	Badges = {
		FirstClearLevel1 = 2788462628933614,
		FirstClearLevel2 = 349186155479685,
		FirstClearLevel3 = 457908347698355,
		-- Awarded the first time all three levels have been cleared at least
		-- once, which is NOT the same as clearing Level 3.
		CampaignComplete = 2318404539475574,
	},

	-- Accessibility switches, in the order a settings surface should list them.
	-- Key is BOTH the player attribute the client reads and the profile.Settings
	-- field it is saved under, so these strings must keep matching their readers
	-- exactly: ReduceCameraShake (EntityShakeController, Level 2 Pool Foam
	-- Client), ReduceFlashing (Level 2 Pool Foam Client, Level 3 Lighting
	-- Controller) and the two caption names (Level 2 Pool Foam Client).
	-- Default is what a profile that never touched the switch
	-- publishes -- captions are ON unless a player turns them off, everything
	-- else is off -- so a default must never be changed to the opposite of what
	-- its readers already assume.
	AccessibilitySettings = {
		{
			Key = "ReduceCameraShake",
			Label = "Reduce camera shake",
			Description = "Removes the entity's proximity tremble, chase rumble and footstep punch. Head-bob and crouch are unaffected.",
			Default = false,
		},
		{
			Key = "ReduceFlashing",
			Label = "Reduce flashing lights",
			Description = "Softens the strobing and full-screen flashes an encounter can throw at you.",
			Default = false,
		},
		{
			Key = "CaptionsEnabled",
			Label = "Show captions",
			Description = "Shows on-screen captions for sounds you would otherwise only hear.",
			Default = true,
		},
		-- The older half of the same caption pair, still read by the Pool Foam
		-- client (`DisableCaptions ~= true and CaptionsEnabled ~= false`). It is
		-- persisted and published so an existing save keeps working, but a UI
		-- that rendered both rows would contradict itself: show CaptionsEnabled
		-- and skip every entry marked Hidden.
		{
			Key = "DisableCaptions",
			Label = "Hide captions",
			Description = "Legacy switch kept for older saves. Use Show captions instead.",
			Default = false,
			Hidden = true,
		},
	},

	Colors = {
		HazmatDefault = Color3.fromRGB(210, 174, 58),
		GlowstickDefault = Color3.fromRGB(65, 145, 255),
	},
}
