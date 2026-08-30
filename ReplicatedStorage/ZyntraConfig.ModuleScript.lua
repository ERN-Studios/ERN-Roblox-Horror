-- ZyntraConfig
-- Central product catalogue and balance values. IDs map to products created
-- under the BACKROOMS: STAY QUIET [CO-OP HORROR] experience in Creator Dashboard.

return {
	DataStoreName = "ZyntraPlayerData_v1",
	SupportLeaderboardDataStoreName = "ZyntraDonationLeaderboard_v2",
	SupportLeaderboardSize = 10,
	SupportLeaderboardRefreshSeconds = 90,
	TokenPercentPerLevel = 0.05,
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
			Description = "Permanently unlock the hazmat color picker and receive one +5% upgrade to both Stamina Capacity and Battery Capacity.",
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
			Description = "Adds 4 Research Tokens to your account. Spend each token on a permanent +5% upgrade to either Stamina Capacity or Battery Capacity.",
		},
		Tokens20 = {
			Id = 3707755233,
			IconId = 85350713730800,
			Name = "20 Research Tokens",
			Price = 149,
			TokenGrant = 20,
			Description = "Adds 20 Research Tokens to your account. Spend each token on a permanent +5% upgrade to either Stamina Capacity or Battery Capacity.",
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

	Colors = {
		HazmatDefault = Color3.fromRGB(210, 174, 58),
		GlowstickDefault = Color3.fromRGB(65, 145, 255),
	},
}
