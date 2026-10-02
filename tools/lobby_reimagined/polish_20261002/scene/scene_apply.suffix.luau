function Module.Apply(model)
	assert(model:IsA("Model") and model.Name=="LobbyReimaginedPreview"
		and model:GetAttribute("LobbyReimaginedOwned")==true and model:GetAttribute("LobbyVisualRevision")==4
		and model:GetAttribute("Ready")==false,"Scene polish requires the owned R4 build transaction")
	assert(not model:FindFirstChild(FOLDER),"Conflicting scene presentation owner")
	local root = Instance.new("Folder");root.Name=FOLDER;own(root);root.Parent=model
	local changedEmitters = polishLighting(model)
	local stageParts = polishStage(model,root)
	local shop = polishShop(model,{owner=OWNER})
	root:SetAttribute("ChangedExistingEmitters",changedEmitters)
	root:SetAttribute("DisabledShopGlows",shop.disabledShopGlows)
	root:SetAttribute("AddedPointLights",0)
	root:SetAttribute("AddedColliders",0)
	root:SetAttribute("AddedUniqueMeshes",0)
	root:SetAttribute("StageGuidanceParts",stageParts)
	root:SetAttribute("ShopCards",#shop.cards)
	root:SetAttribute("AddedInstancedTriangles",(stageParts+shop.addedParts)*12)
	model:SetAttribute("ScenePolishRevision",1)
	return root
end
return Module
