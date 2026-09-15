--!strict
-- Card #86 probe: read the recorder back. Summarises in Luau so the execute_luau
-- result stays small; set TAIL to pull raw sample lines as well.

local TAIL = 0 -- raw sample lines to append (0 = summary only; 60 = last 15 s)

local folder = workspace:FindFirstChild("Probe86")
if not folder then return "Probe86 is not installed" end
local samples = folder:FindFirstChild("Samples") :: StringValue
local stalls = folder:FindFirstChild("Stalls") :: StringValue

local header, rows = nil, {}
for line in string.gmatch(samples.Value, "[^\n]+") do
	if not header then
		header = {}
		for field in string.gmatch(line, "[^,]+") do table.insert(header, field) end
	else
		local row, index = {}, 1
		for field in string.gmatch(line, "([^,]*)") do
			if index <= #header then row[header[index]] = field end
			index += 1
		end
		table.insert(rows, row)
	end
end
if #rows < 2 then return "Probe86 has " .. tostring(#rows) .. " samples" end

local function number(row, key) return tonumber(row[key]) or 0 end

-- Wall seconds per CPU second. This is the whole premise of the planning-budget
-- fix: PathRequestTimeout is spent in CPU seconds, so this ratio is the factor
-- by which a 3-second budget overruns in real time.
local wallSpan = number(rows[#rows], "wall") - number(rows[1], "wall")
local cpuSpan = number(rows[#rows], "cpu") - number(rows[1], "cpu")

local targeted, standing, computing, waiting, noRoute = 0, 0, 0, 0, 0
local longestComputing, currentComputing = 0, 0
local failures, states = {}, {}
for index, row in ipairs(rows) do
	local previous = rows[index - 1]
	local step = previous and (number(row, "wall") - number(previous, "wall")) or 0
	states[row.state] = (states[row.state] or 0) + 1
	if row.failure ~= "" then failures[row.failure] = (failures[row.failure] or 0) + 1 end
	if number(row, "targetId") ~= 0 then
		targeted += 1
		if row.moving ~= "true" then standing += 1 end
		if row.state == "WAITING" or row.path == "WAITING_FOR_CLEARANCE" then waiting += 1 end
		if number(row, "waypoints") == 0 then noRoute += 1 end
		if row.computing == "true" then
			computing += 1
			currentComputing += step
			longestComputing = math.max(longestComputing, currentComputing)
		else
			currentComputing = 0
		end
	end
end

local lines = {
	("samples %d over %.1f s wall / %.1f s cpu  (wall per cpu second: %.2f)")
		:format(#rows, wallSpan, cpuSpan, cpuSpan > 0 and wallSpan / cpuSpan or -1),
	("seed %s pinned=%s  pumps %s")
		:format(rows[#rows].seed, rows[#rows].pinned, rows[#rows].pumps),
	("with a target: %d samples, standing %d (%.0f%%), Computing %d (%.0f%%), "
		.. "WAITING %d, no route %d")
		:format(targeted, standing, targeted > 0 and standing / targeted * 100 or 0,
			computing, targeted > 0 and computing / targeted * 100 or 0, waiting, noRoute),
	("longest unbroken Computing run: %.1f s wall"):format(longestComputing),
	("stall episodes recorded: %s"):format(tostring(folder:GetAttribute("Stalls"))),
	"states: ",
}
for name, count in pairs(states) do lines[#lines] ..= name .. "=" .. count .. " " end
table.insert(lines, "path failures seen:")
for reason, count in pairs(failures) do
	table.insert(lines, ("  %4d  %s"):format(count, reason))
end
table.insert(lines, "--- stalls ---")
table.insert(lines, stalls.Value)

if TAIL > 0 then
	table.insert(lines, "--- raw tail ---")
	local kept, all = {}, {}
	for line in string.gmatch(samples.Value, "[^\n]+") do table.insert(all, line) end
	for index = math.max(1, #all - TAIL + 1), #all do table.insert(kept, all[index]) end
	table.insert(lines, table.concat(kept, "\n"))
end

return table.concat(lines, "\n")
