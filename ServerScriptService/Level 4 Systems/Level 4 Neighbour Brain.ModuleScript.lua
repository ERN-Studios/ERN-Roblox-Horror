--!strict
-- Level 4 Neighbour Brain
--
-- PURE. The whole state machine, with no Instance, no service and no clock of
-- its own: every fact it decides on arrives in one `sense` table and every
-- answer leaves in one `decision` table. The controller does all the world I/O.
--
-- That split is the point. An AI whose rules are tangled into raycasts and
-- pathfinding can only be tested by playing it, and "the Pool Slide never once
-- spawned successfully and nobody noticed for days" is what that costs. These
-- rules are asserted offline in tools/tests/test_level4_neighbour_brain.py,
-- against a fake world, at a fake clock.
--
-- The rules the brief fixes, all of them enforced HERE rather than in the
-- controller, so none of them can be lost in a refactor of the movement code:
--
--   * CHASE is never entered directly. It is only ever reached through ALERT,
--     which is the telegraphed warning, and ALERT needs a REAL detection: the
--     player in the cone, with line of sight, at close range.
--   * A player who is merely SEEN far away is a trace, not a target -- it
--     produces a SEARCH at the place they were seen, never a chase.
--   * Noise is investigated AT THE NOISE POSITION. The brain is never handed a
--     player position it did not earn through sight.
--   * Breaking line of sight ends a chase, and walking quietly ends it roughly
--     three times faster.
--   * Every state has a bounded life. Nothing can sit in INVESTIGATE or SEARCH
--     forever, and RETURN always drains back to PATROL.

local Brain = {}

Brain.Version = 1

Brain.PATROL = "PATROL"
Brain.INVESTIGATE = "INVESTIGATE"
Brain.SEARCH = "SEARCH"
Brain.ALERT = "ALERT"
Brain.CHASE = "CHASE"
Brain.RETURN = "RETURN"

Brain.States = {Brain.PATROL, Brain.INVESTIGATE, Brain.SEARCH, Brain.ALERT, Brain.CHASE, Brain.RETURN}

-- Goal kinds tell the controller WHERE to path, and they are deliberately
-- distinct from the state: SEARCH reached from a lost chase aims at a last-seen
-- position, SEARCH reached from a distant sighting aims at that sighting.
Brain.GOAL_PATROL = "Patrol"
Brain.GOAL_NOISE = "Noise"
Brain.GOAL_SIGHTING = "Sighting"
Brain.GOAL_LASTSEEN = "LastSeen"
Brain.GOAL_TARGET = "Target"
Brain.GOAL_HOME = "Home"

local function number(value: any, fallback: number): number
	local resolved = tonumber(value)
	if not resolved or resolved ~= resolved then return fallback end
	return resolved
end

-- How long broken line of sight is tolerated before a chase ends. A quiet
-- (crouched) player gets the multiplier; a sprinting one does not.
function Brain.ContactGrace(config: any, quiet: boolean?): number
	local base = number(config.LoseContactSeconds, 3.5)
	if quiet == true then return base * number(config.QuietContactMultiplier, 0.34) end
	return base
end

-- The single answer. `sense` is read-only; nothing here mutates it, so a caller
-- may reuse one table across ticks without the brain leaving state in it.
--
-- sense fields (all optional; missing means "no"):
--   Now              number, the controller's clock
--   State            current state string
--   StateSince       when the current state was entered
--   Visible          boolean: a living player is in the cone, with line of
--                    sight, and is NOT inside a safe house
--   VisibleDistance  number, studs to that player
--   VisibleUserId    number
--   Quiet            boolean: that player is moving quietly
--   ContactLostFor   number, seconds since the chase target was last seen
--   NoiseAt          number, when the freshest heard noise was made
--   HasNoise         boolean, a noise is inside its lifetime and in range
--   AtGoal           boolean, the rig has reached the goal it was given
--   LegExpired       boolean, the current goal's watchdog has run out
function Brain.Step(sense: any, config: any): any
	local now = number(sense.Now, 0)
	local state = sense.State
	if not table.find(Brain.States, state) then state = Brain.PATROL end
	local since = number(sense.StateSince, now)
	local elapsed = math.max(0, now - since)

	local detectRange = number(config.DetectRange, 42)
	local closeContact = sense.Visible == true
		and number(sense.VisibleDistance, math.huge) <= detectRange

	local function answer(nextState: string, goal: string, reason: string): any
		return {
			State = nextState,
			GoalKind = goal,
			Reason = reason,
			-- The controller draws the warning off this, and the HUD reads the
			-- published state; both are true only in ALERT.
			Telegraph = nextState == Brain.ALERT,
			Changed = nextState ~= state,
			TargetUserId = (nextState == Brain.ALERT or nextState == Brain.CHASE)
				and sense.VisibleUserId or nil,
		}
	end

	-- ALERT and CHASE are handled first because they own the frames they are
	-- in: nothing else may interrupt a telegraph, and a chase ends only on its
	-- own rule.
	if state == Brain.ALERT then
		if not closeContact then
			-- The line broke during the warning. That is the whole point of the
			-- warning: it becomes a search where they were, not a chase.
			return answer(Brain.SEARCH, Brain.GOAL_LASTSEEN, "alert lost contact")
		end
		if elapsed >= number(config.AlertSeconds, 1.1) then
			return answer(Brain.CHASE, Brain.GOAL_TARGET, "telegraph complete")
		end
		return answer(Brain.ALERT, Brain.GOAL_TARGET, "telegraphing")
	end

	if state == Brain.CHASE then
		local lost = number(sense.ContactLostFor, 0)
		if lost >= Brain.ContactGrace(config, sense.Quiet) then
			return answer(Brain.SEARCH, Brain.GOAL_LASTSEEN, "contact broken")
		end
		return answer(Brain.CHASE, Brain.GOAL_TARGET, "in contact")
	end

	-- Everything below shares one escalation ladder, in strict priority order.
	if closeContact then
		return answer(Brain.ALERT, Brain.GOAL_TARGET, "close detection")
	end
	if sense.Visible == true then
		-- Seen, but too far to be sure. A trace, not a target.
		return answer(Brain.SEARCH, Brain.GOAL_SIGHTING, "distant sighting")
	end

	if state == Brain.INVESTIGATE then
		-- A FRESHER noise re-aims the investigation; the same one does not.
		if sense.HasNoise == true and number(sense.NoiseAt, 0) > since then
			return answer(Brain.INVESTIGATE, Brain.GOAL_NOISE, "newer noise")
		end
		if sense.AtGoal == true then
			return answer(Brain.SEARCH, Brain.GOAL_LASTSEEN, "reached the noise")
		end
		if elapsed >= number(config.InvestigateSeconds, 18) or sense.LegExpired == true then
			return answer(Brain.RETURN, Brain.GOAL_HOME, "investigation timed out")
		end
		return answer(Brain.INVESTIGATE, Brain.GOAL_NOISE, "walking to the noise")
	end

	if state == Brain.SEARCH then
		if sense.HasNoise == true and number(sense.NoiseAt, 0) > since then
			return answer(Brain.INVESTIGATE, Brain.GOAL_NOISE, "noise during search")
		end
		if elapsed >= number(config.SearchSeconds, 14) then
			return answer(Brain.RETURN, Brain.GOAL_HOME, "search exhausted")
		end
		return answer(Brain.SEARCH, Brain.GOAL_LASTSEEN, "searching")
	end

	if state == Brain.RETURN then
		if sense.HasNoise == true then
			return answer(Brain.INVESTIGATE, Brain.GOAL_NOISE, "noise on the way back")
		end
		if sense.AtGoal == true or sense.LegExpired == true then
			return answer(Brain.PATROL, Brain.GOAL_PATROL, "home")
		end
		return answer(Brain.RETURN, Brain.GOAL_HOME, "returning")
	end

	-- PATROL, and the recovery path for any state the controller does not know.
	if sense.HasNoise == true then
		return answer(Brain.INVESTIGATE, Brain.GOAL_NOISE, "heard something")
	end
	if sense.AtGoal == true or sense.LegExpired == true then
		-- A fresh patrol leg. Same state, new goal -- the controller picks the
		-- next node; the brain only says that it is time for one.
		local decision = answer(Brain.PATROL, Brain.GOAL_PATROL, "next patrol leg")
		decision.NewGoal = true
		return decision
	end
	return answer(Brain.PATROL, Brain.GOAL_PATROL, "patrolling")
end

return Brain
