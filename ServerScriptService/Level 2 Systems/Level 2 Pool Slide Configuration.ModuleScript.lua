-- Stage configuration: full encounter verification required before release.
return table.freeze({
	Enabled = true,
	StudioValidationMode = true, -- Studio tests only; NEVER publish this value
	WalkSpeed = 10,
	NormalRunSpeed = 20,
	EnragedSpeed = 32,
	RunDistance = 100,
	Acceleration = 24,
	Deceleration = 40,
	WalkAnimationReferenceSpeed = 8.062205314636232,
	RunAnimationReferenceSpeed = 17.367606461048128,
	AttackWindup = .5, -- reviewed single-strike clip contact marker
	AttackRecovery = .7, -- complete 1.2-second clip before resuming movement
	AttackCooldown = 2.4,
	AttackDamage = 100,
	AttackArcDegrees = 140,
})
