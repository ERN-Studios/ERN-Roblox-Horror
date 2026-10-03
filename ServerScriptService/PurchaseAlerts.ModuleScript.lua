-- PurchaseAlerts
-- Fire-and-forget developer alert for a verified developer-product purchase.
--
-- Called from ZyntraMonetization's MarketplaceService.ProcessReceipt AFTER the
-- grant is committed, and only for a FIRST-TIME grant (the profile's permanent
-- ReceiptIds list is the durable dedupe; a Roblox receipt retry never reaches
-- here). Delivery is entirely separate from the grant: Notify never yields its
-- caller, never throws, and a dead relay costs at most a warn.
--
-- A Roblox game server cannot POST to discord.com: Discord answers 403 to
-- Roblox's HttpService user agent and the user agent cannot be overridden. So
-- this posts to a small authenticated relay (tools/purchase_alert_relay), and
-- the relay -- never the game server, never a client -- holds the webhook URL.

local HttpService = game:GetService("HttpService")

local SECRET_URL = "ZYNTRA_PURCHASE_ALERT_URL"
local SECRET_TOKEN = "ZYNTRA_PURCHASE_ALERT_TOKEN"
local MAX_ATTEMPTS = 3
-- Three attempts spend the first two gaps; 10 s is the documented ceiling of
-- the ladder, reached only if MAX_ATTEMPTS is raised.
local RETRY_DELAYS = { 2, 5, 10 }
local RATE_LIMIT = 20
local RATE_WINDOW = 60
local QUEUE_LIMIT = 50

local PurchaseAlerts = {}

-- Injected by _configure so the offline test can drive a fake host.
local Http, Storage, waitFor, clockNow, spawnWorker, report, isoNow, placeId, jobId
local queue, seen, sendTimes
local dropped, running, resolved, config, disabled

local function resolveConfig()
	if resolved then return config end
	resolved = true
	-- Production: Roblox Secrets. A Secret is opaque -- usable as the Url and as
	-- a header value, never readable, printable or concatenable in plain text.
	local ok, url, auth = pcall(function()
		local secretUrl = Http:GetSecret(SECRET_URL)
		return secretUrl, Http:GetSecret(SECRET_TOKEN):AddPrefix("Bearer ")
	end)
	if ok and url and auth then
		config = { Url = url, Auth = auth }
		return config
	end
	-- Studio and local testing: a server-only config object. ServerStorage is
	-- never replicated, so no client ever sees the endpoint or the token.
	local folder = Storage and Storage:FindFirstChild("PurchaseAlertConfig")
	local endpoint = folder and folder:GetAttribute("Endpoint")
	local token = folder and folder:GetAttribute("Token")
	if type(endpoint) == "string" and endpoint ~= "" and type(token) == "string" and token ~= "" then
		config = { Url = endpoint, Auth = "Bearer " .. token }
		return config
	end
	report("[PurchaseAlerts] not configured; alerts disabled")
	disabled = true
	return nil
end

local function payloadFor(alert)
	return {
		purchaseId = alert.PurchaseId,
		productId = alert.ProductId,
		productKey = alert.ProductKey,
		productName = alert.ProductName,
		kind = alert.Kind,
		robux = alert.RobuxSpent,
		playerName = alert.PlayerName,
		userId = alert.UserId,
		placeId = placeId,
		jobId = jobId,
		timestamp = isoNow(),
		test = alert.IsStudio == true,
	}
end

-- One POST. Returns "done", "retry" or "stop"; never throws, never logs a value.
local function attempt(cfg, body)
	local ok, response = pcall(function()
		return Http:RequestAsync({
			Url = cfg.Url,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", Authorization = cfg.Auth },
			Body = body,
		})
	end)
	if not ok then
		if string.find(string.lower(tostring(response)), "not enabled", 1, true) then
			disabled = true
			report("[PurchaseAlerts] HTTP requests are not enabled for this place; alerts disabled")
			return "stop"
		end
		return "retry"
	end
	local status = 0
	if type(response) == "table" and type(response.StatusCode) == "number" then
		status = response.StatusCode
	end
	if status >= 200 and status < 300 then return "done" end
	if status == 408 or status == 429 or status >= 500 then return "retry" end
	report(string.format("[PurchaseAlerts] relay rejected an alert (HTTP %d); dropped", status))
	return "stop"
end

local function rateGate()
	while #sendTimes >= RATE_LIMIT do
		local age = clockNow() - sendTimes[1]
		if age >= RATE_WINDOW then
			table.remove(sendTimes, 1)
		else
			waitFor(RATE_WINDOW - age)
		end
	end
	table.insert(sendTimes, clockNow())
end

local function drain()
	while #queue > 0 do
		local cfg = resolveConfig()
		if not cfg then break end
		local alert = table.remove(queue, 1)
		rateGate()
		local body = Http:JSONEncode(payloadFor(alert))
		local outcome
		for n = 1, MAX_ATTEMPTS do
			outcome = attempt(cfg, body)
			if outcome ~= "retry" then break end
			if n < MAX_ATTEMPTS then waitFor(RETRY_DELAYS[n]) end
		end
		if outcome == "retry" then
			report("[PurchaseAlerts] alert not delivered after " .. MAX_ATTEMPTS .. " attempts; dropped")
		end
		if disabled then break end
	end
end

local function worker()
	-- No error text is logged: an error string can quote the configured URL.
	local ok = pcall(drain)
	running = false
	if not ok then report("[PurchaseAlerts] alert worker failed; alert dropped") end
end

-- alert = {PurchaseId, ProductId, ProductKey, ProductName, Kind, RobuxSpent,
--          PlayerName, UserId, IsStudio}. Returns nothing.
function PurchaseAlerts.Notify(alert)
	if disabled or type(alert) ~= "table" then return end
	local purchaseId = alert.PurchaseId
	if type(purchaseId) ~= "string" or purchaseId == "" or seen[purchaseId] then return end
	seen[purchaseId] = true
	if #queue >= QUEUE_LIMIT then
		table.remove(queue, 1)
		dropped += 1
		report("[PurchaseAlerts] queue full; " .. dropped .. " alert(s) dropped")
	end
	table.insert(queue, alert)
	if not running then
		running = true
		spawnWorker(worker)
	end
end

-- Test seam and state reset. Production calls this once, argument-less, below.
function PurchaseAlerts._configure(deps)
	deps = deps or {}
	Http = deps.HttpService or HttpService
	Storage = deps.ServerStorage or game:GetService("ServerStorage")
	waitFor = deps.wait or task.wait
	clockNow = deps.clock or os.clock
	spawnWorker = deps.spawn or task.spawn
	report = deps.warn or warn
	isoNow = deps.now or function() return DateTime.now():ToIsoDate() end
	placeId = deps.placeId or game.PlaceId
	jobId = deps.jobId or game.JobId
	queue, seen, sendTimes = {}, {}, {}
	dropped, running, resolved, config, disabled = 0, false, false, nil, false
end

PurchaseAlerts._configure()

return PurchaseAlerts
