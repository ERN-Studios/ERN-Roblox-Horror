"""Build reviewable scoped pricing proposals from the fresh Studio audit export.

This script never connects to Studio. The parent applies its exact replacements
against a newly checked live Source/editor baseline.
"""
import difflib
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
AUDIT = ROOT.parent / "audit/live-sources"
entries = []

def propose(name, replacements):
    before = (AUDIT / name).read_text()
    after = before
    for change in replacements:
        old, new = change["old"], change["new"]
        assert after.count(old) == 1, (name, change["purpose"], after.count(old))
        after = after.replace(old, new, 1)
    (ROOT / "proposed-after").mkdir(exist_ok=True)
    (ROOT / "proposed-after" / name).write_text(after)
    (ROOT / (name + ".diff")).write_text("".join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile="live-before/" + name, tofile="proposed-after/" + name)))
    path, class_name = name.removesuffix(".luau").rsplit(".", 1)
    entries.append({"path": path, "class": class_name, "beforeSourceSHA256": hashlib.sha256(before.encode()).hexdigest(), "afterSourceSHA256": hashlib.sha256(after.encode()).hexdigest(), "beforeSourceBytes": len(before.encode()), "afterSourceBytes": len(after.encode()), "replacements": replacements})

earner_old = '''-- Sale state is Roblox's: a pass that is off sale (all six are until QA) or not
-- at its approved price shows COMING SOON, never a BUY that cannot complete.
shopDetail.EarnerForSale = {}
function shopDetail.renderEarner()
	local earner = Config.TokenEarner
	local owns = {}
	for key in pairs(earner.Passes) do owns[key] = player:GetAttribute("ZyntraOwns" .. key) == true end
	for tier, item in pairs(shopDetail.TokenEarner) do
		local key = "TokenEarner" .. tier .. "x"
		local itemButton = productButtons[key]
		local offer = earner.Offer(earner.Passes, earner.Tier, owns, tier)
		local pass = offer and earner.Passes[offer]
		local onSale = pass ~= nil and shopDetail.EarnerForSale[pass.Id] == true
		item.Id = onSale and pass.Id or 0
		if pass then item.Price = pass.Price; displayedProductPrices[key] = pass.Price end
		itemButton.Text = not pass and "OWNED" or onSale and (tostring(pass.Price) .. " R$") or "COMING SOON"
		itemButton.TextColor3 = not pass and COLORS.accent or onSale and COLORS.accent2 or COLORS.muted
		UIDevice.SetEnabled(itemButton, onSale)
		if shopDetail.priceChanged then shopDetail.priceChanged(key) end
	end
end
task.spawn(function()
	for _, pass in pairs(Config.TokenEarner.Passes) do
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass.Id, Enum.InfoType.GamePass)
		shopDetail.EarnerForSale[pass.Id] = ok and type(info) == "table" and info.IsForSale == true
			and info.PriceInRobux == pass.Price
	end
	shopDetail.renderEarner()
end)
'''

earner_new = '''-- Managed Pricing can return a different price for each player. Only verified
-- on-sale offers enter this client price table; the configured base catalogue
-- and its ownership/prerequisite rules remain unchanged.
shopDetail.EarnerLivePasses = {}
shopDetail.EarnerPricesPending = true
local function verifiedEarnerPrice(info, expectedId)
	if type(info) ~= "table" or info.IsForSale ~= true or info.TargetId ~= expectedId then return nil end
	local price = info.PriceInRobux
	if type(price) ~= "number" or price ~= price or price <= 0
		or price == math.huge or price % 1 ~= 0 then return nil end
	return price
end
function shopDetail.renderEarner()
	local earner = Config.TokenEarner
	local owns = {}
	for key in pairs(earner.Passes) do owns[key] = player:GetAttribute("ZyntraOwns" .. key) == true end
	local ownedTier = earner.Tier(owns)
	for tier, item in pairs(shopDetail.TokenEarner) do
		local key = "TokenEarner" .. tier .. "x"
		local itemButton = productButtons[key]
		local reached = ownedTier >= tier
		local offer = not reached and earner.Offer(shopDetail.EarnerLivePasses, earner.Tier, owns, tier) or nil
		local pass = offer and shopDetail.EarnerLivePasses[offer]
		local onSale = pass ~= nil
		item.Id = onSale and pass.Id or 0
		if pass then item.Price = pass.Price; displayedProductPrices[key] = pass.Price end
		itemButton.Text = reached and "OWNED" or onSale and (tostring(pass.Price) .. " R$")
			or shopDetail.EarnerPricesPending and "CHECKING PRICE" or "UNAVAILABLE"
		itemButton.TextColor3 = reached and COLORS.accent or onSale and COLORS.accent2 or COLORS.muted
		UIDevice.SetEnabled(itemButton, onSale)
		if shopDetail.priceChanged then shopDetail.priceChanged(key) end
	end
end
shopDetail.renderEarner()
task.spawn(function()
	for key, pass in pairs(Config.TokenEarner.Passes) do
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass.Id, Enum.InfoType.GamePass)
		local price = ok and verifiedEarnerPrice(info, pass.Id) or nil
		if price then
			local offer = table.clone(pass)
			offer.Price = price
			shopDetail.EarnerLivePasses[key] = offer
		end
	end
	shopDetail.EarnerPricesPending = false
	shopDetail.renderEarner()
end)
'''
propose("StarterPlayer.StarterPlayerScripts.ZyntraStore.LocalScript.luau", [{"purpose": "Use verified client-specific on-sale prices for Token Earner display and cheapest valid offers without changing Config, ownership, or purchase IDs.", "old": earner_old, "new": earner_new}])

skin_old = '''	return ok and type(info) == "table" and info.IsForSale == true
		and info.PriceInRobux == item.RobuxPrice
'''
skin_new = '''	if not ok or type(info) ~= "table" or info.IsForSale ~= true or info.TargetId ~= id then return false end
	local price = info.PriceInRobux
	if type(price) ~= "number" or price ~= price or price <= 0
		or price == math.huge or price % 1 ~= 0 then return false end
	return true, price
'''
propose("ReplicatedStorage.ZyntraSkinsPage.ModuleScript.luau", [
    {"purpose": "Accept a verified positive regional skin pass price instead of requiring base-price equality.", "old": skin_old, "new": skin_new},
    {"purpose": "Keep resolved skin prices in client state without mutating the suit catalogue.", "old": "\tlocal paidVerified = {}\n", "new": "\tlocal paidVerified = {}\n\tlocal paidPrices = {}\n"},
    {"purpose": "Display the player's actual skin pass price only after successful validation, with accurate pending/error state.", "old": '''				entry.Meta.Text = ("%d R$"):format(item.RobuxPrice)
				canAct = paidVerified[skinId] == true
''', "new": '''				canAct = paidVerified[skinId] == true
				entry.Meta.Text = canAct and ("%d R$"):format(paidPrices[skinId])
					or paidVerified[skinId] == nil and "CHECKING PRICE" or "PRICE UNAVAILABLE"
'''},
    {"purpose": "Capture both validation and resolved price from the same Marketplace request.", "old": '''	-- Price and availability are checked with Roblox before a paid prompt can
	-- open. A missing ID, network error, or price mismatch leaves it disabled.
''', "new": '''	-- Each player's price and availability are read from Roblox before a paid
	-- prompt can open. Invalid IDs, unavailable prices and network errors disable it.
'''},
    {"purpose": "Store the resolved price alongside the on-sale verification result.", "old": "\t\t\t\tpaidVerified[skinId] = allowedRobuxPass(item)\n", "new": "\t\t\t\tpaidVerified[skinId], paidPrices[skinId] = allowedRobuxPass(item)\n"},
])

(ROOT / "exact-replacements.json").write_text(json.dumps({"authority": "Review-only proposals from fresh Studio Sources; no Studio write performed", "placeId": 131311258779917, "universeId": 10559217407, "scripts": entries}, indent=2))
print(json.dumps([{key: value for key, value in entry.items() if key != "replacements"} for entry in entries], indent=2))
