local out={players={},zones={}}
for _,p in ipairs(game.Players:GetPlayers()) do table.insert(out.players,{name=p.Name,id=p.UserId,attributes=p:GetAttributes()}) end
for _,o in ipairs(workspace:GetDescendants()) do
 if o:IsA("BasePart") and o.Name:find("LaunchZone") then
  table.insert(out.zones,{path=o:GetFullName(),size={o.Size.X,o.Size.Y,o.Size.Z},position={o.Position.X,o.Position.Y,o.Position.Z},attributes=o:GetAttributes()})
 end
end
return out
