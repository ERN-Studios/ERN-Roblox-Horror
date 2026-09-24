-- ZyntraSkins: the fixed cosmetic catalogue and pure profile transforms.
-- No client value may choose a price, grant ownership, or name a paid product.
-- DataStore writes and Roblox receipts remain owned by ZyntraMonetization.

local Skins = {}

Skins.DefaultId = "BaselineYellow"
Skins.WheelEligible = {"PoolService", "SuburbSurvey"}
Skins.Order = {
	"BaselineYellow",
	"PoolService",
	"SuburbSurvey",
	"BlacksiteDirector",
	"StaticWraith",
	"FalseSun",
}

Skins.ById = {
	BaselineYellow = {
		Name = "Baseline Yellow", Kind = "Free", ImageId = 113696916548555,
		PreviewImageId = 108962875803884,
		Description = "The standard Zyntra hazmat suit.",
	},
	PoolService = {
		Name = "Pool Service", Kind = "Tokens", TokenCost = 25,
		ImageId = 71321355623557, PreviewImageId = 113105840961412,
		Description = "A worn pool-crew suit earned with Research Tokens.",
	},
	SuburbSurvey = {
		Name = "Suburb Survey", Kind = "Tokens", TokenCost = 75,
		ImageId = 81335744794900, PreviewImageId = 105515413111120,
		Description = "A survey suit earned with Research Tokens.",
	},
	BlacksiteDirector = {
		Name = "Blacksite Director", Kind = "Tokens", TokenCost = 300,
		RequiredClears = 100, ImageId = 96837294142054,
		PreviewImageId = 96742758510511,
		Description = "A prestige suit requiring 100 lifetime clears and 300 Research Tokens.",
	},
	StaticWraith = {
		Name = "Static Wraith", Kind = "Robux", RobuxPrice = 99,
		PassId = 1994666374, ImageId = 105116444000474,
		PreviewImageId = 71524908131120,
		Description = "Premium cosmetic suit with a separate static backpack.",
	},
	FalseSun = {
		Name = "False Sun", Kind = "Robux", RobuxPrice = 149,
		PassId = 1994816385, ImageId = 83272384519781,
		PreviewImageId = 132614425134815,
		Description = "Premium cosmetic suit with a separate sun backpack.",
	},
}

local function validCount(value)
	return type(value) == "number" and value == value and value >= 0
		and value <= 9007199254740991 and value % 1 == 0
end

function Skins.Get(skinId)
	return type(skinId) == "string" and Skins.ById[skinId] or nil
end

function Skins.Normalize(value)
	local saved = type(value) == "table" and value or {}
	local savedOwned = type(saved.Owned) == "table" and saved.Owned or {}
	local owned = {[Skins.DefaultId] = true}
	for _, skinId in ipairs(Skins.Order) do
		if savedOwned[skinId] == true then owned[skinId] = true end
	end
	local equipped = saved.Equipped
	if type(equipped) ~= "string" or not owned[equipped] then
		equipped = Skins.DefaultId
	end
	return {Owned = owned, Equipped = equipped}
end

function Skins.IsOwned(state, skinId)
	return Skins.Get(skinId) ~= nil and type(state) == "table"
		and type(state.Owned) == "table" and state.Owned[skinId] == true
end

-- Call only inside a server-owned, durable mutation. In particular, a client
-- action must never call Grant directly; wheel claims and verified paid receipts
-- are the two grant paths besides a Token purchase.
function Skins.Grant(state, skinId)
	if not Skins.Get(skinId) or type(state) ~= "table"
		or type(state.Owned) ~= "table" then return false end
	if state.Owned[skinId] == true then return false end
	state.Owned[skinId] = true
	return true
end

function Skins.BuyToken(data, skinId)
	local item = Skins.Get(skinId)
	if not item or item.Kind ~= "Tokens" then return false, "Unavailable skin." end
	if not Skins.IsOwned(data.Skins, Skins.DefaultId) then
		return false, "Skin inventory is unavailable."
	end
	if Skins.IsOwned(data.Skins, skinId) then return false, "Already owned." end
	if not validCount(data.Tokens) then return false, "Token balance is unavailable." end
	if not validCount(data.CompletedLevels) then return false, "Clear count is unavailable." end
	if data.CompletedLevels < (item.RequiredClears or 0) then
		return false, ("Requires %d lifetime clears."):format(item.RequiredClears)
	end
	if data.Tokens < item.TokenCost then
		return false, ("Requires %d Research Tokens."):format(item.TokenCost)
	end
	data.Tokens -= item.TokenCost
	data.Skins.Owned[skinId] = true
	return true, item.Name .. " unlocked."
end

function Skins.Equip(state, skinId)
	if not Skins.IsOwned(state, skinId) then return false, "Skin is not owned." end
	if state.Equipped == skinId then return false, "Already equipped." end
	state.Equipped = skinId
	return true, Skins.ById[skinId].Name .. " equipped."
end

function Skins.Public(state)
	state = Skins.Normalize(state)
	return {Owned = state.Owned, Equipped = state.Equipped}
end

return Skins
