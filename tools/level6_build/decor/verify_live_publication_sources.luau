-- Read-only comparison against a fresh native-after snapshot, never a Studio push.
local HS=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
assert(not game:GetService("RunService"):IsRunning(),"Verify in Edit")
local beforeHttp=HS.HttpEnabled
local receipt={phase="after-successful-native-ui-publication",scripts={}}
local ok,problem=pcall(function()
    HS.HttpEnabled=true
    local payload=HS:JSONDecode(HS:GetAsync("http://127.0.0.1:8884/post-publish-comparison-payload.json",true))
    assert(game.PlaceId==payload.PlaceId and game.GameId==payload.UniverseId,"Wrong place")
    for _,row in payload.scripts do
        local target=game
        for token in row.path:gmatch("[^.]+") do target=assert(target:FindFirstChild(token),row.path) end
        assert(target.ClassName==row.class,"Class mismatch: "..row.path)
        assert(target.Source==row.source and SES:GetEditorSource(target)==row.source,"Fresh source/editor mismatch: "..row.path)
        table.insert(receipt.scripts,{path=row.path,class=row.class,SHA256=row.SHA256,role=row.role,editorMatch=true})
    end
    receipt.PlaceId=game.PlaceId
    receipt.UniverseId=game.GameId
    receipt.ProbeAbsent=game.ServerScriptService:FindFirstChild("__Level6DecorPlayProbe")==nil
    receipt.LiveLevel4Revision=workspace["Level 4 Cinema Blender"]:GetAttribute("Level4Revision")
    receipt.LiveLevel4PartCount=workspace["Level 4 Cinema Blender"]:GetAttribute("PartCount")
    receipt.LightingStyle=game.Lighting.LightingStyle.Name
    receipt.VerifiedAt=DateTime.now():ToIsoDate()
end)
HS.HttpEnabled=beforeHttp
assert(ok,tostring(problem))
receipt.HttpEnabled=HS.HttpEnabled
receipt.Passed=true
return HS:JSONEncode(receipt)
