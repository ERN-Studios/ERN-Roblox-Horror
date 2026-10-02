-- Apply once to the newly constructed owned R4 model, after end furniture exists.
-- Static templates live under this module. No runtime image allocation or global effects.
local HS = game:GetService("HttpService")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Module = {}
local OWNED = "LobbyReimaginedOwned"
local REVISION = "R4-MaterialPolish-20261002"
local BASELINE = "17b68efc473a0f100cf6ce6b9389332a5f2a87d82faf7694a0536a82483bc995"
local SPEC = HS:JSONDecode([====[{"materials":{"tunnel_concrete":{"color":{"pngSHA256":"174360cb5b0b750ccb4183fe393e29cf6f33149eb462786f8691ef2d56f0c130","originalURI":"rbxassetid://75893473229833"},"normal":{"pngSHA256":"87693ee0d94628e58f20901849584d1eb6c35f71dc5c76fc4e200572b8f53c04","originalURI":"rbxassetid://127271719715729"},"roughness":{"pngSHA256":"0e302cdf650a03989127b2e3cf05032348bfa4cbbaacdf1437b3f238097ae902","originalURI":"rbxassetid://96772314871126"}},"asphalt_road":{"color":{"pngSHA256":"f25701af130f829777208c0b6679cb46f5418cb18f8c22d13d6b969f0b969482","originalURI":"rbxassetid://122629305677764"},"normal":{"pngSHA256":"a8eb947bede56280fcbfe794c53959e901d8cabb517759c20afbdb8901d68831","originalURI":"rbxassetid://124637763157232"},"roughness":{"pngSHA256":"d3a24522eedbfa79c1880b39d354ac702bfd6c90867e20ce80ddaf76266ab563","originalURI":"rbxassetid://102850469487873"}},"sidewalk_concrete":{"color":{"pngSHA256":"c2ff43d2c7b6254589d99cbf5e09f727ec9faede72034fa054515a2c75fdb5f4","originalURI":"rbxassetid://103015335983029"},"normal":{"pngSHA256":"0fcfeaf303ca9ac4a68e6f319a2f961594f0ac9fccdf140e8f47d026f8656ab6","originalURI":"rbxassetid://134697002832773"},"roughness":{"pngSHA256":"881ae43eb5ef0b4ade620d2922a6966dae7864139a5ba2e788c866813ef1c2ee","originalURI":"rbxassetid://117887403540614"}}},"sidewalkAtlas":{"pngSHA256":"86447fb4c82082d2262327765a21ba8ef87c85b13dc53f524cbd130d5625d5f1","chunkSHA256":"9f1e2113cecb2fb4697f28fbd3088ba3981cddd9ad72c98564730ecdbe17e50f"}}]====])
local KNOWN = HS:JSONDecode([====[{"7b2d07b7259b203e09f73740121c7d0c724bcb608cb31abee921984893f6343c":{"triangles":1232,"family":"ArchRib","materialKey":"atlas"},"7c2f1f5d548079bc9fcc931d119ca031fe5f4d555c93383c6dd6ac2e2c87acd3":{"triangles":120,"family":"BayDecorLevel1","materialKey":"atlas"},"58e5c270565634f44f7b92c1ce8b6bfc0829bdce661020b8f464e283cc9ea00a":{"triangles":288,"family":"BayDecorLevel2","materialKey":"asset_113211706146395"},"6e070bf7b7c93e2ec92f6c4d4dfc5fc0ef79013032389a650dc12b1382f95489":{"triangles":1032,"family":"BayDecorLevel2","materialKey":"atlas"},"1be89dbe7c69540d2ebfbf45a4665c9dc142fca1f3c1cc13b8ecade45dad3280":{"triangles":12,"family":"BayDecorLevel3","materialKey":"asset_103412925025303"},"16c50be3a839ee03c29c612b9e419b35e8ed1f009695498e2e319518f6fff4e0":{"triangles":276,"family":"BayDecorLevel3","materialKey":"atlas"},"7a275038047f2e35b965399c3eebcd20c87dbb0c2e71c70ea6b9ae585e0194fe":{"triangles":1088,"family":"BayDecorLevel4","materialKey":"atlas"},"3fe5312cd0df0685b716711b7d21a639dc2689de658d7e056259dbce63f36dfa":{"triangles":36,"family":"BayDecorLevel5","materialKey":"asset_115748401620318"},"97c5785663a278e47079f3f3f77e4ee3cebff53536bd27a695c7524aa60a3a7c":{"triangles":36,"family":"BayDecorLevel5","materialKey":"asset_118880038763227"},"073da62fe36da9b2acecbc4800429aa59d345539f6e6579310ae0ca944a60d92":{"triangles":972,"family":"BayDecorLevel5","materialKey":"atlas"},"36dac2219cba2d5e7ae6c316e95c8f2ca21596b1a6dfeee513edbc572e436581":{"triangles":788,"family":"BayDecorLevel6","materialKey":"atlas"},"2db1cf899791e947832f8aa5ae3c59c169e935082e9a3e57f2b8adbf43f2a5cc":{"triangles":508,"family":"BayShellLevel1","materialKey":"asset_100093931957721"},"cee4c41ceea50343b5a7e5a3039c981bd415dee252060a7173ae63891993a997":{"triangles":1072,"family":"BayShellLevel1","materialKey":"asset_87947439437597"},"2b34725771bc4955f45fb2fb31d3afd7b28d27e336a7f0ffccb874320585f7d4":{"triangles":508,"family":"BayShellLevel1","materialKey":"asset_91804597609254"},"168c2f54441e4da6223a6836deaf2e1d0c55b79aa03cf96013cd54b0eef546cf":{"triangles":2088,"family":"BayShellLevel2","materialKey":"asset_113211706146395"},"50ead2ee2a92ce5defff88ff080654cca0a4d76b904dc2ac3e7204327ad13a37":{"triangles":508,"family":"BayShellLevel3","materialKey":"asset_110230144446272"},"f27406c3c56d522d21c42d1dfaa00d359b18ae7a90cccb0770543073f173f096":{"triangles":1072,"family":"BayShellLevel3","materialKey":"asset_128270554927663"},"fcbdeb2990bc6636d96917de907649c7e9a0a5c6ce0545f567a2421d415af6e1":{"triangles":508,"family":"BayShellLevel3","materialKey":"atlas"},"49a5edf6b1de26fb88ede6d56e09db92010519c8c36fe041b68ffa12c6e3e021":{"triangles":2088,"family":"BayShellLevel4","materialKey":"atlas"},"ee6e744a6caa39196f156d350b5a3197cda2677a86bf7c6500315da06cfa15d9":{"triangles":1580,"family":"BayShellLevel5","materialKey":"asset_108985650994325"},"658de91e76fc530a9638599228ec9f58e99350bd43efe2323436ab46f8759f7c":{"triangles":508,"family":"BayShellLevel6","materialKey":"atlas"},"cf3ca7ebc2348eecf15cd5f00fcd3757f87f598e110b7fd4118dee6672b1c50c":{"triangles":3240,"family":"BeigeKeyboard","materialKey":"atlas"},"ba44a630664daeef8961c6b24b812cbf54ae1bd5b8dd04968dc3aba3fb35d06d":{"triangles":748,"family":"BrownOfficeChair","materialKey":"atlas"},"19806213de1fe5eefc2baa758cba558a8706fabe99bd7c1be5ff958dd4e6b2cb":{"triangles":564,"family":"CRTMonitor","materialKey":"atlas"},"e1562e1f73866821c7e839995d247fe60ed9ae99e0009a1cd1deb4a3c77a5d4a":{"triangles":204,"family":"CableTray","materialKey":"atlas"},"e011e9a58bcf1f1f35dad9a0fe0428c261b1eb225da1f6fe150df31e538a02b8":{"triangles":84,"family":"ConduitSection","materialKey":"atlas"},"9a48ba903b8105664d14d827caa0303497b79ea3e7e7a73467b3f6c046f28776":{"triangles":9844,"family":"DJConsole","materialKey":"atlas"},"cf88f1bfc812363e8463d4bf5bced22d5e5314ee9d8dbc8c9eb99ba5f3dc320a":{"triangles":972,"family":"Desk","materialKey":"atlas"},"2169ee7d0e13a66dec43f64f583ee60f1648316479163768c35b866e3237a0a2":{"triangles":12,"family":"DoorThreshold","materialKey":"atlas"},"ac183c29110ca84341fa7a3a06305f3962afe292b0fb3978d381063e1e4571d4":{"triangles":12,"family":"DoorThreshold","materialKey":"sidewalk_concrete"},"7529cefda616e1166042a4f42ef80c954c924aef56e9c56fb247a9d0e7ee6790":{"triangles":12,"family":"EndBackstop","materialKey":"tunnel_concrete"},"e47d5f462c48e7f6736404e68aa74d108193d68c01b064a0944388b52130e0c6":{"triangles":72,"family":"EntryConnector","materialKey":"atlas"},"769b2ad03f3fa76b37c4e9ddbaf2cc906c1f666ab979dda58d5cd22278915c9a":{"triangles":12,"family":"EntryConnector","materialKey":"sidewalk_concrete"},"50da54e7952a0e7156ddf1b4d2e00aefc2cbf5b3e4c7a27b00d3d5628b3eb985":{"triangles":36,"family":"EntryConnector","materialKey":"tunnel_concrete"},"d6b0ae0d3c4852ffbb057ee7216763ee0dc0c1952ff8d8c8fc172f1bb9dea25e":{"triangles":1080,"family":"FilingCabinet","materialKey":"atlas"},"ed1d36cddded465da8a426f7bbadbb3658f7e798ab4c69b3aadea0145704a891":{"triangles":48,"family":"Fluorescent","materialKey":"atlas"},"c8e3e15a73ecd91222a15f5e78cbd03494ec70164550237c8f7d45e4b9dd9db4":{"triangles":128,"family":"HologramBand","materialKey":"atlas"},"308fc0df28a38fe2e4b5385e5db5379ad46ee57b48ac4a09e0e2ab237b0de6a8":{"triangles":512,"family":"HologramRing","materialKey":"atlas"},"ad9efe2e7d9461855d9934e903dbfc960833ca60c832d51f367009e8cfd11c11":{"triangles":396,"family":"LevelGate","materialKey":"atlas"},"c290f4df7df3339a3056b245293e2719e0ecf722a0c218015ee5272e604ff740":{"triangles":1520,"family":"Photocopier","materialKey":"atlas"},"5fd63320b807d4eb6d155233f729852e796c7155fb63b47e57497c3ad13b532d":{"triangles":1052,"family":"PlainShell","materialKey":"tunnel_concrete"},"601a13b055c3c1e98a1f5ab6bbb6d37aa99bdaee2b1feb0542d4f7fdd29e7275":{"triangles":2756,"family":"PortalShell","materialKey":"tunnel_concrete"},"779fb1d6b6a931ee1dac4dc6de4f22948e94905a1d5d592e651f627fd9ef9829":{"triangles":2296,"family":"QueuePad","materialKey":"atlas"},"dbf8d085e907df65f973015f64c45ebcc0e4b98fd406ae9f513b66796a0c1e68":{"triangles":972,"family":"R4BalloonBouquet","materialKey":"atlas"},"cdcaa2ec2bb171ce7fecb44c0cddfab95f1659eaff5b7d585a44bdff6c1f0b2f":{"triangles":48,"family":"R4BayFluorescent","materialKey":"atlas"},"d2688707ef69774c969350011fba888a1f8a1be9527b32f4b03629fcfac1a38c":{"triangles":48,"family":"R4BayFluorescentDead","materialKey":"atlas"},"8148fe3cb8068bc97fccc5837e3d32d1f935bfa3e2776a54b141e90ca650aae7":{"triangles":624,"family":"R4MonitorArm","materialKey":"atlas"},"fa1f756cacc21c9fe9b0047a10b6fdea065449704487acd247439f9f8f9f2621":{"triangles":168,"family":"R4PartyChair","materialKey":"atlas"},"ffe25eb7d6003730734fb4928ccf76c79fcf3fb8406a5340b39621cac31fa764":{"triangles":24,"family":"R4PoolCeilingPanel","materialKey":"atlas"},"cdf8b14a6e73ff6f6e5cac4c63354519d3e364cf91a43b3394be62d5a8c2f596":{"triangles":400,"family":"R4WallMonitor","materialKey":"atlas"},"d837638634f5ce7d3b604512109c70785fd305fef8ce26c2ec5fd750e8a86226":{"triangles":60,"family":"RevisionPlaque","materialKey":"atlas"},"60b873c067fd80f128244c24cd19bea69e0fec90e1c6aee99d8f8bfde6aea977":{"triangles":12,"family":"RoadSection","materialKey":"asphalt_road"},"fcd1f72f954a9e530ccfad6e001607cf98bc618e62bd0ecad361013f7a9f53db":{"triangles":72,"family":"RoadSection","materialKey":"atlas"},"47bf1f6e72409b9e6eba42e23c4ce814f7c6396322a49df7bf0c4747ec32eb2d":{"triangles":2064,"family":"RolledCarpet","materialKey":"atlas"},"97d333e467c25ee9522bfbb4de9c33377d4e120fc895a2416fa9b9054c4b9a78":{"triangles":96,"family":"ServicePanel","materialKey":"atlas"},"9f1e2113cecb2fb4697f28fbd3088ba3981cddd9ad72c98564730ecdbe17e50f":{"triangles":936,"family":"SidewalkSection","materialKey":"atlas"},"0b93fdee5bc9878d5612839f431de1512e12b4784f6dc4bb2ea5d33bc17ddb6c":{"triangles":12,"family":"SidewalkSection","materialKey":"sidewalk_concrete"},"93c3bc1cc245a2c133c401b8c62705047ee5eb64a95fe4ec16384334e7644867":{"triangles":1456,"family":"Sofa","materialKey":"atlas"},"d3eefb38efa601e197542c8880effd16a75f6998a4f817330ac24f387116bc5b":{"triangles":5820,"family":"SpeakerTower","materialKey":"atlas"},"48d044236144e30f0b51fcafe6caa6ade3d1911cb7c9f1ae05c060516c9b6768":{"triangles":584,"family":"StackChair","materialKey":"atlas"},"4cd0e4519b98145708fa01335a20cf3f2645d2f82190b5a75290bbeed3170afe":{"triangles":168,"family":"StageDeck","materialKey":"atlas"},"b652c9f2b74defbcbb49ca88eb2483b3a916fa5d3626537646b1f7e5ee2492ff":{"triangles":84,"family":"StageRearRail","materialKey":"atlas"},"46f58ad4848c1f388a9f7395f877bf5b466f765c0daa64ce7bdb8cc37f4e7585":{"triangles":1088,"family":"Subwoofer","materialKey":"atlas"},"e3bfa054afc58b3311d4c86bc24455e96438b1e34ec3f8d5d835261bf0baf041":{"triangles":808,"family":"VinylBench","materialKey":"atlas"},"874791722d46919b20dbdcc888f5046bce4f8b6befca9d16e9e43d284af19022":{"triangles":2824,"family":"VinylDiscAmber","materialKey":"atlas"},"2c11ebc9910adc40cb0da8e4b60f96e7680cc42a39d7039fb8afc34759c06610":{"triangles":2824,"family":"VinylDiscCyan","materialKey":"atlas"},"e44c6150a79de2e6056db08ff7d94c5c7e9437f015a6122aa4a1e44c8630f375":{"triangles":1660,"family":"WireTrolley","materialKey":"atlas"}}]====])
local SINGLE_SIDED = HS:JSONDecode([====[{"7b2d07b7259b203e09f73740121c7d0c724bcb608cb31abee921984893f6343c":true,"7c2f1f5d548079bc9fcc931d119ca031fe5f4d555c93383c6dd6ac2e2c87acd3":true,"58e5c270565634f44f7b92c1ce8b6bfc0829bdce661020b8f464e283cc9ea00a":true,"6e070bf7b7c93e2ec92f6c4d4dfc5fc0ef79013032389a650dc12b1382f95489":true,"1be89dbe7c69540d2ebfbf45a4665c9dc142fca1f3c1cc13b8ecade45dad3280":true,"16c50be3a839ee03c29c612b9e419b35e8ed1f009695498e2e319518f6fff4e0":true,"7a275038047f2e35b965399c3eebcd20c87dbb0c2e71c70ea6b9ae585e0194fe":true,"3fe5312cd0df0685b716711b7d21a639dc2689de658d7e056259dbce63f36dfa":true,"97c5785663a278e47079f3f3f77e4ee3cebff53536bd27a695c7524aa60a3a7c":true,"073da62fe36da9b2acecbc4800429aa59d345539f6e6579310ae0ca944a60d92":true,"36dac2219cba2d5e7ae6c316e95c8f2ca21596b1a6dfeee513edbc572e436581":true,"2db1cf899791e947832f8aa5ae3c59c169e935082e9a3e57f2b8adbf43f2a5cc":true,"2b34725771bc4955f45fb2fb31d3afd7b28d27e336a7f0ffccb874320585f7d4":true,"50ead2ee2a92ce5defff88ff080654cca0a4d76b904dc2ac3e7204327ad13a37":true,"fcbdeb2990bc6636d96917de907649c7e9a0a5c6ce0545f567a2421d415af6e1":true,"658de91e76fc530a9638599228ec9f58e99350bd43efe2323436ab46f8759f7c":true,"cf3ca7ebc2348eecf15cd5f00fcd3757f87f598e110b7fd4118dee6672b1c50c":true,"e1562e1f73866821c7e839995d247fe60ed9ae99e0009a1cd1deb4a3c77a5d4a":true,"e011e9a58bcf1f1f35dad9a0fe0428c261b1eb225da1f6fe150df31e538a02b8":true,"2169ee7d0e13a66dec43f64f583ee60f1648316479163768c35b866e3237a0a2":true,"ac183c29110ca84341fa7a3a06305f3962afe292b0fb3978d381063e1e4571d4":true,"7529cefda616e1166042a4f42ef80c954c924aef56e9c56fb247a9d0e7ee6790":true,"e47d5f462c48e7f6736404e68aa74d108193d68c01b064a0944388b52130e0c6":true,"769b2ad03f3fa76b37c4e9ddbaf2cc906c1f666ab979dda58d5cd22278915c9a":true,"50da54e7952a0e7156ddf1b4d2e00aefc2cbf5b3e4c7a27b00d3d5628b3eb985":true,"ed1d36cddded465da8a426f7bbadbb3658f7e798ab4c69b3aadea0145704a891":true,"308fc0df28a38fe2e4b5385e5db5379ad46ee57b48ac4a09e0e2ab237b0de6a8":true,"ad9efe2e7d9461855d9934e903dbfc960833ca60c832d51f367009e8cfd11c11":true,"5fd63320b807d4eb6d155233f729852e796c7155fb63b47e57497c3ad13b532d":true,"601a13b055c3c1e98a1f5ab6bbb6d37aa99bdaee2b1feb0542d4f7fdd29e7275":true,"779fb1d6b6a931ee1dac4dc6de4f22948e94905a1d5d592e651f627fd9ef9829":true,"dbf8d085e907df65f973015f64c45ebcc0e4b98fd406ae9f513b66796a0c1e68":true,"cdcaa2ec2bb171ce7fecb44c0cddfab95f1659eaff5b7d585a44bdff6c1f0b2f":true,"d2688707ef69774c969350011fba888a1f8a1be9527b32f4b03629fcfac1a38c":true,"8148fe3cb8068bc97fccc5837e3d32d1f935bfa3e2776a54b141e90ca650aae7":true,"fa1f756cacc21c9fe9b0047a10b6fdea065449704487acd247439f9f8f9f2621":true,"ffe25eb7d6003730734fb4928ccf76c79fcf3fb8406a5340b39621cac31fa764":true,"cdf8b14a6e73ff6f6e5cac4c63354519d3e364cf91a43b3394be62d5a8c2f596":true,"d837638634f5ce7d3b604512109c70785fd305fef8ce26c2ec5fd750e8a86226":true,"60b873c067fd80f128244c24cd19bea69e0fec90e1c6aee99d8f8bfde6aea977":true,"fcd1f72f954a9e530ccfad6e001607cf98bc618e62bd0ecad361013f7a9f53db":true,"97d333e467c25ee9522bfbb4de9c33377d4e120fc895a2416fa9b9054c4b9a78":true,"9f1e2113cecb2fb4697f28fbd3088ba3981cddd9ad72c98564730ecdbe17e50f":true,"0b93fdee5bc9878d5612839f431de1512e12b4784f6dc4bb2ea5d33bc17ddb6c":true,"4cd0e4519b98145708fa01335a20cf3f2645d2f82190b5a75290bbeed3170afe":true,"b652c9f2b74defbcbb49ca88eb2483b3a916fa5d3626537646b1f7e5ee2492ff":true}]====])
local AUTOMATIC = HS:JSONDecode([====[{"7b2d07b7259b203e09f73740121c7d0c724bcb608cb31abee921984893f6343c":true,"e1562e1f73866821c7e839995d247fe60ed9ae99e0009a1cd1deb4a3c77a5d4a":true,"dbf8d085e907df65f973015f64c45ebcc0e4b98fd406ae9f513b66796a0c1e68":true,"8148fe3cb8068bc97fccc5837e3d32d1f935bfa3e2776a54b141e90ca650aae7":true,"9f1e2113cecb2fb4697f28fbd3088ba3981cddd9ad72c98564730ecdbe17e50f":true}]====])
local CONTENT_PROPERTY = {color="ColorMapContent", normal="NormalMapContent", roughness="RoughnessMapContent"}

local function uri(content)
	assert(typeof(content)=="Content" and content.SourceType==Enum.ContentSourceType.Uri,"Unpublished static material content")
	assert(content.Uri:match("^rbxassetid://[1-9]%d*$"),"Static material must use a published URI")
	return content.Uri
end

local function appearances(part)
	local result={}
	for _,child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceAppearance") then table.insert(result,child) end
	end
	return result
end

local function furnitureOwner(part,root)
	local cursor=part
	while cursor and cursor~=root do
		if (cursor.Name:match("^South Embedded 0[678]%-") or cursor.Name:match("^NorthDJ Embedded 0[678]%-"))
			and (cursor:GetAttribute("EndClutterFamily")=="FilingCabinet" or cursor:GetAttribute("EndClutterFamily")=="Desk"
				or cursor:GetAttribute("EndClutterFamily")=="Sofa" or cursor:GetAttribute("EndClutterFamily")=="VinylBench") then
			return cursor
		end
		cursor=cursor.Parent
	end
	return nil
end

local function tintFor(part,root,key)
	if key=="asphalt_road" then return Color3.new(1,1,1) end
	local p=root:GetPivot():PointToObjectSpace(part.Position)
	local minimum=key=="tunnel_concrete" and .947 or .97
	local value=minimum+(1-minimum)*(.5+.5*math.sin(p.X*.173+p.Z*.087+part.Size.Y*.37))
	return Color3.new(value,value,value)
end

function Module.AssetSpec()
	-- Read-only contract for the guarded Edit installer; IDs must be uploaded,
	-- pinned and represented by matching static templates before Apply can run.
	return HS:JSONDecode(HS:JSONEncode(SPEC))
end

function Module.Apply(root,options)
	options=options or {}
	assert(not RunService:IsClient(),"R4 material polish is server-only")
	assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and game.CreatorId==1039373905,"Wrong material polish place/owner")
	assert(script:GetAttribute(OWNED)==true,"Unowned material helper")
	assert(root and root:IsA("Model") and root.Name=="LobbyReimaginedPreview" and root:GetAttribute(OWNED)==true,"Unowned R4 model")
	assert(root:GetAttribute("LobbyVisualRevision")==4 and root:GetAttribute("IsolatedDesignPreview")==true
		and root:GetAttribute("PreviewCenter")==Vector3.new(220,30,-760),"Wrong R4 visual baseline")
	assert(root.Parent==nil or root.Parent==workspace,"Wrong R4 model parent")
	local previous=root:GetAttribute("MaterialPolishRevision")
	if previous then
		assert(previous==REVISION,"Conflicting R4 material revision")
		return {AlreadyApplied=true,Revision=previous}
	end
	assert(options.OptimizeBackfaces==nil or type(options.OptimizeBackfaces)=="boolean","Invalid backface option")
	assert(options.AutomaticFidelity==nil or type(options.AutomaticFidelity)=="boolean","Invalid fidelity option")
	local source=assert(SS:FindFirstChild("LobbyReimaginedBlenderSource20261001R4"),"R4 raw source missing")
	assert(source:GetAttribute(OWNED)==true and source:GetAttribute("Ready")==true
		and source:GetAttribute("ManifestSHA256")==BASELINE,"Material baseline manifest changed")
	local folder=assert(script:FindFirstChild("StaticPBRMaterials"),"Publish and install static polish material templates first")
	assert(folder:IsA("Folder") and folder:GetAttribute(OWNED)==true and folder:GetAttribute("Ready")==true,"Incomplete polish materials")
	assert(#folder:GetChildren()==3,"Expected exactly three polish PBR templates")
	local templates={}
	for key,mapSpec in pairs(SPEC.materials) do
		local template=assert(folder:FindFirstChild(key),"Missing material template "..key)
		assert(template:IsA("SurfaceAppearance") and template:GetAttribute(OWNED)==true
			and template.AlphaMode==Enum.AlphaMode.Overlay and template.Color==Color3.new(1,1,1),"Invalid polish template "..key)
		assert(template.MetalnessMapContent.SourceType==Enum.ContentSourceType.None,"Concrete/asphalt must be dielectric")
		for role,property in pairs(CONTENT_PROPERTY) do
			assert(template:GetAttribute(role.."PNG_SHA256")==mapSpec[role].pngSHA256,"Candidate PNG hash changed "..key.."/"..role)
			uri(template[property])
		end
		templates[key]=template
	end
	local atlas=assert(script:FindFirstChild("SidewalkAtlas"),"Published sidewalk-specific atlas missing")
	assert(atlas:IsA("StringValue") and atlas:GetAttribute(OWNED)==true and atlas.Value:match("^[1-9]%d*$")
		and atlas:GetAttribute("PNG_SHA256")==SPEC.sidewalkAtlas.pngSHA256,"Invalid sidewalk-specific atlas")
	local visuals=assert(root:FindFirstChild("BlenderVisuals"),"Missing owned R4 visuals")
	local pbr,sidewalk,furniture,backfaces,fidelity={},{},{},{},{}
	for _,part in ipairs(visuals:GetDescendants()) do
		if part:IsA("MeshPart") and part:GetAttribute(OWNED)==true then
			local hash=part:GetAttribute("BlenderSourceSHA256")
			local chunk=KNOWN[hash]
			if chunk then
				assert(part:GetAttribute("BlenderTriangles")==chunk.triangles,"Material mesh metadata changed")
				local key=part:GetAttribute("LobbyR4PBRMaterial")
				if key then
					assert(key==chunk.materialKey and templates[key],"Material key differs from verified chunk")
					local existing=appearances(part)
					assert(#existing==1 and existing[1]:GetAttribute(OWNED)==true,"Unexpected PBR child set")
					local old=existing[1]
					for role,property in pairs(CONTENT_PROPERTY) do
						assert(uri(old[property])==SPEC.materials[key][role].originalURI,"Original PBR references changed; inspect fresh baseline")
					end
					table.insert(pbr,{part=part,old=old,key=key})
				elseif hash==SPEC.sidewalkAtlas.chunkSHA256 then
					assert(#appearances(part)==0,"Unexpected sidewalk atlas PBR")
					table.insert(sidewalk,part)
				end
				local owner=furnitureOwner(part,root)
				if owner then table.insert(furniture,{part=part,owner=owner}) end
				-- Mesh hashes were checked against manifold/winding/normal proofs.
				-- Open holograms and inconsistent furniture are deliberately absent.
				if options.OptimizeBackfaces and SINGLE_SIDED[hash] and not part:GetAttribute("PreviewVinylDisc") then table.insert(backfaces,part) end
				if options.AutomaticFidelity and AUTOMATIC[hash] and not part:GetAttribute("PreviewVinylDisc") then table.insert(fidelity,part) end
			end
		end
	end
	assert(#pbr>=7 and #sidewalk==14,"Expected R4 roadway/sidewalk mesh set changed")
	-- Validate the complete scope first. Only runtime clones of owned appearances
	-- are replaced; original raw templates and shared atlas remain untouched.
	for _,row in ipairs(pbr) do
		local replacement=templates[row.key]:Clone()
		replacement.Color=tintFor(row.part,root,row.key)
		replacement:SetAttribute("MaterialPolishRevision",REVISION)
		replacement.Parent=row.part
		row.old:Destroy()
		row.part:SetAttribute("MaterialPolishRevision",REVISION)
	end
	local atlasContent=Content.fromAssetId(tonumber(atlas.Value))
	for _,part in ipairs(sidewalk) do part.TextureContent=atlasContent;part:SetAttribute("MaterialPolishRevision",REVISION) end
	for _,row in ipairs(furniture) do
		local p=root:GetPivot():PointToObjectSpace(row.owner:GetPivot().Position)
		local value=.94+.06*(.5+.5*math.sin(p.X*.39+p.Y*.53+p.Z*.17))
		row.part.Color=Color3.new(value,value,value)
		row.part:SetAttribute("MaterialPolishFurnitureTint",value)
	end
	for _,part in ipairs(backfaces) do part.DoubleSided=false;part:SetAttribute("MaterialPolishClosedMesh",true) end
	for _,part in ipairs(fidelity) do part.RenderFidelity=Enum.RenderFidelity.Automatic end
	root:SetAttribute("MaterialPolishRevision",REVISION)
	root:SetAttribute("MaterialPolishPBRCount",#pbr)
	root:SetAttribute("MaterialPolishJointAtlasCount",#sidewalk)
	root:SetAttribute("MaterialPolishFurnitureCount",#furniture)
	root:SetAttribute("MaterialPolishSingleSidedCount",#backfaces)
	root:SetAttribute("MaterialPolishAutomaticCount",#fidelity)
	return {Revision=REVISION,PBR=#pbr,SidewalkAtlas=#sidewalk,FurnitureTints=#furniture,
		SingleSided=#backfaces,Automatic=#fidelity,RequiresPlayVerification=true}
end

return Module
