local fs, luau = require("@lune/fs"), require("@lune/luau")
local r = require("@lune/roblox")
local root = "tools/level3_promotion_20261002/gameplay_boards/r4-claude-fix/"
local source = fs.readFile(root .. "Builder.guard-first.candidate.luau")
luau.compile(source)
luau.compile(fs.readFile("tools/level3_promotion_20261002/gameplay_boards/support-board-runtime-smoke.luau"))
local first = assert(source:find("\tif existing then", 1, true))
local last = assert(source:find("\n\tlocal manifest", first, true))
local branch = source:sub(first, last - 1)
local cases = {}
local function scenario(name, options)
    local trace, warnings, restored = {}, {}, nil
    local model = {}
    function model:GetAttribute(key)
        if key == "Owned" or key == "Ready" then return options.conflicting ~= true end
        if key == "PreviewCenter" then return options.missingCenter and nil or r.Vector3.new(220,30,-760) end
    end
    -- Lua's and/or cannot encode nil; override the deliberate nil fixture.
    if options.missingCenter then
        function model:GetAttribute(key)
            if key == "Owned" or key == "Ready" then return true end
            return nil
        end
    end
    local transfer = {Board={}}
    local token = {}
    local guard = {Start=function(value)
        assert(value == model)
        table.insert(trace, "guard")
        if options.guardFailure then error("guard failure") end
    end}
    local run = luau.load("return function(existing)\n" .. branch .. "\nend", {environment={
        OWNED="Owned", script={Parent={WaitForChild=function(_, name)
            assert(name == "DevBayAccessGuard"); return token
        end}},
        require=function(value) assert(value == token); return guard end,
        typeof=typeof,
        supportBoardTransfer=function(value, center)
            assert(value == model and typeof(center) == "Vector3")
            table.insert(trace, "find")
            if options.missingBoard then error("original board missing") end
            return transfer
        end,
        applySupportBoardTransfer=function(value, destination)
            assert(value == transfer and destination == model)
            table.insert(trace, "apply")
            if options.applyFailure then error("apply failure") end
        end,
        restoreSupportBoardTransfer=function(value)
            table.insert(trace, "restore")
            restored = value
        end,
        warn=function(message) table.insert(warnings, message) end,
    }})()
    local ok, result = pcall(run, model)
    if options.conflicting then
        assert(not ok and #trace == 0 and #warnings == 0)
    elseif options.guardFailure then
        assert(not ok and trace[1] == "guard" and #trace == 1 and #warnings == 0)
    else
        assert(ok and result == model and trace[1] == "guard")
        if options.missingCenter then
            assert(#warnings == 1 and trace[2] == "restore" and restored == nil)
        elseif options.missingBoard then
            assert(#warnings == 1 and trace[2] == "find" and trace[3] == "restore" and restored == nil)
        elseif options.applyFailure then
            assert(#warnings == 1 and trace[2] == "find" and trace[3] == "apply"
                and trace[4] == "restore" and restored == transfer)
        else
            assert(#warnings == 0 and trace[2] == "find" and trace[3] == "apply")
        end
    end
    table.insert(cases, name)
end
scenario("guard precedes valid re-entry transfer", {})
scenario("missing center retains existing model and guard", {missingCenter=true})
scenario("missing or ambiguous board retains existing model and guard", {missingBoard=true})
scenario("failed apply restores transfer and retains guard", {applyFailure=true})
scenario("guard failure remains fail-closed", {guardFailure=true})
scenario("conflicting ownership remains fail-closed", {conflicting=true})
print("Syntax-only: R4 fix + optional runtime smoke compiled. " .. #cases .. " extracted-branch mocked scenarios passed.")
print("No native guard, renderer, replication or gameplay pass implied.")
