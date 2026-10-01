assert(game.PlaceId == 131311258779917, "Wrong place")
assert(not game:GetService("RunService"):IsRunning(), "Read requires Edit")
local out = {}
for _, i in ipairs(game:GetDescendants()) do
    if i:IsA("LuaSourceContainer") then
        local name = i.Name:lower()
        if name:find("lobbyreimagined", 1, true) or name:find("previewaccess", 1, true)
            or name:find("gamemanager", 1, true) or name:find("devaccess", 1, true)
            or name:find("routing", 1, true) or (i.Parent and i.Parent.Name == "LobbyReimaginedPreview") then
            table.insert(out, {path = i:GetFullName(), class = i.ClassName, bytes = #i.Source})
        end
    end
end
table.sort(out, function(a, b) return a.path < b.path end)
return game:GetService("HttpService"):JSONEncode({placeId = game.PlaceId, universeId = game.GameId,
    httpEnabled = game:GetService("HttpService").HttpEnabled, scripts = out})
