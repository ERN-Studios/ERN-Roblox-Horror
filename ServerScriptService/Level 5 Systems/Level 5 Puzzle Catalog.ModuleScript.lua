-- Pure server-side puzzle definitions and gate-bound submission validation.
-- Public() copies presentation only; never replicate Get() or its solutions.
local Catalog = {}
local function options(labels, icons)
	local result = {}
	for i, label in ipairs(labels) do result[i] = {label = label, icon = icons and icons[i] or nil} end
	return result
end
local definitions = {
	{title="Four House Colours",instructions="Read the four numbered house clues. Match their colours.",mode="colours",count=4,labels={"1","2","3","4"},options=options({"RED","YELLOW","BLUE","GREEN"},{"◯","△","□","◇"}),solution={1,2,3,4},incorrectText="Check the numbered clues and try those colours again."},
	{title="Domestic Symbols",instructions="Read the three symbols in the house, from left to right.",mode="symbols",count=3,labels={"1","2","3"},options=options({"KEY","LAMP","CHAIR","CUP"}),solution={2,4,1},incorrectText="Read the house symbols from left to right."},
	{title="Missing Addresses",instructions="Find red, blue and yellow house numbers, in that order.",mode="address",count=3,labels={"RED","BLUE","YELLOW"},options=options({"0","1","2","3","4","5","6","7","8","9"}),solution={3,7,5},incorrectText="Use the red number, then blue, then yellow."},
	{title="Quiet Switches",instructions="Match the three switch positions shown inside the house.",mode="switches",count=3,labels={"1","2","3"},options=options({"DOWN","UP"},{"↓","↑"}),solution={2,1,2},incorrectText="Check which switches point up and which point down."},
	{title="Stopped Clocks",instructions="Match the three stopped clocks, from left to right.",mode="clocks",count=3,labels={"1","2","3"},options=options({"12:00","3:00","6:00","9:00"}),solution={2,4,3},incorrectText="Read the stopped clocks from left to right."},
	{title="Empty Channels",instructions="Enter the three channel numbers shown inside the house.",mode="television",count=3,labels={"1","2","3"},options=options({"CH01","CH02","CH03","CH04","CH05","CH06","CH07","CH08","CH09"}),solution={4,7,2},incorrectText="Check the three channel numbers and their order."},
	{title="Last Directions",instructions="Follow the three house arrows, from left to right.",mode="arrows",count=3,labels={"1","2","3"},options=options({"UP","RIGHT","DOWN","LEFT"},{"↑","→","↓","←"}),solution={2,3,1},incorrectText="Read the three arrow directions from left to right."},
}
local function freezeDeep(value)
	if type(value) ~= "table" or table.isfrozen(value) then return value end
	for _, child in pairs(value) do freezeDeep(child) end
	return table.freeze(value)
end
freezeDeep(definitions)
local function finite(value)
	return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function validGate(gate)
	return finite(gate) and gate%1==0 and gate>=1 and gate<=#definitions
end
function Catalog.Get(gate)
	return validGate(gate) and definitions[gate] or nil
end
function Catalog.Public(gate)
	local definition=Catalog.Get(gate)
	if not definition then return nil end
	local public={title=definition.title,instructions=definition.instructions,mode=definition.mode,count=definition.count,
		incorrectText=definition.incorrectText,labels={},options={},startingIndices={}}
	for i,label in ipairs(definition.labels) do public.labels[i]=label;public.startingIndices[i]=1 end
	for i,option in ipairs(definition.options) do public.options[i]={label=option.label,icon=option.icon} end
	return public
end
function Catalog.ValidateSequence(gate,sequence)
	local definition=Catalog.Get(gate)
	if not definition then return false,"INVALID_GATE" end
	if type(sequence)~="table" or getmetatable(sequence)~=nil then return false,"MALFORMED_ANSWER" end
	local seen=0
	for index,value in pairs(sequence) do
		if not finite(index) or index%1~=0 or index<1 or index>definition.count
			or not finite(value) or value%1~=0 or value<1 or value>#definition.options then return false,"MALFORMED_ANSWER" end
		seen+=1
	end
	if seen~=definition.count then return false,"MALFORMED_ANSWER" end
	return true,nil
end
function Catalog.Matches(gate,sequence)
	if not Catalog.ValidateSequence(gate,sequence) then return false end
	for index,value in ipairs(definitions[gate].solution) do if sequence[index]~=value then return false end end
	return true
end
function Catalog.CanAttempt(gate,previousFullyOpen)
	return validGate(gate) and (gate==1 or previousFullyOpen==true)
end
function Catalog.ValidateSubmission(context,sequence)
	if type(context)~="table" then return false,"INVALID_SESSION" end
	local gate=context.gate
	if not validGate(gate) or gate~=context.expectedGate then return false,"INVALID_GATE" end
	if type(context.nonce)~="string" or #context.nonce==0 or #context.nonce>128
		or type(context.expectedNonce)~="string" or context.nonce~=context.expectedNonce then return false,"INVALID_SESSION" end
	if not finite(context.elapsedSinceOpen) or context.elapsedSinceOpen<0 or context.elapsedSinceOpen>120 then return false,"SESSION_EXPIRED" end
	if not finite(context.elapsedSinceSubmit) or context.elapsedSinceSubmit<.65 then return false,"RATE_LIMITED" end
	if not Catalog.CanAttempt(gate,context.previousFullyOpen) then return false,"PREVIOUS_GATE_CLOSED" end
	if context.canUse~=true then return false,"CANNOT_USE" end
	local valid,reason=Catalog.ValidateSequence(gate,sequence)
	if not valid then return false,reason end
	if not Catalog.Matches(gate,sequence) then return false,"WRONG_ANSWER" end
	return true,nil
end
return table.freeze(Catalog)
