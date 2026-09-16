-- ZyntraFieldNotes -- the whole Field Notes collection, as data. (Trello #85/#88)
--
-- WHY A SHARED MODULE AND NOT A SERVER TABLE. Three readers need the same
-- twelve rows and none of them may disagree: ZyntraInventory's "DiscoverNote"
-- picks the next unowned id on a level, the reading card in
-- StarterPlayerScripts."Field Notes Client" renders the body it was told to,
-- and the terminal's NOTES page draws all twelve whether or not they are
-- owned. A server-only table would force the two clients to be sent the text
-- with every grant and would leave the undiscovered half of the page with
-- nothing to draw an outline around.
--
-- NOTHING HERE YIELDS AND NOTHING HERE READS THE GAME. It is a literal table,
-- so `require` is safe from any context, including a client that is mid-round.
--
-- THE CONTRACT THE OTHER FILES DEPEND ON:
--   * `Notes` is sorted by `Id` and every `Id` is unique. DiscoverNote grants
--     the FIRST unowned note of the level, so this order IS the drop order.
--   * `Id` is "L<level>-<two digits>" and is what the profile persists. Once a
--     save exists, an id may never be renamed or recycled -- a renamed id turns
--     into an unrecoverable hole in somebody's collection. Add new notes with
--     new ids at the end of their level's block and raise `Total`.
--   * `Level` matches the id's own level, 1..3.
--   * `Total` is #Notes, stated rather than counted so a reader can compare the
--     two and notice a partial copy.
--
-- THE TEXT IS ORIGINAL FICTION about the Zyntra facility. Deliberately no
-- dates, no real organisations and no real people: a four-digit year in a
-- readable memo reads as a claim about the real world, and this collection is
-- not making any. Numbers inside a body are spelled out for the same reason.
-- Bodies sit at 35-60 words -- long enough to have a turn in them, short enough
-- to read on a phone card without scrolling.

local L1 = {
	{
		Id = "L1-01",
		Level = 1,
		Title = "CIRCUIT COLOUR ORDER",
		Stamp = "ZX-114 / FORM 7",
		Body = "Maintenance will paint every lever cable to match its box. Red to red. "
			.. "Blue to blue. Crews who guessed the pairing last quarter left two corridors "
			.. "dark for eleven shifts. The colours are not decoration. Follow the cable on "
			.. "the floor, not the number on the plate.",
	},
	{
		Id = "L1-02",
		Level = 1,
		Title = "RELAY EXTRACTION NOTICE",
		Stamp = "ZX-114 / SAFETY 22",
		Body = "Pulling a fuse from a wall relay is loud. It is loud in the corridor, and it "
			.. "is loud three corridors over. Staff are asked to extract in pairs: one hand "
			.. "on the cabinet, one pair of eyes on the junction behind you. Do not extract "
			.. "alone after the amber lamps cluster.",
	},
	{
		Id = "L1-03",
		Level = 1,
		Title = "PIT ROOM ACCESS",
		Stamp = "ZX-114 / FORM 31",
		Body = "The open shafts on sublevel storage are not a fault. They were cut for cable "
			.. "runs and never capped. Walk the beams, not the gaps. If something calls from "
			.. "the edge, it is calling because the edge is where you fall from. Report loose "
			.. "tiles to floor maintenance.",
	},
	{
		Id = "L1-04",
		Level = 1,
		Title = "LOST AND FOUND SLIP",
		Stamp = "ZX-114 / SLIP 9",
		Body = "Handed in at the service elevator this week: one brown loafer, a lanyard with "
			.. "the photo scratched off, a cold mug of tea, and a maintenance poster for a "
			.. "circuit list nobody on this floor recognises. Claim at the desk. The desk has "
			.. "not been staffed for some time.",
	},
}

local L2 = {
	{
		Id = "L2-01",
		Level = 2,
		Title = "PUMP STATION START ORDER",
		Stamp = "ZX-207 / FORM 4",
		Body = "Three stations drain the corridors between you and the grand hall. Start them "
			.. "in any order you like; the doors will not unseal until all three run. The "
			.. "second station arms the water. After that, the leisure floor is no longer a "
			.. "leisure floor. Wade, do not swim.",
	},
	{
		Id = "L2-02",
		Level = 2,
		Title = "SKYLIGHT GLAZING LOG",
		Stamp = "ZX-207 / LOG 58",
		Body = "Replaced eleven panes above the west halls. The glass throws no shadow, which "
			.. "the day crew find restful and the night crew find otherwise. Note for the "
			.. "record: the sun above this roof has not moved since the survey. We have "
			.. "stopped writing it in the weather column.",
	},
	{
		Id = "L2-03",
		Level = 2,
		Title = "KIDS WING INVENTORY",
		Stamp = "ZX-207 / STOCK 12",
		Body = "Counted this morning: three hundred and seventy pit balls, nine rings, four "
			.. "rafts, a crate of noodles. Counted again at close: three hundred and seventy "
			.. "pit balls. The count is correct both times and the pit is a different shape. "
			.. "Reorder foam. Do not reorder the pit.",
	},
	{
		Id = "L2-04",
		Level = 2,
		Title = "FLUME SAFETY NOTICE",
		Stamp = "ZX-207 / SAFETY 3",
		Body = "Riders must exit at the catwalk. The east helix recycles: reach the bottom of "
			.. "the drum and it will hand you back a full turn above it, carrying your speed. "
			.. "There is no end to that ride. Leave through the opening you are shown, and "
			.. "leave quickly.",
	},
}

local L3 = {
	{
		Id = "L3-01",
		Level = 3,
		Title = "PARTY ROOM BOOKING",
		Stamp = "ZX-330 / FORM 18",
		Body = "Room bookings close when the lights do. Guests are asked to remain under the "
			.. "tables during the dark portion of the programme and to keep both hands inside "
			.. "the cloth. Two guests fit per table. A third will be seen. Streamers and "
			.. "balloons are provided at no charge.",
	},
	{
		Id = "L3-02",
		Level = 3,
		Title = "DISC PLAYER SERVICE LOG",
		Stamp = "ZX-330 / LOG 41",
		Body = "Five slots. Five discs. The unit will not play a partial set, and the hall "
			.. "will not open for a partial set either. Discs go missing between shifts. The "
			.. "note stands: a dropped disc is still a disc, and it is still on the floor "
			.. "where it fell. Go and collect it.",
	},
	{
		Id = "L3-03",
		Level = 3,
		Title = "STAFF NOTICE: THE MANAGER",
		Stamp = "ZX-330 / SAFETY 15",
		Body = "The floor manager keeps its own rounds and does not take instruction from the "
			.. "desk. It hears a door before it sees one. It checks tables. When it stops at "
			.. "a table it will wait two seconds, and two seconds is all the warning the "
			.. "cloth gives you. Be elsewhere.",
	},
	{
		Id = "L3-04",
		Level = 3,
		Title = "CAFETERIA STOCK COUNT",
		Stamp = "ZX-330 / STOCK 6",
		Body = "Sheet cake, eight. Paper cups, two hundred. Candles, one box, unopened. "
			.. "Nobody has ordered cake since the floor closed and the cake is fresh. Kitchen "
			.. "staff are reminded not to eat the stock and not to ask the kitchen where the "
			.. "stock comes from. Count again on Friday.",
	},
}

local Notes = {}
for _, block in ipairs({L1, L2, L3}) do
	for _, note in ipairs(block) do
		table.insert(Notes, note)
	end
end

return {
	Notes = Notes,
	-- Keyed by the LEVEL NUMBER, not by a string: every caller has the number in
	-- hand (workspace's SelectedLevel, the prop's own level, the page's group
	-- header) and a string key would make three of them stringify it first.
	ByLevel = {[1] = L1, [2] = L2, [3] = L3},
	Total = 12,
	-- One place to ask "is this a level this collection covers?", so the service
	-- and the page cannot disagree about it.
	Levels = {1, 2, 3},
}
