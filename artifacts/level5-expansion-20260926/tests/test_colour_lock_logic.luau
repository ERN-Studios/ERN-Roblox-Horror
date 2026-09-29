local Logic=require("../../../ServerScriptService/Level 5 Systems/Level 5 Colour Lock Logic.ModuleScript")
local checks=0
local function check(ok,message) checks+=1;assert(ok,message) end
local matches=0
for a=1,4 do for b=1,4 do for c=1,4 do for d=1,4 do
	local sequence={a,b,c,d};check(Logic.ValidateSequence(sequence),"Every four-wheel choice must be valid")
	if Logic.Matches(sequence) then matches+=1;check(a==1 and b==2 and c==3 and d==4,"Only the authored colour order opens") end
end end end end
check(matches==1,"Exactly one solution among 256 choices")
for _,bad in ipairs({false,true,7,"1234",{},{1},{1,2,3},{1,2,3,4,1},{1,2,3,0},{1,2,3,5},{1,2,3,1.5},{1,2,3,"4"},{1,2,3,{}},{1,2,3,math.huge},{1,2,3,0/0},{[0]=1,1,2,3,4},{[1]=1,[2]=2,[4]=4},{1,2,3,4,extra=true}}) do
	check(not Logic.ValidateSequence(bad),"Reject malformed sequence")
	check(not Logic.Matches(bad),"Malformed sequence must never open")
end
check(not Logic.ValidateSequence(nil),"Reject nil")
local good={live=true,roundActive=true,level=5,inRound=true,escaped=false,spectating=false,health=100,distance=12,lineOfSight=true}
check(Logic.CanUse(good),"Living nearby active participant may interact")
for _,key in ipairs({"live","roundActive","inRound","lineOfSight"}) do
	local state=table.clone(good);state[key]=false;check(not Logic.CanUse(state),"Reject false "..key)
	state[key]=nil;check(not Logic.CanUse(state),"Reject missing "..key)
end
for _,key in ipairs({"escaped","spectating"}) do local state=table.clone(good);state[key]=true;check(not Logic.CanUse(state),"Reject "..key) end
for _,level in ipairs({0,1,2,3,4,6,"5"}) do local state=table.clone(good);state.level=level;check(not Logic.CanUse(state),"Reject other level") end
for _,health in ipairs({0,-1,0/0,"100"}) do local state=table.clone(good);state.health=health;check(not Logic.CanUse(state),"Reject dead/malformed health") end
for _,distance in ipairs({-1,14.001,9999,math.huge,0/0,"3"}) do local state=table.clone(good);state.distance=distance;check(not Logic.CanUse(state),"Reject out-of-range/malformed distance") end
for _,distance in ipairs({0,13.999,14}) do local state=table.clone(good);state.distance=distance;check(Logic.CanUse(state),"Allow inclusive valid range") end
check(table.concat(Logic.Choices,",")=="RED,YELLOW,BLUE,GREEN","Authored colour order")
check(table.concat(Logic.Symbols,",")=="◯,△,□,◇","Accessible clue symbols")
print(string.format("PASS %d assertions; all 256 candidate answers checked",checks))
