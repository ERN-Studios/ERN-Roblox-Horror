-- Execute the emitted installer against fake Studio instances/services only.
-- Concurrency cases check real installer assertions and exact prepared hashes.
local fs,luau,serde=require("@lune/fs"),require("@lune/luau"),require("@lune/serde")
local ROOT="tools/level3_finale_player_20261002/install/"
local manifest=serde.decode("json",fs.readFile(ROOT.."source-manifest.v2.json"))
local scriptSource=fs.readFile(ROOT.."install-five-scoped.v2.luau")
assert(serde.hash("sha256",scriptSource)==manifest.installerSHA256)
luau.compile(scriptSource)
local results={}
local function check(name,fn) fn();table.insert(results,name) end
local function fixture(kind)
    local nodes,service,writes,compiles={}, {},0,0
    local game={PlaceId=131311258779917,GameId=10559217407,Children={}}
    function game:FindFirstChild(name) return self.Children[name] end
    local function node(parent,name)
        local n={Name=name,Parent=parent,Children={}}
        function n:FindFirstChild(child) return self.Children[child] end
        parent.Children[name]=n;return n
    end
    for _,row in ipairs(manifest.changes) do
        local object=game
        for name in row.path:gmatch("[^.]+") do object=object:FindFirstChild(name) or node(object,name) end
        object.ClassName=row.className;object.Source=fs.readFile(row.baselineFile);object.Editor=object.Source
        nodes[row.path]=object
    end
    local first=manifest.changes[1].path
    local last=manifest.changes[5].path
    if kind=="initialSource" then nodes[last].Source..=" --concurrent"
    elseif kind=="initialEditor" then nodes[last].Editor..=" --unsaved"
    elseif kind=="initialClass" then nodes[last].ClassName="Script"
    elseif kind=="wrongPlace" then game.PlaceId=1 end
    service.RunService={IsRunning=function() return kind=="running" end}
    service.EncodingService={ComputeBufferHash=function(_,value)
        local hex=serde.hash("sha256",buffer.tostring(value))
        return buffer.fromstring((hex:gsub("%x%x",function(pair) return string.char(tonumber(pair,16)) end)))
    end}
    service.HttpService={JSONEncode=function(_,value) return serde.encode("json",value) end}
    local calls=0
    service.ScriptEditorService={GetEditorSource=function(_,object) return object.Editor end,
        UpdateSourceAsync=function(_,object,callback)
            calls+=1
            if kind=="futureSource" and calls==1 then nodes[last].Source..=" --concurrent" end
            if kind=="priorSource" and calls==2 then nodes[first].Source..=" --concurrent" end
            if kind=="futureEditor" and calls==1 then nodes[last].Editor..=" --concurrent" end
            if kind=="instanceSwap" and calls==1 then
                local old=nodes[last];local replacement=table.clone(old);old.Parent.Children[old.Name]=replacement
            end
            local current=object.Source
            if kind=="callbackArgument" and calls==1 then current..=" --retrynewcontent" end
            local candidate=callback(current)
            object.Source=candidate;object.Editor=candidate;writes+=1
        end}
    function game:GetService(name) return assert(service[name],name) end
    local execute=luau.load(scriptSource,{environment={game=game,Enum={HashAlgorithm={Sha256={}}},
        DateTime={now=function() return {ToIsoDate=function() return "2026-10-02T21:00:00Z" end} end},
        print=function() end,
        loadstring=function(source) luau.compile(source);compiles+=1;return function() end end,
    }})
    local ok,result=pcall(execute)
    return {ok=ok,result=result,writes=writes,compiles=compiles,nodes=nodes}
end
check("valid five-source CAS prepares exact candidate hashes and writes all five",function()
    local f=fixture("valid");assert(f.ok,tostring(f.result));assert(f.writes==5 and f.compiles==5)
    for _,row in ipairs(manifest.changes) do
        assert(serde.hash("sha256",f.nodes[row.path].Source)==row.candidateSHA256)
        assert(f.nodes[row.path].Source==f.nodes[row.path].Editor)
    end
    assert(#f.result.prewrite==5 and #f.result.sources==5 and f.result.sceneChanged==false)
end)
for _,kind in ipairs({"initialSource","initialEditor","initialClass","wrongPlace","running"}) do
    check(kind.." aborts before any install write",function()
        local f=fixture(kind);assert(not f.ok and f.writes==0)
    end)
end
for _,kind in ipairs({"futureSource","futureEditor","instanceSwap","callbackArgument"}) do
    check(kind.." during callback aborts with no install writes",function()
        local f=fixture(kind);assert(not f.ok and f.writes==0 and f.compiles==5)
    end)
end
check("concurrent edit to an already-written source aborts next write and preserves edit",function()
    local f=fixture("priorSource");assert(not f.ok and f.writes==1)
    assert(f.nodes[manifest.changes[1].path].Source:find("--concurrent",1,true))
    assert(serde.hash("sha256",f.nodes[manifest.changes[2].path].Source)==manifest.changes[2].baselineSHA256)
end)
fs.writeFile("artifacts/level3-finale-player-20261002/installer-mock-receipt.json",serde.encode("json",{
    kind="Exact generated installer fake Studio CAS tests",studioWriteClaim=false,
    installerSHA256=manifest.installerSHA256,installerBytes=manifest.installerBytes,
    scenarios=#results,passed=results,
},true))
print(serde.encode("json",{passed=true,scenarios=#results,installerSHA256=manifest.installerSHA256,installerBytes=manifest.installerBytes}))
