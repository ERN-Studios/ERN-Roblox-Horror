local A=require(game.ServerScriptService["Level 3 Systems"]["Level 3 Round Adapter"])
local m=A.GetManifest()
local output={keys={},rooms={},links={}}
for k in pairs(m) do table.insert(output.keys,k) end
for _,r in ipairs(m.Layout.Rooms) do table.insert(output.rooms,{id=r.Id,x=r.X,z=r.Z,w=r.W,d=r.D}) end
for _,r in ipairs(m.Layout.Links) do table.insert(output.links,{a=r.A,b=r.B,door=r.Door}) end
return output
