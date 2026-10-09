-- Compile every LuaSourceContainer in the open place, WITHOUT running any of it.
--
-- There is no scriptable "compile this string" in Studio: `loadstring` is gated
-- behind a place setting this project deliberately leaves off, and `require`ing
-- a module compiles it AND executes it. So each source is wrapped as
--
--     return function()
--     <the whole script>
--     end
--
-- and required. Compiling the wrapper compiles the entire body -- a syntax error
-- anywhere in it makes `require` raise -- while `require` only hands back the
-- function and never calls it, so nothing the script does actually happens. The
-- wrapper ModuleScript is destroyed immediately afterwards.
--
-- The wrapper is staged through ScriptEditorService:UpdateSourceAsync, not a raw
-- `.Source` write: `.Source` refuses any string of 200,000 characters or more,
-- and Level 2 World Builder alone is 248,130. A raw write reports "compiled
-- 113/114" and quietly counts the one script it could not even load as a pass,
-- which is why a script that fails to STAGE is reported separately here and is
-- never counted as compiled.
--
-- Paste into execute_luau (Edit is fine) and read the returned summary.
local Storage = game:GetService("ServerStorage")
local ScriptEditorService = game:GetService("ScriptEditorService")

local function pathOf(instance)
	local parts, node = {}, instance
	while node and node ~= game do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end

local targets = {}
for _, d in ipairs(game:GetDescendants()) do
	if d:IsA("LuaSourceContainer") then targets[#targets + 1] = d end
end

local failures, compiled, skipped = {}, 0, {}
for _, target in ipairs(targets) do
	local wrapped = "return function()\n" .. target.Source .. "\nend"
	local probe = Instance.new("ModuleScript")
	probe.Name = "CompileProbe"
	probe.Parent = Storage
	local staged, stageError = pcall(function()
		ScriptEditorService:UpdateSourceAsync(probe, function() return wrapped end)
	end)
	if not staged then
		skipped[#skipped + 1] = pathOf(target) .. " (stage failed: " .. tostring(stageError) .. ")"
	elseif probe.Source ~= wrapped then
		skipped[#skipped + 1] = pathOf(target) .. " (staged source did not land)"
	else
		local ok, err = pcall(require, probe)
		if ok then
			compiled += 1
		else
			failures[#failures + 1] = pathOf(target) .. "  ->  " .. tostring(err)
		end
	end
	probe:Destroy()
end

table.sort(failures)
table.sort(skipped)
return string.format("compiled %d/%d\nFAILURES:\n%s\nNOT STAGED:\n%s", compiled, #targets,
	#failures == 0 and "  none" or table.concat(failures, "\n"),
	#skipped == 0 and "  none" or table.concat(skipped, "\n"))
