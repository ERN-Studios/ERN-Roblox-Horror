-- DeathAdvice -- what actually killed you, and the one thing that would have
-- kept you alive. (Trello: "forstaaelig foerste doed", "Entity-regler".)
--
-- THE RULE THIS FILE EXISTS TO ENFORCE: the death card may never invent an
-- explanation. Every line below was read out of the code that does the killing,
-- and the file:line it came from is written next to it. If a mechanic changes,
-- this copy is wrong and has to change with it -- which is why all of it lives
-- in ONE file rather than being spread over five controllers and a HUD.
--
-- HOW IT TRAVELS. The server marks the player immediately before the
-- authoritative kill:
--
--     DeathAdvice.Mark(player, "L2Foam")
--     humanoid.Health = 0
--
-- Mark writes two REPLICATED player attributes, LastDeathCause (a key from the
-- table below) and LastDeathCauseAt (workspace:GetServerTimeNow()). GameManager's
-- hum.Died handler calls Take, which returns the key only if the mark is younger
-- than FreshSeconds and clears it either way, and appends the key to the
-- existing "death" (and, on a wipe, "partydown") RoundStatus payload.
--
-- WHY A FRESHNESS WINDOW: a mark that is never consumed -- a kill site that
-- fired but whose Health write was refused, a protected character -- must not
-- be inherited by an unrelated death minutes later. An old or missing mark is
-- Unknown, and Unknown shows a truthful "signal lost" line with NO tip. A
-- made-up tip is worse than no tip.
--
-- The window is measured on workspace:GetServerTimeNow(), the same clock every
-- other player-visible timer here uses, so the mark and its reader agree even
-- if they ever run in different scripts' os.clock domains.

local DeathAdvice = {}

DeathAdvice.Unknown = "Unknown"
DeathAdvice.FreshSeconds = 3
DeathAdvice.CauseAttribute = "LastDeathCause"
DeathAdvice.TimeAttribute = "LastDeathCauseAt"

-- Copy limits, enforced by tools/tests/test_death_advice.py. The title is a HUD
-- label (upper case, one line on a phone); the cause and the tip are one short
-- sentence each and wrap to at most two lines in the death card.
DeathAdvice.TitleLimit = 22
DeathAdvice.CauseLimit = 72
DeathAdvice.TipLimit = 72

DeathAdvice.Causes = {
	-- EntityKill.Script.lua:193. Contact with the Level 1 entity; the capture is
	-- cinematic but the health write is unconditional once it starts.
	-- WHY THIS TIP: EntityAI.Script.lua:200 chases at 27.2 studs/s and a sprint
	-- is 26, so running away in a straight line cannot work. Its noise intake
	-- (EntityAI.Script.lua:56-73) only hears walk/sprint above 2 studs/s.
	L1Entity = {
		Title = "THE ENTITY CAUGHT YOU",
		Cause = "It reached you in the maze.",
		Tip = "Break line of sight and stay quiet; it is faster than your sprint.",
	},
	-- MazeGenerator.Script.lua:668 and :689 -- both Health writes in that file
	-- are the pit-zone bottoms, the second one after a protection window expires.
	-- WHY THIS TIP: PIT_HOLE is 12 studs with PIT_GAP 1 stud of beam between
	-- them (MazeGenerator.Script.lua:66-67), so a pit field is crossable on foot.
	L1Pit = {
		Title = "YOU FELL",
		Cause = "You dropped through a pit field.",
		Tip = "Cross a pit field on the narrow beams between the holes.",
	},
	-- Level 2 Pool Foam Controller.ModuleScript.lua:913.
	-- WHY THIS TIP: instantKill returns early unless entity.ChaseTriggered
	-- (:865), and triggerChase (:937) latches on a server-validated LOOK. The
	-- phase gate on the same function (:868) is why contact before the lethal
	-- pump does nothing, so "hunting" is the honest word for the cause.
	L2Foam = {
		Title = "POOL FOAM GOT YOU",
		Cause = "Pool foam reached you while it was hunting.",
		Tip = "Looking at one starts its hunt, so look away and keep moving.",
	},
	-- Level 2 Pool Slide Controller.ModuleScript.lua:639.
	-- WHY THIS TIP: attackReach (:592-594) re-tests the 140-degree
	-- AttackArcDegrees against the facing the windup froze, and its own comment
	-- says circling behind a visible swing avoids the hit. The windup is .5 s.
	L2Slide = {
		Title = "THE SLIDE STRUCK",
		Cause = "The pool slide landed its swing.",
		Tip = "Step behind it during the windup; its swing is locked forward.",
	},
	-- Level 3 Mall Manager AI Controller.ModuleScript.lua:2424.
	-- WHY THIS TIP: a hidden player is reached through a table check --
	-- beginTableCheck (:2266) publishes a reaction window of
	-- TableCheck.ReactionWindowSeconds (2 s) that the Table Hiding Client counts
	-- down under "SOMETHING IS LOOKING UNDER THE TABLE", and leaving inside it is
	-- the whole mechanic.
	L3Manager = {
		Title = "THE MANAGER FOUND YOU",
		Cause = "The Mall Manager reached you.",
		Tip = "Hide under a table, and leave it the moment it kneels to look.",
	},
	-- Everything nothing marked: a void fall, a failed arrival placement
	-- (GameManager.Script.lua:913), or a kill site added without a mark. It says
	-- so and offers NOTHING, because there is nothing true to offer.
	Unknown = {
		Title = "SIGNAL LOST",
		Cause = "Your signal cut out before the cause was logged.",
		Tip = "",
	},
}

-- The copy for a key, never nil: an unknown or missing key reads as Unknown so
-- no caller has to carry a fallback. Clients call this; it touches no state.
function DeathAdvice.Copy(key)
	local advice = type(key) == "string" and DeathAdvice.Causes[key] or nil
	return advice or DeathAdvice.Causes[DeathAdvice.Unknown]
end

function DeathAdvice.IsKnown(key)
	return type(key) == "string" and DeathAdvice.Causes[key] ~= nil
		and key ~= DeathAdvice.Unknown
end

-- SERVER. Called on the line before the authoritative kill. Returns false and
-- writes nothing for an unknown key, so a typo at a kill site degrades to
-- "SIGNAL LOST" instead of printing a confident lie; it never throws, because a
-- kill site is the worst place in the game to raise an error.
function DeathAdvice.Mark(player, key)
	if not player then return false end
	if not DeathAdvice.IsKnown(key) then return false end
	player:SetAttribute(DeathAdvice.CauseAttribute, key)
	player:SetAttribute(DeathAdvice.TimeAttribute, workspace:GetServerTimeNow())
	return true
end

function DeathAdvice.Clear(player)
	if not player then return end
	player:SetAttribute(DeathAdvice.CauseAttribute, nil)
	player:SetAttribute(DeathAdvice.TimeAttribute, nil)
end

-- SERVER. Read and consume. Always returns a key -- Unknown when the mark is
-- missing, malformed or older than FreshSeconds -- and always clears, so one
-- mark can never explain two deaths.
function DeathAdvice.Take(player)
	if not player then return DeathAdvice.Unknown end
	local key = player:GetAttribute(DeathAdvice.CauseAttribute)
	local at = player:GetAttribute(DeathAdvice.TimeAttribute)
	DeathAdvice.Clear(player)
	if not DeathAdvice.IsKnown(key) or type(at) ~= "number" then return DeathAdvice.Unknown end
	local age = workspace:GetServerTimeNow() - at
	if age < 0 or age > DeathAdvice.FreshSeconds then return DeathAdvice.Unknown end
	return key
end

return DeathAdvice
