-- Single existing script only. Generated from verified baseline; DO NOT RUN AS A BATCH.
-- No new Instances, source buffers, runtime rebuilds, attributes or property edits.
local HttpService=game:GetService("HttpService")
local ScriptEditorService=game:GetService("ScriptEditorService")
local names={"ServerScriptService","Level 5 Systems","Level 5 Round Adapter"}
local wantedClass="ModuleScript"
local baselineLength,baselineDjb=15482,2781571066
local expectedLength,expectedDjb=17720,3055794701
local invoked,accepted=false,false
local function djb2(text)
 local h=5381
 for i=1,#text do h=(h*33+string.byte(text,i))%4294967296 end
 return h
end
local function finish(status,detail)
 return HttpService:JSONEncode({status=status,detail=detail or "",path=table.concat(names,"."),class=wantedClass,
  updateInvoked=invoked,callbackAccepted=accepted,baselineLength=baselineLength,baselineDjb2=baselineDjb,
  expectedLength=expectedLength,expectedDjb2=expectedDjb})
end
if game.PlaceId~=131311258779917 or game.GameId~=10559217407 then return finish("WRONG_PLACE") end
if game:GetService("RunService"):IsRunning() then return finish("EDIT_MODE_REQUIRED") end
local function resolve()
 local parent=game
 for _,name in ipairs(names) do
  local found=nil
  for _,child in ipairs(parent:GetChildren()) do
   if child.Name==name then
    if found then return nil,"AMBIGUOUS_PATH" end
    found=child
   end
  end
  if not found then return nil,"MISSING_PATH" end
  parent=found
 end
 if parent.ClassName~=wantedClass then return nil,"WRONG_CLASS" end
 return parent,nil
end
local target,resolveError=resolve()
if not target then return finish(resolveError) end
local ok,current,editor=pcall(function()return target.Source,ScriptEditorService:GetEditorSource(target)end)
if not ok then return finish("READ_FAILED",tostring(current)) end
if current~=editor then return finish("SOURCE_EDITOR_CONFLICT") end
if #current~=baselineLength or djb2(current)~=baselineDjb then return finish("BASELINE_CHANGED") end
local edits={
 {old="--!strict\n-- Level 5 map-only preview lifecycle. Independent of Level 4 and its gameplay.\n-- GameManager owns entry, Back to Lobby and round cleanup. This module never\n-- sets Escaped/PuzzleWon or grants completion/rewards. The passive window\n-- encounter has no chase, damage or completion behavior.\n",new="--!strict\n-- Level 5 playable preview lifecycle. Independent of Level 4 and campaign completion.\n-- GameManager owns entry, Back to Lobby and round cleanup. This module never\n-- sets Escaped/PuzzleWon or grants completion/rewards. The passive window\n-- encounter has no chase, damage or completion behavior.\n"},
 {old="\tend\nend\n\nfunction Adapter.Build()\n\tassert(workspace:GetAttribute(\"Level5DevEnabled\") == true, \"Level 5 map preview is developer-only\")\n\tfor _, player in ipairs(Players:GetPlayers()) do\n\t\tassert(DevAccess.IsAllowed(player), \"Level 5 preview refuses a non-developer roster\")\n\tend\n\tfor _, level in ipairs({2, 3, 4}) do\n\t\tassert(workspace:FindFirstChild(\"Level \" .. level .. \" Generated World\") == nil,\n\t\t\t\"End the existing level before starting the Level 5 map preview\")\n\tend\n\tAdapter.Cleanup()\n\tassert(workspace:FindFirstChild(WORLD_NAME) == nil, \"Level 5 world name is occupied by unowned content\")\n",new="\tend\nend\n\n-- These two owned signs describe the current preview boundary. They do not\n-- complete the round, award a clear, or invoke any transfer; the existing\n-- BACK TO LOBBY control remains the player's way out.\nlocal function addPreviewNotices(world: Model, built: any)\n\tlocal notices = Instance.new(\"Folder\")\n\tnotices.Name = \"Level5PreviewNotices\"\n\tnotices:SetAttribute(OWNED, true)\n\tnotices.Parent = world\n\tlocal function sign(name: string, frame: CFrame, text: string)\n\t\tlocal board = Instance.new(\"Part\")\n\t\tboard.Name, board.Size, board.CFrame = name, Vector3.new(6.6, 3.6, 0.1), frame\n\t\tboard.Anchored, board.CanCollide, board.CanTouch, board.CanQuery = true, false, false, false\n\t\tboard.CastShadow = false\n\t\tboard.Color, board.Material = Color3.fromRGB(49, 44, 35), Enum.Material.Wood\n\t\tboard:SetAttribute(OWNED, true)\n\t\tboard.Parent = notices\n\t\tlocal gui = Instance.new(\"SurfaceGui\")\n\t\tgui.Name, gui.Face = \"PreviewInformation\", Enum.NormalId.Front\n\t\tgui.CanvasSize, gui.LightInfluence, gui.AlwaysOnTop = Vector2.new(880, 480), 0, false\n\t\tgui.MaxDistance = 55\n\t\tgui.Parent = board\n\t\tlocal label = Instance.new(\"TextLabel\")\n\t\tlabel.Position, label.Size = UDim2.fromScale(.06, .06), UDim2.fromScale(.88, .88)\n\t\tlabel.BackgroundTransparency = 1\n\t\tlabel.Font, label.TextColor3 = Enum.Font.GothamMedium, Color3.fromRGB(236, 226, 194)\n\t\tlabel.TextSize, label.TextWrapped, label.Text = 35, true, text\n\t\tlabel.Parent = gui\n\tend\n\tlocal entry = built.SpawnCFrame.Position\n\tsign(\"PreviewArrival\", CFrame.lookAt(entry + Vector3.new(8, 2, 7), entry + Vector3.new(0, 2, 0)),\n\t\t\"LEVEL 5 · PLAYABLE PREVIEW\\n\\nSeven puzzles lead through eight sections. The final slide and ending are still in development.\\n\\nUse the lobby control to leave at any time.\")\n\tassert(typeof(built.ChuteEnd) == \"CFrame\", \"Preview ending needs the authored descent endpoint\")\n\tlocal ending = built.ChuteEnd.Position\n\tsign(\"PreviewEnding\", CFrame.lookAt(ending + Vector3.new(0, 4.5, 8.45), ending + Vector3.new(0, 4.5, 0)),\n\t\t\"END OF THE CURRENT PREVIEW\\n\\nThe final slide and ending are still in development.\\n\\nUse the lobby control to return.\")\nend\n\nfunction Adapter.Build()\n\tif workspace:GetAttribute(\"Level5PublicPreviewEnabled\") ~= true then\n\t\tassert(workspace:GetAttribute(\"Level5DevEnabled\") == true, \"Level 5 preview is currently closed\")\n\t\tfor _, player in ipairs(Players:GetPlayers()) do\n\t\t\tassert(DevAccess.IsAllowed(player), \"Level 5 private preview requires a developer roster\")\n\t\tend\n\tend\n\tfor _, level in ipairs({2, 3, 4}) do\n\t\tassert(workspace:FindFirstChild(\"Level \" .. level .. \" Generated World\") == nil,\n\t\t\t\"End the existing level before starting the Level 5 preview\")\n\tend\n\tAdapter.Cleanup()\n\tassert(workspace:FindFirstChild(WORLD_NAME) == nil, \"Level 5 world name is occupied by unowned content\")\n"},
 {old="\t\t})\n\t\tassert(type(manifest) == \"table\" and typeof(manifest.SpawnCFrame) == \"CFrame\", \"Architecture needs an arrival SpawnCFrame\")\n\t\tmanifest.World, manifest.Origin = world, ORIGIN\n\t\tif RunService:IsRunning() then\n\t\t\tlocal progression = require(script.Parent:WaitForChild(\"Level 5 Section Progression\"))\n\t\t\tlocal progressResult = progression.Start(world, manifest, {\n",new="\t\t})\n\t\tassert(type(manifest) == \"table\" and typeof(manifest.SpawnCFrame) == \"CFrame\", \"Architecture needs an arrival SpawnCFrame\")\n\t\tmanifest.World, manifest.Origin = world, ORIGIN\n\t\taddPreviewNotices(world, manifest)\n\t\tif RunService:IsRunning() then\n\t\t\tlocal progression = require(script.Parent:WaitForChild(\"Level 5 Section Progression\"))\n\t\t\tlocal progressResult = progression.Start(world, manifest, {\n"}
}
local ranges={}
for index,edit in ipairs(edits) do
 local a,b=string.find(current,edit.old,1,true)
 if not a then return finish("FRAGMENT_MISSING",tostring(index)) end
 if string.find(current,edit.old,a+1,true) then return finish("FRAGMENT_NOT_UNIQUE",tostring(index)) end
 if index>1 and a<=ranges[index-1].last then return finish("OVERLAPPING_FRAGMENTS",tostring(index)) end
 ranges[index]={first=a,last=b,replacement=edit.new}
end
local newSource=current
for index=#ranges,1,-1 do
 local span=ranges[index]
 newSource=string.sub(newSource,1,span.first-1)..span.replacement..string.sub(newSource,span.last+1)
end
if #newSource~=expectedLength or djb2(newSource)~=expectedDjb then return finish("PATCH_FINGERPRINT_MISMATCH") end
if newSource==current then return finish("NO_CHANGE") end
local callbackProblem=nil
local writeOK,writeError=pcall(function()
 invoked=true
 ScriptEditorService:UpdateSourceAsync(target,function(old)
  -- Roblox may call again if an editor changes while the update is in flight.
  -- Returning nil cancels the update, including on a later retry.
  if callbackProblem then return nil end
  if old~=current then callbackProblem="CALLBACK_BASELINE_CHANGED";return nil end
  local stillTarget=resolve()
  if stillTarget~=target then callbackProblem="INSTANCE_PATH_CHANGED";return nil end
  if target.Source~=current then callbackProblem="SOURCE_CHANGED_DURING_UPDATE";return nil end
  accepted=true
  return newSource
 end)
end)
if callbackProblem then return finish(callbackProblem,"Cancelled; reread authoritative Source/editor before preparing another patch.") end
if not writeOK then return finish("UPDATE_FAILED",tostring(writeError)) end
if not accepted then return finish("UPDATE_CANCELLED") end
local readOK,sourceAfter,editorAfter=pcall(function()return target.Source,ScriptEditorService:GetEditorSource(target)end)
if not readOK then return finish("POSTWRITE_READ_FAILED",tostring(sourceAfter)) end
if sourceAfter==newSource and editorAfter==newSource then return finish("APPLIED_VERIFIED") end
return finish("POSTWRITE_PARITY_NOT_VERIFIED",HttpService:JSONEncode({sourceLength=#sourceAfter,sourceDjb2=djb2(sourceAfter),editorLength=#editorAfter,editorDjb2=djb2(editorAfter),equal=sourceAfter==editorAfter}))
