-- ZyntraConfig
-- Central product catalogue and balance values. IDs map to products created
-- under the Backrooms: No Way Out experience in Creator Dashboard.

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
			Id = 1941938256,
			IconId = 112088662679534,
			Name = "Zyntra Supporter",
			Price = 99,
			TokenGrant = 10,
			Description = "10 Research Tokens, supporter tag and custom hazmat styling.",
		},
		AdvancedEquipment = {
			Id = 1945402536,
			IconId = 82752249741977,
			Name = "Advanced Equipment",
			Price = 149,
			Description = "+5% stamina, +5% battery and the hazmat color picker.",
		},
		CosmeticEquipment = {
			Id = 1946086261,
			IconId = 96817218792472,
			Name = "Glowstick Customizer",
			Price = 99,
			Description = "Unlocks the glowstick color picker.",
		},
	},

	Products = {
		Tokens4 = {
			Id = 3707755089,
			IconId = 122080898819162,
			Name = "4 Research Tokens",
			Price = 49,
			TokenGrant = 4,
		},
		Tokens20 = {
			Id = 3707755233,
			IconId = 85350713730800,
			Name = "20 Research Tokens",
			Price = 149,
			TokenGrant = 20,
		},
		EmergencyReentry = {
			Id = 3707755318,
			IconId = 105488216694656,
			Name = "Emergency Re-entry",
			Price = 29,
			ReentryGrant = 1,
		},
	},

	Colors = {
		HazmatDefault = Color3.fromRGB(210, 174, 58),
		GlowstickDefault = Color3.fromRGB(65, 145, 255),
	},
}
