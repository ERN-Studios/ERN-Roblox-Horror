-- ZyntraConfig
-- Central product catalogue and balance values. Replace every Id = 0 with the
-- matching ID from Creator Dashboard before enabling real purchases.

return {
	DataStoreName = "ZyntraPlayerData_v1",
	TokenPercentPerLevel = 0.05,
	LevelCompletionTokens = 1,

	Studio = {
		GrantAllPasses = true,
		StartingTokens = 25,
	},

	Passes = {
		Supporter = {
			Id = 0,
			Name = "Zyntra Supporter",
			Price = 99,
			TokenGrant = 10,
			Description = "10 Research Tokens, supporter tag and exclusive teal hazmat styling.",
		},
		AdvancedEquipment = {
			Id = 0,
			Name = "Advanced Equipment",
			Price = 149,
			Description = "+5% stamina, +5% battery and the hazmat color picker.",
		},
		CosmeticEquipment = {
			Id = 0,
			Name = "Cosmetic Equipment Packs",
			Price = 99,
			Description = "Unlocks the glowstick color picker.",
		},
	},

	Products = {
		Tokens4 = {
			Id = 0,
			Name = "4 Zyntra Research Tokens",
			Price = 49,
			TokenGrant = 4,
		},
		Tokens20 = {
			Id = 0,
			Name = "20 Zyntra Research Tokens",
			Price = 149,
			TokenGrant = 20,
		},
		EmergencyReentry = {
			Id = 0,
			Name = "Emergency Re-entry",
			Price = 29,
			ReentryGrant = 1,
		},
	},

	Colors = {
		HazmatDefault = Color3.fromRGB(210, 174, 58),
		HazmatSupporter = Color3.fromRGB(70, 205, 190),
		GlowstickDefault = Color3.fromRGB(65, 145, 255),
	},
}
