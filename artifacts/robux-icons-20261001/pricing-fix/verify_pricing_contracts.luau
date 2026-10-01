-- Execute committed verified Studio UI pricing functions and unchanged production
-- catalogue rules against bounded region/ownership/sale-state matrices.
-- No Studio connection, purchase prompt, data store, or network call.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")
local process = require("@lune/process")
local root = "artifacts/robux-icons-20261001/pricing-fix"
local audit = "artifacts/robux-icons-20261001/audit/live-sources"
-- Run from the repository root. Argument 1 may override the recorded mirror;
-- argument 2 may override the JSON report path. Neither needs transient proposals.
local verifiedMirror = process.args[1] or "artifacts/robux-icons-20261001/verified-studio-mirror"
local configSource = fs.readFile(verifiedMirror .. "/ReplicatedStorage/ZyntraConfig.ModuleScript.luau")
local skinCatalogueSource = fs.readFile(audit .. "/ReplicatedStorage.ZyntraSkins.ModuleScript.luau")
local config = luau.load("return function(Color3)\n" .. configSource .. "\nend")()(rbx.Color3)
local skins = luau.load(skinCatalogueSource)()
local configBefore = serde.encode("json", config.TokenEarner.Passes)
local storeSource = fs.readFile(verifiedMirror .. "/StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.luau")
local skinSource = fs.readFile(verifiedMirror .. "/ReplicatedStorage/ZyntraSkinsPage.ModuleScript.luau")
luau.compile(storeSource)
luau.compile(skinSource)

local validationText = assert(storeSource:match("(local function verifiedEarnerPrice.-\nend)\nfunction shopDetail%.renderEarner"))
local validate = luau.load(validationText .. "\nreturn verifiedEarnerPrice")()
local earnerRenderText = assert(storeSource:match("(function shopDetail%.renderEarner%(%)\n.-\nend)\nshopDetail%.renderEarner%(%).*task%.spawn"))
local earnerRenderFactory = luau.load([[return function(shared)
local Config, shopDetail, player = shared.Config, shared.shopDetail, shared.player
local productButtons, displayedProductPrices = shared.buttons, shared.prices
local COLORS = {accent="owned", accent2="buy", muted="disabled"}
local UIDevice = {SetEnabled=function(button, value) button.Active=value end}
]] .. earnerRenderText .. "\nreturn shopDetail.renderEarner end")()

local skinValidationText = assert(skinSource:match("(local function allowedRobuxPass.-\nend)\n\nfunction Page%.mount"))
local skinValidationFactory = luau.load([[return function(provider)
local MarketplaceService={GetProductInfo=function(_, id, kind) return provider(id,kind) end}
local Enum={InfoType={GamePass="GamePass"}}
]] .. skinValidationText .. "\nreturn allowedRobuxPass end")()
local skinRenderText = assert(skinSource:match("(local function render%(%)\n.-\n\tend)\n\n\tlocal stopProfile"))
local skinRenderFactory = luau.load([[return function(shared)
local ctx, Skins, entries = shared.ctx, shared.Skins, shared.entries
local paidVerified, paidPrices = shared.verified, shared.prices
local previewStatus, selectedSkinId = shared.previewStatus, shared.selectedSkinId
local ink, muted = "enabled", "disabled"
]] .. skinRenderText .. "\nreturn render end")()

local report = {compiledScripts=2, validators=0, earnerRows=0, skinRows=0, cases={}, productionFunctionsExecuted=true,
	sourceOrigin = if process.args[1] then "Explicit Source mirror override" else "Actual verified Studio native-after Sources",
	sourceMirror = verifiedMirror,
	sourceSHA256 = {config = serde.hash("sha256", configSource), store = serde.hash("sha256", storeSource),
		skinsPage = serde.hash("sha256", skinSource)}}
local keys = {"TokenEarner2x", "TokenEarner3x", "TokenEarner5x", "TokenEarnerUp2to3", "TokenEarnerUp3to5", "TokenEarnerUp2to5"}
local function check(condition, message) assert(condition, message) end
local function ownership(mask)
	local owns = {}
	for index,key in keys do if bit32.band(mask, bit32.lshift(1,index-1)) ~= 0 then owns[key]=true end end
	return owns
end
local scenarios = {
	{name="base", price=function(base) return base end},
	{name="regional_half", price=function(base) return math.max(1,math.floor(base*.5)) end},
	{name="pinned_price_10", price=function() return 10 end},
	{name="reordered_region_prices", price=function(base,key) return key=="TokenEarner5x" and 7 or base+31 end},
	{name="partial_off_sale", price=function(base,key) if key=="TokenEarner3x" then return nil end; return base end},
	{name="all_unavailable", price=function() return nil end},
	{name="pending", pending=true, price=function() return nil end},
}
for _, scenario in scenarios do
	for mask=0,63 do
		local owns = ownership(mask)
		local live = {}
		for key,pass in config.TokenEarner.Passes do
			local price = scenario.price(pass.Price,key)
			if price then local item=table.clone(pass); item.Price=price; live[key]=item end
		end
		local buttons,prices,detail = {},{}, {TokenEarner={},EarnerLivePasses=live,EarnerPricesPending=scenario.pending==true}
		for _,tier in {2,3,5} do
			local key="TokenEarner"..tier.."x"
			buttons[key]={Active=true}
			detail.TokenEarner[tier]={Id=0,Price=config.TokenEarner.Passes[key].Price}
		end
		local player={GetAttribute=function(_,attribute) return owns[attribute:sub(#"ZyntraOwns"+1)]==true end}
		local render=earnerRenderFactory({Config=config,shopDetail=detail,player=player,buttons=buttons,prices=prices})
		render()
		for _,target in {2,3,5} do
			local key="TokenEarner"..target.."x"
			local item,button=detail.TokenEarner[target],buttons[key]
			local reached=config.TokenEarner.Tier(owns)>=target
			local minimum
			for candidate,pass in live do
				local trial=table.clone(owns); trial[candidate]=true
				if not owns[candidate] and config.TokenEarner.Tier(trial)>=target then minimum=math.min(minimum or math.huge,pass.Price) end
			end
			if reached then
				check(button.Text=="OWNED" and button.Active==false and item.Id==0,"Owned tiers must stay owned without price availability")
			elseif minimum then
				check(button.Active==true and item.Id>0,"Available regional offer should be enabled")
				check(item.Price==minimum and prices[key]==minimum and button.Text==tostring(minimum).." R$","Card and detail must use the actual cheapest valid price")
				local selected
				for candidate,pass in live do if pass.Id==item.Id then selected=candidate end end
				check(selected~=nil and not owns[selected],"Offer must be a known unowned on-sale pass ID")
				local trial=table.clone(owns);trial[selected]=true
				check(config.TokenEarner.Tier(trial)>=target,"Every offered upgrade must satisfy its prerequisites")
			else
				check(button.Active==false and item.Id==0,"Pending/unavailable prices must not prompt a purchase")
				check(button.Text==(scenario.pending and "CHECKING PRICE" or "UNAVAILABLE"),"Unavailable must not be mislabeled OWNED")
			end
			report.earnerRows+=1
		end
	end
	table.insert(report.cases,scenario.name)
end

for _,case in {
	{name="valid_region", info={TargetId=42,IsForSale=true,PriceInRobux=17},expected=17},
	{name="sale_false",info={TargetId=42,IsForSale=false,PriceInRobux=17}},
	{name="wrong_id",info={TargetId=43,IsForSale=true,PriceInRobux=17}},
	{name="missing_id",info={IsForSale=true,PriceInRobux=17}},
	{name="zero",info={TargetId=42,IsForSale=true,PriceInRobux=0}},
	{name="negative",info={TargetId=42,IsForSale=true,PriceInRobux=-2}},
	{name="fractional",info={TargetId=42,IsForSale=true,PriceInRobux=2.5}},
	{name="infinite",info={TargetId=42,IsForSale=true,PriceInRobux=math.huge}},
	{name="nan",info={TargetId=42,IsForSale=true,PriceInRobux=0/0}},
	{name="string",info={TargetId=42,IsForSale=true,PriceInRobux="17"}},
	{name="missing_price",info={TargetId=42,IsForSale=true}},
} do
	check(validate(case.info,42)==case.expected,"Earner validation: "..case.name)
	local skinValidator=skinValidationFactory(function(id,kind)check(id==42 and kind=="GamePass","Skin metadata requested with wrong ID/type");return case.info end)
	local ok,price=skinValidator({PassId=42,RobuxPrice=99})
	check(ok==(case.expected~=nil) and price==case.expected,"Skin validation: "..case.name)
	report.validators+=2
end
local failingSkin=skinValidationFactory(function()error("test network failure")end)
check(failingSkin({PassId=42,RobuxPrice=99})==false,"Network failure must disable the paid skin")
report.validators+=1

for _,case in {
	{name="regional",verified={StaticWraith=true,FalseSun=true},prices={StaticWraith=37,FalseSun=51},owned={}},
	{name="base",verified={StaticWraith=true,FalseSun=true},prices={StaticWraith=99,FalseSun=149},owned={}},
	{name="pending",verified={},prices={},owned={}},
	{name="unavailable",verified={StaticWraith=false,FalseSun=false},prices={},owned={}},
	{name="owned_without_metadata",verified={},prices={},owned={StaticWraith=true,FalseSun=true}},
} do
	local entries={}
	for _,skinId in skins.Order do entries[skinId]={Meta={},Action={}} end
	local profile={Tokens=0,CompletedLevels=0,Skins={Owned=case.owned,Equipped="BaselineYellow"}}
	local ctx={profile=function()return profile end,UIDevice={SetEnabled=function(button,value)button.Active=value end}}
	local previewStatus={}
	local render=skinRenderFactory({ctx=ctx,Skins=skins,entries=entries,verified=case.verified,prices=case.prices,previewStatus=previewStatus,selectedSkinId="StaticWraith"})
	render()
	for _,skinId in {"StaticWraith","FalseSun"} do
		local entry=entries[skinId]
		if case.owned[skinId] then
			check(entry.Meta.Text=="OWNED" and entry.Action.Text=="EQUIP" and entry.Action.Active==true,"Owned suit equip must not require price availability")
		elseif case.verified[skinId]==true then
			check(entry.Meta.Text==tostring(case.prices[skinId]).." R$" and entry.Action.Text=="BUY" and entry.Action.Active==true,"Paid suit must show actual verified regional price")
		else
			check(entry.Action.Active==false and entry.Action.Text=="UNAVAILABLE","Unverified suit must not prompt")
			check(entry.Meta.Text==(case.verified[skinId]==nil and "CHECKING PRICE" or "PRICE UNAVAILABLE"),"Skin metadata status must be accurate")
		end
		report.skinRows+=1
	end
	check(previewStatus.Text==entries.StaticWraith.Meta.Text.." · "..entries.StaticWraith.Action.Text,"3D preview must mirror the same actual price/ownership state")
end
check(serde.encode("json",config.TokenEarner.Passes)==configBefore,"Client regional offers must not mutate the base catalogue")
check(config.TokenEarner.Tier({TokenEarner2x=true,TokenEarner3x=true,TokenEarner5x=true})==5,"Token tiers must never stack")
check(config.TokenEarner.Tier({TokenEarnerUp2to5=true})==1,"Unqualified upgrade must not grant a tier")
report.baseCatalogueUnchanged=true
report.prerequisiteAndNonStackingChecks=true
report.status="passed"
fs.writeFile(process.args[2] or root.."/actual-source-contract-test-results.json",serde.encode("json",report,true))
print(serde.encode("json",report,true))
