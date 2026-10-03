-- Release candidate: install only with the accepted rig and owned animation bundle.
return table.freeze({
	-- Rig and corridor verification flags remain mandatory in released rounds.
	Enabled = true,
	StudioValidationMode = false, -- Temporary Studio overrides must not be published.
	WalkSpeed = 10,
	NormalRunSpeed = 20,
	EnragedSpeed = 32,
	RunDistance = 100,
	Acceleration = 24,
	Deceleration = 40,
	WalkAnimationReferenceSpeed = 10.82,
	RunAnimationReferenceSpeed = 27.6,
	AttackWindup = .5, -- reviewed single-strike clip contact marker
	AttackRecovery = .7, -- complete 1.2-second clip before resuming movement
	AttackCooldown = 2.4,
	AttackDamage = 100,
	AttackArcDegrees = 140,
})
