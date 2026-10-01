-- Edit-only, exact baseline guarded installation of this Level 6 task.
local HS=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong experience")
assert(not game:GetService("RunService"):IsRunning(),"Apply only in Edit")
local allowed={
    ["Level 6 Configuration"]=true,
    ["Level 6 Mall Manager AI Controller"]=true,
    ["Level 6 Objective Controller"]=true,
    ["Level 6 World Builder"]=true,
    ["Level 6 Visual Adapter"]=true,
    ["Level 6 Balloon Dressing"]=true,
    ["Level 6 Crayon Wall Art"]=true,
}
local folder=game:GetService("ServerScriptService"):WaitForChild("Level 6 Systems")
local previousHttp=HS.HttpEnabled
local receipts={}
local ok,problem=pcall(function()
    HS.HttpEnabled=true
    local payload=HS:JSONDecode(HS:GetAsync("http://127.0.0.1:8884/entity-decor-payload.json",true))
    assert(payload.placeId==game.PlaceId and #payload.scripts>=1 and #payload.scripts<=7,"Wrong payload")
    local seen={}
    for _,item in ipairs(payload.scripts) do
        assert(allowed[item.name] and not seen[item.name],"Unexpected/duplicate target")
        seen[item.name]=true
        assert(item.path==folder:GetFullName().."."..item.name,"Unexpected exact path")
        local instance=folder:FindFirstChild(item.name)
        if item.new then
            assert(not instance,"New target already exists; reread Studio")
        else
            assert(instance and instance.ClassName=="ModuleScript","Target class changed")
            assert(instance.Source==item.before and SES:GetEditorSource(instance)==item.before,
                "Concurrent source/editor change: "..item.path)
        end
        local chunk,err=loadstring(item.after)
        assert(chunk,"Compile failed "..item.path..": "..tostring(err))
        item.instance=instance
    end
    -- New required modules are installed before the adapters that reference them.
    table.sort(payload.scripts,function(a,b)
        if a.new~=b.new then return a.new==true end
        return a.path<b.path
    end)
    for _,item in ipairs(payload.scripts) do
        local target=item.instance
        if item.new then
            assert(not folder:FindFirstChild(item.name),"Concurrent new module")
            target=Instance.new("ModuleScript")
            target.Name=item.name
            target.Source=item.after
            target.Parent=folder
        else
            assert(target.Parent==folder and target.Name==item.name,"Target identity changed")
            assert(target.Source==item.before and SES:GetEditorSource(target)==item.before,"Concurrent update")
            SES:UpdateSourceAsync(target,function(editor)
                assert(editor==item.before and target.Source==item.before,"Concurrent inside update")
                return item.after
            end)
        end
        assert(target.Source==item.after and SES:GetEditorSource(target)==item.after,"Source/editor parity")
        table.insert(receipts,{path=item.path,class=target.ClassName,new=item.new==true,
            beforeSHA256=item.beforeSHA256,afterSHA256=item.afterSHA256,bytes=#item.after,editorMatch=true})
    end
end)
HS.HttpEnabled=previousHttp
assert(ok,"Stopped with completed writes="..HS:JSONEncode(receipts)..": "..tostring(problem))
return {ok=true,scripts=receipts,httpRestored=HS.HttpEnabled==previousHttp}
