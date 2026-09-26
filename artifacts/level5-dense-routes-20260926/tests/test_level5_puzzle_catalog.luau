local Catalog=require("../../../ServerScriptService/Level 5 Systems/Level 5 Puzzle Catalog.ModuleScript")
local assertions,combinations=0,0
local function check(value,message) assertions+=1;assert(value,message) end
local function context(gate)
	return {gate=gate,expectedGate=gate,nonce="gate-session-token",expectedNonce="gate-session-token",
		elapsedSinceOpen=1,elapsedSinceSubmit=1e9,previousFullyOpen=true,canUse=true}
end
local expectedSolutions={{1,2,3,4},{2,4,1},{3,7,5},{2,1,2},{2,4,3},{4,7,2},{2,3,1}}
for gate=1,7 do
	local definition=Catalog.Get(gate)
	check(#definition.instructions<=65,"mobile instructions too long")
	check(table.isfrozen(definition) and table.isfrozen(definition.solution),"server definition mutable")
	for i,value in ipairs(expectedSolutions[gate]) do check(definition.solution[i]==value,"wrong authored answer") end
	local public=Catalog.Public(gate)
	check(public.solution==nil and #public.startingIndices==definition.count,"public response leaks or lacks fields")
	local allowed={title=true,instructions=true,mode=true,count=true,incorrectText=true,labels=true,options=true,startingIndices=true}
	for key in pairs(public) do check(allowed[key],"unexpected public field") end
	for _,value in ipairs(public.startingIndices) do check(value==1,"unexpected starting index") end
	public.labels[1]="changed";public.options[1].label="changed"
	check(definition.labels[1]~="changed" and definition.options[1].label~="changed","public table shares server definition")
	local solutionCount=0
	local sequence={}
	local function visit(index)
		if index<=definition.count then
			for value=1,#definition.options do sequence[index]=value;visit(index+1) end
			return
		end
		combinations+=1
		check(Catalog.ValidateSequence(gate,sequence),"valid combination rejected")
		local expected=true
		for i,value in ipairs(expectedSolutions[gate]) do if sequence[i]~=value then expected=false end end
		check(Catalog.Matches(gate,sequence)==expected,"answer comparison wrong")
		local ok,reason=Catalog.ValidateSubmission(context(gate),sequence)
		check(ok==expected and (expected and reason==nil or not expected and reason=="WRONG_ANSWER"),"submission outcome wrong")
		if ok then solutionCount+=1 end
	end
	visit(1)
	check(solutionCount==1,"ambiguous puzzle solution")
	check(Catalog.CanAttempt(gate,false)==(gate==1),"previous gate bypass")
	for _,bad in ipairs({{}, {1}, {1,2,3,4,5}, {[0]=1,[1]=1,[2]=1,[3]=1,[4]=1}, {1.5,1,1}, {0,1,1}, {math.huge,1,1}, {0/0,1,1}, {"1",1,1}, {extra=1}, setmetatable({},{})}) do
		check(not Catalog.ValidateSequence(gate,bad),"malformed answer accepted")
	end
	local sparse=table.clone(expectedSolutions[gate]);sparse[2]=nil
	check(not Catalog.ValidateSequence(gate,sparse),"sparse answer accepted")
	local extra=table.clone(expectedSolutions[gate]);extra.unexpected=1
	check(not Catalog.ValidateSequence(gate,extra),"dictionary payload accepted")
	local answer=table.clone(expectedSolutions[gate])
	local cases={
		{"expectedGate",gate%7+1,"INVALID_GATE"},{"nonce","other-gate","INVALID_SESSION"},
		{"nonce","","INVALID_SESSION"},{"nonce",string.rep("x",129),"INVALID_SESSION"},
		{"elapsedSinceOpen",120.001,"SESSION_EXPIRED"},{"elapsedSinceOpen",-1,"SESSION_EXPIRED"},
		{"elapsedSinceOpen",0/0,"SESSION_EXPIRED"},{"elapsedSinceOpen",math.huge,"SESSION_EXPIRED"},
		{"elapsedSinceSubmit",.649,"RATE_LIMITED"},{"elapsedSinceSubmit",-1,"RATE_LIMITED"},
		{"elapsedSinceSubmit",0/0,"RATE_LIMITED"},{"elapsedSinceSubmit",math.huge,"RATE_LIMITED"},
		{"canUse",false,"CANNOT_USE"},{"canUse",1,"CANNOT_USE"},
	}
	if gate>1 then table.insert(cases,{"previousFullyOpen",false,"PREVIOUS_GATE_CLOSED"}) end
	for _,case in ipairs(cases) do
		local attempt=context(gate);attempt[case[1]]=case[2]
		local ok,reason=Catalog.ValidateSubmission(attempt,answer)
		check(not ok and reason==case[3],"invalid context accepted or wrong reason: "..case[1])
	end
	local edge=context(gate);edge.elapsedSinceOpen=120;edge.elapsedSinceSubmit=.65
	check(Catalog.ValidateSubmission(edge,answer),"inclusive expiry/cooldown boundary wrong")
end
for _,gate in ipairs({0,8,-1,1.5,math.huge,0/0,"1",true}) do
	check(Catalog.Get(gate)==nil and Catalog.Public(gate)==nil and not Catalog.CanAttempt(gate,true),"invalid gate accepted")
end
check(Catalog.Get(nil)==nil and not Catalog.ValidateSequence(1,nil),"nil input accepted")
check(not Catalog.ValidateSubmission(nil,{1,2,3,4}),"missing context accepted")
check(combinations==2185,"exhaustive combination count changed")
print(string.format("PASS Puzzle Catalog: %d assertions; %d exhaustive combinations across 7 gates; pure logic only",assertions,combinations))
