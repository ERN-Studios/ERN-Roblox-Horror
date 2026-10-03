-- Pure daily ledger. Completion and its token award are one profile transaction.
-- Fixed first selection: all three can be completed solo without bought gear.
local Research = {}
Research.Goals = {
 {Key="Fuse", Title="Restore power", Detail="Personally insert a fuse in Level 1.", Reward=1},
 {Key="Lever", Title="Open the route", Detail="Personally activate a powered lever in Level 1.", Reward=1},
 {Key="Clear", Title="Return with research", Detail="Escape any level alive.", Reward=2},
}
function Research.Normalize(value)
 local result = {}
 for _, goal in ipairs(Research.Goals) do
  result[goal.Key] = type(value)=="table" and value[goal.Key]==true or false
 end
 return result
end
function Research.Complete(data, key)
 local goal
 for _, entry in ipairs(Research.Goals) do if entry.Key==key then goal=entry break end end
 if not goal then return false, 0 end
 local saved=data.Daily.Research
 if saved[key] then return false, 0 end
 if type(data.Tokens)~="number" or data.Tokens < 0 or data.Tokens ~= data.Tokens
  or data.Tokens > 9007199254740991-goal.Reward then return false,0 end
 saved[key]=true
 data.Tokens+=goal.Reward
 return true,goal.Reward
end
function Research.Public(saved, sameDay)
 local result={}
 for _,goal in ipairs(Research.Goals) do
  table.insert(result,{Key=goal.Key,Title=goal.Title,Detail=goal.Detail,Reward=goal.Reward,
   Complete=sameDay and type(saved)=="table" and saved[goal.Key]==true or false})
 end
 return result
end
return table.freeze(Research)
