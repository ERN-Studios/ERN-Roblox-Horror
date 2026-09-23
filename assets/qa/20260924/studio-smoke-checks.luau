-- RUN ONE SECTION AT A TIME, Server Play context. Read-only checks: no builds,
-- teleports, attributes, purchase prompts, rewards, or profile writes.
-- A Suite require can need Server even where an old header says Edit is safe.

-- LEVEL 2: deterministic plans plus sensor/recovery geometry in a standing L2.
do
 local systems=game:GetService("ServerScriptService")["Level 2 Systems"]
 local generator=require(systems["Level 2 Layout Generator"])
 local suite=require(systems["Level 2 Exit Transition Test Suite"])
 local result={Layouts={}}
 for _,seed in ipairs({1,101,7331}) do
  local layout=generator.Generate(seed)
  local ok,why=generator.Validate(layout)
  assert(ok,tostring(why))
  table.insert(result.Layouts,{Seed=seed,Halls=layout.HallCount,Corridors=layout.CorridorCount})
 end
 local world=assert(workspace:FindFirstChild("Level 2 Generated World"),"start Level 2 before its world check")
 local manifest={World=world,Exit={
  Trigger=world:FindFirstChild("Level 2 Exit Completion Beam",true),
  Backstop=world:FindFirstChild("Level 2 Exit Completion Backstop",true),
  SafeSpawn=world:FindFirstChild("Level 2 Exit Safe Spawn",true),
 }}
 result.Sensors=suite.ValidateCompletionSensors(manifest)
 result.Recovery=suite.ValidateRecoveryChamber(manifest)
 print(game:GetService("HttpService"):JSONEncode(result))
end

-- LEVEL 3: plans/config plus actual replicated standing-world objective state.
-- ValidateConfiguration already runs the default 9-seed generated-layout suite.
-- Navigation requires its default 20 seeds; a three-seed shortcut is invalid.
do
 local suite=require(game:GetService("ServerScriptService")["Level 3 Systems"]["Level 3 Test Suite"])
 local state=assert(game:GetService("ReplicatedStorage"):FindFirstChild("Level 3 State"))
 local report={Configuration=suite.ValidateConfiguration(),
  NavigationLayouts=suite.ValidateNavigationLayouts(),
  Runtime=suite.ValidateRuntime(state:GetAttribute("Level3_ModuleProgress"))}
 print(game:GetService("HttpService"):JSONEncode(report))
end

-- LEVEL 4: plan/brain pure, world reads actual objects/attributes (not manifest cache).
do
 local suite=require(game:GetService("ServerScriptService")["Level 4 Systems"]["Level 4 Test Suite"])
 print(game:GetService("HttpService"):JSONEncode(suite.RunAll()))
end

-- MCP execute_luau may own a different ModuleScript cache than the real round.
-- Do not call Adapter.Build() just because Adapter.GetManifest() returns nil.
-- Level2 ValidateExitGeometry needs the real complete manifest including authored
-- path points; the mini manifest above intentionally only tests sensor/recovery.
-- Level3 RunNavigationRegression and Level2 Probe* are active, destructive-to-the
-- disposable-round probes; not part of these bounded read-only smoke checks.
