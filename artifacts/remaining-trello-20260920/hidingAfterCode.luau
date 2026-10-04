local probe=Instance.new("Script");probe.Name="MallHidingReproduction";probe.Source=[==[
local p=game.Players:GetPlayers()[1];local char=p.Character;local root=char.HumanoidRootPart
local oldFrame=root.CFrame;local oldLevel=workspace:GetAttribute("SelectedLevel");local oldRound=workspace:GetAttribute("RoundActive");local oldIn=p:GetAttribute("InRound")
local world=Instance.new("Model");world.Name="Temporary Hiding Reproduction";world:SetAttribute("Level3_Generation",90920);world.Parent=workspace
local anchor=Instance.new("Part");anchor.Name="TestHideAnchor";anchor.Anchored=true;anchor.CanCollide=false;anchor.Transparency=1;anchor.CFrame=root.CFrame;anchor:SetAttribute("Level3_HideTableAnchor",true);anchor:SetAttribute("Level3_HideTableIndex",1);anchor.Parent=world
local prompt=Instance.new("ProximityPrompt");prompt.Name="HideUnderTablePrompt";prompt.Parent=anchor
local hiding=require(game.ServerScriptService["Level 3 Systems"]["Level 3 Hiding Controller"])
workspace:SetAttribute("SelectedLevel",3);workspace:SetAttribute("RoundActive",true);p:SetAttribute("InRound",true)
local ok,err=pcall(function()
hiding.Start({World=world,HideTables={anchor}},90920)
local entered,reason=hiding.DebugEnter(p,anchor);assert(entered,reason)
local hidden=root.Position;local initiallyAnchored=root.Anchored
local ejected=hiding.FlushAnchor(anchor,anchor.Position+Vector3.new(0,0,12))
local result={entered=entered,initiallyAnchored=initiallyAnchored,ejected=#ejected,remainsHidden=hiding.IsHidden(p,90920),distance=(root.Position-hidden).Magnitude}
assert(result.ejected==0 and result.remainsHidden and result.distance<.01,"inspection released hidden player")
assert(hiding.DebugExit(p),"exit failed")
result.exitRestored=not root.Anchored and not hiding.IsHidden(p,90920)
assert(result.exitRestored,"exit did not restore control")
workspace:SetAttribute("MallHidingReproduction",game.HttpService:JSONEncode(result))
end)
hiding.Stop();world:Destroy();workspace:SetAttribute("SelectedLevel",oldLevel);workspace:SetAttribute("RoundActive",oldRound);p:SetAttribute("InRound",oldIn);char:PivotTo(oldFrame*root.CFrame:ToObjectSpace(char:GetPivot()))
assert(ok,err)
]==];probe.Parent=game.ServerScriptService;task.wait(1);return workspace:GetAttribute("MallHidingReproduction")
