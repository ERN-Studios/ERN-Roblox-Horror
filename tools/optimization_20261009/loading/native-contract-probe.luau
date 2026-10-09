return function()

local checks = 0
local function check(value, message) assert(value, message) checks += 1 end
local vectorMethods = {}
local vectorMeta = {
 __index = function(t, k)
  if k == "Magnitude" then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z) end
  return vectorMethods[k]
 end,
 __mul = function(v,s) return setmetatable({X=v.X*s,Y=v.Y*s,Z=v.Z*s}, getmetatable(v)) end,
}
local Vector3 = {new=function(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end}
local function frame(x,y,z,yaw)
 return {PointToObjectSpace=function(_,p)
  local dx,dy,dz=p.X-x,p.Y-y,p.Z-z
  local c,s=math.cos(yaw or 0),math.sin(yaw or 0)
  return Vector3.new(dx*c-dz*s,dy,dx*s+dz*c)
 end}
end
local function signal()
 local subscriptions={}
 return {
  Connect=function(_,fn)
   local c={Fn=fn,Connected=true}
   function c:Disconnect() self.Connected=false end
   table.insert(subscriptions,c)
   return c
  end,
  Fire=function(_,...)
   for _,c in ipairs(subscriptions) do if c.Connected then c.Fn(...) end end
  end,
  Count=function()
   local n=0 for _,c in ipairs(subscriptions) do if c.Connected then n+=1 end end return n
  end,
 }
end
local methods={}
local function node(class,parent)
 local n=setmetatable({ClassName=class,Parent=parent,Children={},Attributes={},
  Visible=true,Enabled=true,DescendantAdded=signal()}, {__index=methods})
 if parent then table.insert(parent.Children,n) end
 if class=="Part" or class=="MeshPart" then
  n.Size=Vector3.new(4,4,4); n.CFrame=frame(0,0,0)
 end
 return n
end
function methods:IsA(class)
 return class==self.ClassName
  or (class=="BasePart" and (self.ClassName=="Part" or self.ClassName=="MeshPart"))
  or (class=="GuiObject" and (self.ClassName=="Frame" or self.ClassName=="ImageLabel" or self.ClassName=="ImageButton"))
  or (class=="LayerCollector" and (self.ClassName=="ScreenGui" or self.ClassName=="SurfaceGui" or self.ClassName=="BillboardGui"))
end
function methods:GetDescendants()
 local out={}
 local function scan(parent)
  for _,c in ipairs(parent.Children) do
   table.insert(out,c); scan(c)
  end
 end
 scan(self); return out
end
function methods:FindFirstAncestorWhichIsA(class)
 local p=self.Parent
 while p do if p:IsA(class) then return p end p=p.Parent end
 return nil
end
function methods:GetAttribute(k) return self.Attributes[k] end
function methods:SetAttribute(k,v) self.Attributes[k]=v end
function methods:WaitForChild(name)
 for _,c in ipairs(self.Children) do if c.Name==name then return c end end
 error("missing child "..name)
end
function methods:Destroy() self.Destroyed=true; self.Parent=nil end
local function scenario()
 local ctx={Now=0,Queue={},Calls={},Active=0,Peak=0,Delay=0.1,Fetch={}}
 function ctx:Spawn(fn,...)
  table.insert(self.Queue,{At=self.Now,Thread=coroutine.create(fn),Args=table.pack(...)})
 end
 function ctx:Advance(to)
  local steps=0
  while true do
   table.sort(self.Queue,function(a,b) return a.At<b.At end)
   local next=self.Queue[1]
   if not next or next.At>to then break end
   table.remove(self.Queue,1); self.Now=next.At
   local result=table.pack(coroutine.resume(next.Thread,table.unpack(next.Args or {},1,next.Args and next.Args.n or 0)))
   assert(result[1],result[2]); steps+=1; assert(steps<100000,"scheduler runaway")
   if coroutine.status(next.Thread)~="dead" then
    table.insert(self.Queue,{At=self.Now+(result[2] or 0.01),Thread=next.Thread})
   end
  end
  self.Now=to
 end
 ctx.Task={
  spawn=function(fn,...) ctx:Spawn(fn,...) end,
  wait=function(seconds) return coroutine.yield(seconds or 0.01) end,
  delay=function(seconds,fn)
   table.insert(ctx.Queue,{At=ctx.Now+seconds,Thread=coroutine.create(fn)})
  end,
 }
 ctx.World=node("Workspace")
 ctx.Player=node("Player")
 ctx.Gui=node("PlayerGui",ctx.Player); ctx.Gui.Name="PlayerGui"
 ctx.Root=node("Model",ctx.World)
 ctx.Provider={PreloadAsync=function(_,instances,callback)
  local inst=instances[1]
  local id=inst.Texture or inst.Image or inst.MeshId
  local mode=ctx.Fetch[id]
  ctx.Active+=1; ctx.Peak=math.max(ctx.Peak,ctx.Active)
  table.insert(ctx.Calls,{Id=id,At=ctx.Now,Instance=inst})
  coroutine.yield(mode=="stall" and 120 or ctx.Delay)
  ctx.Active-=1
  if mode=="throw" then error("synthetic content fetch error") end
  if mode~="noCallback" then callback(id,mode=="failed" and "Failed" or "Success") end
 end}
 return ctx
end
local function production(ctx)
 local task,ContentProvider,workspace,player=ctx.Task,ctx.Provider,ctx.World,ctx.Player
 local os={clock=function() return ctx.Now end}
 local Enum={AssetFetchStatus={Success="Success"},ContentSourceType={Uri="Uri",Opaque="Opaque"}}
 local Instance={new=function(class) return node(class) end}
 local function devFlag() return false end
 local function warn() end
 local function lobbyRoots() return {ctx.Root} end
 local retryToken,enterAnyway,progress=0,false,0
 local status={Text=""}
 local function touch() end
local CONTENT_PROPERTIES = {
	MeshPart = { "MeshContent", "TextureContent" },
	SpecialMesh = { "MeshId", "TextureId" },
	Decal = { "Texture" }, Texture = { "Texture" },
	ImageLabel = { "Image" }, ImageButton = { "Image" },
	ParticleEmitter = { "Texture" }, Beam = { "Texture" }, Trail = { "Texture" },
}
local MAP_PROPERTIES = { "ColorMapContent", "NormalMapContent", "RoughnessMapContent", "MetalnessMapContent" }

local function contentKey(value)
	if type(value) == "string" then return value ~= "" and value or nil end
	if typeof(value) == "Content" then
		if value.SourceType == Enum.ContentSourceType.Uri then return value.Uri ~= "" and value.Uri or nil end
		if value.SourceType == Enum.ContentSourceType.Opaque then return value end
	end
	return nil
end

local function collectAsset(instance, ids, carriers)
	local added = 0
	local function add(key, imageId, keys)
		if not key or ids[key] then return end
		ids[key] = "pending"
		added += 1
		if imageId then
			table.insert(carriers, {ImageId = imageId, Keys = {key}})
		else
			table.insert(keys, key)
		end
	end
	if instance:IsA("SurfaceAppearance") then
		-- PreloadAsync ignores SurfaceAppearance. Warm URI images through supported
		-- Decals; this cannot certify that the renderer's processed PBR pack is ready.
		for _, property in ipairs(MAP_PROPERTIES) do
			local ok, value = pcall(function() return instance[property] end)
			if ok and typeof(value) == "Content" and value.SourceType == Enum.ContentSourceType.Uri then
				add(contentKey(value), value.Uri)
			end
		end
	else
		local keys = {}
		for _, property in ipairs(CONTENT_PROPERTIES[instance.ClassName] or {}) do
			local ok, value = pcall(function() return instance[property] end)
			if ok then
				local key = contentKey(value)
				if typeof(key) == "Content" then
					-- Embedded Opaque content without an asset ID has no remote fetch.
					local legacy = property == "MeshContent" and "MeshId" or "TextureID"
					local readable, id = pcall(function() return instance[legacy] end)
					key = readable and type(id) == "string" and id ~= "" and id or nil
				end
				add(key, nil, keys)
			end
		end
		if #keys > 0 then table.insert(carriers, {Instance = instance, Keys = keys}) end
	end
	return added
end

local function loadCarrier(carrier)
	local instance = carrier.Instance
	local reported, failed = false, false
	local ok = pcall(function()
		if carrier.ImageId then
			instance = Instance.new("Decal")
			instance.Texture = carrier.ImageId
		end
		-- Keep mesh instances: a MeshId string does not necessarily fetch the
		-- same content as the actual MeshPart, especially DataModel-scoped meshes.
		ContentProvider:PreloadAsync({instance}, function(_, fetchStatus)
			reported = true
			if fetchStatus ~= Enum.AssetFetchStatus.Success then failed = true end
		end)
	end)
	if carrier.ImageId and instance then
		local cleaned = pcall(function() instance:Destroy() end)
		if not cleaned then ok = false end
	end
	-- A return or absent callback is not evidence of a successful download.
	return ok and reported and not failed
end

local function pendingCarriers(ids, carriers, wanted)
	local out = {}
	for _, carrier in ipairs(carriers) do
		for _, key in ipairs(carrier.Keys) do
			if ids[key] == wanted then table.insert(out, carrier) break end
		end
	end
	return out
end

local function census(roots, ids, carriers, instances)
	local total, checked = 0, 0
	local function consider(instance)
		total += collectAsset(instance, ids, carriers)
		checked += 1
		if checked % 200 == 0 then task.wait() end
	end
	if instances then
		for _, instance in ipairs(instances) do consider(instance) end
	else
		for _, root in ipairs(roots) do
			for _, instance in ipairs(root:GetDescendants()) do consider(instance) end
		end
	end
	if devFlag("DevLobbyLoadBadAsset") then
		local broken = Instance.new("Decal")
		broken.Texture = "rbxassetid://999999999999999"
		consider(broken)
		-- Store the URI on a test-owned carrier so no destroyed probe is preloaded.
		for _, carrier in ipairs(carriers) do
			if carrier.Instance == broken then carrier.Instance, carrier.ImageId = nil, broken.Texture end
		end
		broken:Destroy()
	end
	return total
end


local settledCount = 0
local preloadBusy = false
local function preload(ids, carriers, total)
	local failed, token, done = 0, retryToken, false
	-- All workers from a retry/skip retain this owner until their engine calls drain.
	while preloadBusy and token == retryToken and not enterAnyway do task.wait(0.1) end
	if token ~= retryToken or enterAnyway then return 0, token ~= retryToken end
	local cursor, running = 1, math.min(4, #carriers)
	if running == 0 then return 0, false end
	preloadBusy = true
	for _ = 1, running do
		task.spawn(function()
			local ok, problem = pcall(function()
				while cursor <= #carriers and token == retryToken and not enterAnyway do
					-- Claim before yielding, so each typed carrier is requested once.
					local carrier = carriers[cursor]
					cursor += 1
					while devFlag("DevLobbyLoadStall") and token == retryToken and not enterAnyway do task.wait(0.2) end
					if token ~= retryToken or enterAnyway then break end
					local loaded = loadCarrier(carrier)
					if token ~= retryToken or enterAnyway then break end
					for _, key in ipairs(carrier.Keys) do
						if ids[key] == "pending" then
							ids[key] = loaded and "ok" or "failed"
							settledCount += 1
							if not loaded then failed += 1 end
						end
					end
					progress = math.max(progress, 0.3 + 0.7 * math.min(1, settledCount / math.max(1, total)))
					status.Text = string.format("LOADING LOBBY ASSETS  %d / %d", math.min(settledCount, total), total)
					touch()
					task.wait()
				end
			end)
			if not ok then warn("[LobbyLoading] worker: " .. tostring(problem)) end
			running -= 1
			if running == 0 then
				if token == retryToken and not enterAnyway then
					-- An unexpected worker error must not turn unreported work into success.
					for _, carrier in ipairs(carriers) do
						for _, key in ipairs(carrier.Keys) do
							if ids[key] == "pending" then ids[key] = "failed" failed += 1 settledCount += 1 end
						end
					end
				end
				preloadBusy, done = false, true
			end
		end)
	end
	while not done and token == retryToken and not enterAnyway do task.wait(0.1) end
	return failed, token ~= retryToken
end


local BOOT_ASSET_RADIUS = 128
local LOBBY_BACKGROUND_SECONDS = 20
local lobbyLoadedIds = nil

local function withinBootRadius(part, origin)
	if not origin then return true end -- recovery must not silently omit the scene
	local point = part.CFrame:PointToObjectSpace(origin)
	local half = part.Size * 0.5
	local outside = Vector3.new(
		math.max(0, math.abs(point.X) - half.X),
		math.max(0, math.abs(point.Y) - half.Y),
		math.max(0, math.abs(point.Z) - half.Z))
	return outside.Magnitude <= BOOT_ASSET_RADIUS
end

local function bootAssetVisible(instance, origin)
	local host, screen = nil, false
	local ancestor = instance
	while ancestor do
		if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
		if ancestor:IsA("LayerCollector") then
			if not ancestor.Enabled then return false end
			if ancestor:IsA("ScreenGui") then
				screen = true
			elseif ancestor:IsA("SurfaceGui") or ancestor:IsA("BillboardGui") then
				local adornee = ancestor.Adornee
				if adornee and adornee:IsA("BasePart") then
					host = adornee
				elseif adornee and adornee:IsA("Attachment") then
					host = adornee:FindFirstAncestorWhichIsA("BasePart")
				end
			end
		end
		if not host and ancestor:IsA("BasePart") then host = ancestor end
		ancestor = ancestor.Parent
	end
	if screen and not host then return true end
	return host ~= nil and withinBootRadius(host, origin)
end

local function criticalCensus(roots, origin, ids, carriers)
	local instances, checked = {}, 0
	for _, root in ipairs(roots) do
		for _, instance in ipairs(root:GetDescendants()) do
			if bootAssetVisible(instance, origin) then table.insert(instances, instance) end
			checked += 1
			if checked % 200 == 0 then task.wait() end
		end
	end
	return census(nil, ids, carriers, instances)
end


local function warmLobby()
	local deadline = os.clock() + LOBBY_BACKGROUND_SECONDS
	local connections, queued, cursor = {}, {}, 1
	local ids, carriers, requested = {}, {}, 0
	local function disconnectWatches()
		for _, connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
	end
	-- Engine fetches cannot be cancelled, but their arrival watches can.
	task.delay(LOBBY_BACKGROUND_SECONDS, disconnectWatches)
	for id in pairs(lobbyLoadedIds or {}) do ids[id] = "boot" end
	local function active()
		return os.clock() < deadline
			and workspace:GetAttribute("ReservedRoundServer") ~= true
			and workspace:GetAttribute("LiveLevelServer") ~= 5
			and workspace:GetAttribute("LiveLevelServer") ~= 6
			and player:GetAttribute("InRound") ~= true
			and player:GetAttribute("Level6PlaygroundPreview") ~= true
	end
	local ok, problem = pcall(function()
		-- A skip/retry may leave the foreground engine workers draining.
		while preloadBusy and active() do task.wait(0.1) end
		if not active() then return end
		local roots = lobbyRoots()
		table.insert(roots, player:WaitForChild("PlayerGui"))
		local indexed = 0
		for _, root in ipairs(roots) do
			table.insert(connections, root.DescendantAdded:Connect(function(instance)
				if active() then table.insert(queued, instance) end
			end))
			for _, instance in ipairs(root:GetDescendants()) do
				if not active() then return end
				table.insert(queued, instance)
				indexed += 1
				if indexed % 200 == 0 then task.wait() end
			end
		end
		while active() do
			-- Index a bounded slice. No rescan and no shared progress/readiness state.
			local checked = 0
			while cursor <= #queued and checked < 200 do
				local instance = queued[cursor]
				cursor += 1
				checked += 1
				-- Radius omitted: warm the rest of the currently streamed lobby.
				if instance.Parent and bootAssetVisible(instance, nil) then
					collectAsset(instance, ids, carriers)
				end
			end
			local work = pendingCarriers(ids, carriers, "pending")
			for _, carrier in ipairs(work) do
				if not active() then return end
				local loaded = loadCarrier(carrier)
				if not active() then return end
				requested += #carrier.Keys
				for _, key in ipairs(carrier.Keys) do ids[key] = loaded and "ok" or "failed" end
				if not loaded then
					-- One bounded retry; failure never reopens or holds a cover.
					if not active() then return end
					loaded = loadCarrier(carrier)
					if not active() then return end
					for _, key in ipairs(carrier.Keys) do ids[key] = loaded and "ok" or "failed" end
				end
				task.wait(0.05)
			end
			-- Keep the bounded arrival watch alive while the player walks away
			-- from spawn; a new streamed chunk adds work without a map rescan.
			task.wait(cursor > #queued and 0.25 or 0.05)
		end
	end)
	disconnectWatches()
	if not ok then warn("[LobbyLoading] background: " .. tostring(problem)) end
	player:SetAttribute("LobbyLoadingBackgroundAssets", requested)
end

 return {
  Visible=bootAssetVisible,Census=criticalCensus,Warm=warmLobby,
  Load=loadCarrier,Preload=preload,
  Boot=function(ids) lobbyLoadedIds=ids end,
  Busy=function(b) preloadBusy=b end,
  Retry=function() retryToken+=1 end,
  Skip=function() enterAnyway=true end,
  Settled=function() return settledCount end,
  IsBusy=function() return preloadBusy end,
 }
end
local function art(parent,id,x)
 local part=node("Part",parent)
 part.CFrame=frame(x or 0,0,0)
 local decal=node("Decal",part); decal.Texture=id
 return decal,part
end
local origin=Vector3.new(0,0,0)
do
 local c=scenario(); local p=production(c)
 local near,part=art(c.Root,"near",64)
 local far=art(c.Root,"far",200)
 check(p.Visible(near,origin),"near world content belongs to boot")
 check(not p.Visible(far,origin),"far world content waits for background")
 part.Size=Vector3.new(160,4,4); part.CFrame=frame(200,0,0)
 check(p.Visible(near,origin),"large part tests distance to OBB surface")
 part.CFrame=frame(200,0,0,math.pi/2)
 check(not p.Visible(near,origin),"rotated OBB avoids sphere false positive")
 part.Size=Vector3.new(4,4,4); part.CFrame=frame(130,0,0)
 check(p.Visible(near,origin),"128 stud boundary included")
 part.CFrame=frame(130.01,0,0)
 check(not p.Visible(near,origin),"outside boundary deferred")
 check(p.Visible(far,nil),"missing recovery origin is conservative")
 local screen=node("ScreenGui",c.Gui)
 local image=node("ImageLabel",screen); image.Image="screen"
 check(p.Visible(image,origin),"visible screen UI belongs to boot")
 local hidden=node("Frame",screen); hidden.Visible=false
 local hiddenIcon=node("ImageLabel",hidden); hiddenIcon.Image="hidden"
 check(not p.Visible(hiddenIcon,origin),"hidden menu descendant excluded")
 screen.Enabled=false
 check(not p.Visible(image,origin),"disabled screen excluded")
 screen.Enabled=true
 local adornee=node("Part",c.Root); adornee.CFrame=frame(200,0,0)
 local surface=node("SurfaceGui",c.Gui); surface.Adornee=adornee
 local billboardIcon=node("ImageLabel",surface); billboardIcon.Image="billboard"
 check(not p.Visible(billboardIcon,origin),"PlayerGui world UI uses actual adornee")
 adornee.CFrame=frame(30,0,0)
 check(p.Visible(billboardIcon,origin),"near adornee included")
 local attachment=node("Attachment",adornee); surface.Adornee=attachment
 check(p.Visible(billboardIcon,origin),"attachment adornment uses ancestor part")
 surface.Enabled=false
 check(not p.Visible(billboardIcon,origin),"disabled world UI excluded")
 check(not p.Visible(node("Decal"),origin),"unparented unknown content omitted")
 c:Spawn(function()
  local ids,carriers={},{}
  local n=p.Census({c.Root,c.Gui},origin,ids,carriers)
  check(n==1 and ids.screen=="pending","critical census excludes remote and hidden content")
  check(ids.far==nil and ids.hidden==nil,"optional IDs never enter critical denominator")
 end)
 c:Advance(1)
end
do
 local c=scenario(); local p=production(c)
 art(c.Root,"alreadyBoot",0); art(c.Root,"optional",200)
 art(c.Root,"failed",300); c.Fetch.failed="failed"
 art(c.Root,"noCallback",400); c.Fetch.noCallback="noCallback"
 local screen=node("ScreenGui",c.Gui)
 local hidden=node("Frame",screen); hidden.Visible=false
 local image=node("ImageLabel",hidden); image.Image="unopenedMenu"
 p.Boot({alreadyBoot="ok"}); c:Spawn(p.Warm)
 c.Task.delay(0.6,function()
  local late=art(c.Root,"lateStreamed",600)
  c.Root.DescendantAdded:Fire(late)
  local duplicate=art(c.Root,"optional",700)
  c.Root.DescendantAdded:Fire(duplicate)
 end)
 c:Advance(21)
 local counts={}
 for _,call in ipairs(c.Calls) do counts[call.Id]=(counts[call.Id] or 0)+1 end
 check(counts.alreadyBoot==nil,"critical IDs are not requested twice")
 check(counts.optional==1,"optional content and duplicate URI requested once")
 check(counts.failed==2,"background failed fetch gets one retry")
 check(counts.noCallback==2,"absent callback never means success")
 check(counts.unopenedMenu==nil,"hidden menu is never forced into background")
 check(counts.lateStreamed==1,"late streamed arrival is indexed without rescan")
 check(c.Peak==1,"background owns at most one engine request")
 check(c.Root.DescendantAdded:Count()==0 and c.Gui.DescendantAdded:Count()==0,"arrival watches drain at cap")
 check(c.Player:GetAttribute("LobbyLoadingDone")==nil,"warming cannot release/reopen loading")
 check(c.Player:GetAttribute("LobbyLoadingBackgroundAssets")==4,"background records distinct attempted IDs")
end
do
 local c=scenario(); local p=production(c)
 art(c.Root,"afterDrain",300); p.Busy(true); c:Spawn(p.Warm)
 c.Task.delay(0.5,function() p.Busy(false) end)
 c:Advance(21)
 check(#c.Calls==1 and c.Calls[1].At>=0.5,"skip/retry foreground ownership drains before warming")
end
for _,trigger in ipairs({"InRound","Level6PlaygroundPreview","LiveLevelServer","ReservedRoundServer"}) do
 local c=scenario(); local p=production(c); c.Delay=0.5
 art(c.Root,"first",200); art(c.Root,"mustNotStart",250)
 c.Fetch.first="failed"; c:Spawn(p.Warm)
 c.Task.delay(0.15,function()
  if trigger=="LiveLevelServer" then c.World:SetAttribute(trigger,6)
  elseif trigger=="ReservedRoundServer" then c.World:SetAttribute(trigger,true)
  else c.Player:SetAttribute(trigger,true) end
 end)
 c:Advance(21)
 check(#c.Calls==1,trigger.." stops new requests and retries after an in-flight engine call")
 check(c.Root.DescendantAdded:Count()==0 and c.Gui.DescendantAdded:Count()==0,trigger.." cleans watches")
end
do
 local c=scenario(); local p=production(c)
 art(c.Root,"stall",200); art(c.Root,"afterStall",300); c.Fetch.stall="stall"
 c:Spawn(p.Warm); c:Advance(20.01)
 check(#c.Calls==1 and c.Active==1,"engine operation may remain uncancellable beyond cap")
 check(c.Root.DescendantAdded:Count()==0 and c.Gui.DescendantAdded:Count()==0,"cap cleans watchers even during engine stall")
 c:Advance(121)
 check(#c.Calls==1 and c.Active==0,"late operation cannot queue more work")
end
do
 local c=scenario(); local p=production(c)
 local carrier={ImageId="throw",Keys={"throw"}}; c.Fetch.throw="throw"
 c:Spawn(function()
  check(not p.Load(carrier),"fetch exception is failed")
  check(c.Calls[1].Instance.Destroyed,"temporary image carrier destroyed on exception")
 end)
 c:Advance(1)
end
do
 local c=scenario(); local p=production(c); local carriers,ids={},{}
 for n=1,10 do
  local decal=art(c.Root,"parallel"..n,0)
  ids[decal.Texture]="pending"
  table.insert(carriers,{Instance=decal,Keys={decal.Texture}})
 end
 c:Spawn(function()
  local failed,restarted=p.Preload(ids,carriers,10)
  check(failed==0 and not restarted,"foreground successful completion retained")
 end)
 c:Advance(5)
 check(c.Peak==4,"foreground remains bounded at four workers")
 check(#c.Calls==10 and p.Settled()==10 and not p.IsBusy(),"foreground claims once and drains ownership")
end
do
 local c=scenario(); local p=production(c); c.Delay=1
 local carriers,ids={},{}
 for n=1,8 do local decal=art(c.Root,"skip"..n,0)
  ids[decal.Texture]="pending"; table.insert(carriers,{Instance=decal,Keys={decal.Texture}}) end
 c:Spawn(function() p.Preload(ids,carriers,8) end)
 c.Task.delay(0.1,p.Skip); c:Advance(0.2)
 check(p.IsBusy() and #c.Calls==4,"foreground skip cannot release engine ownership")
 c:Advance(1.2)
 check(not p.IsBusy() and #c.Calls==4 and p.Settled()==0,"late skipped completions cannot settle IDs or start more requests")
end
do
 local c=scenario(); local p=production(c); c.Delay=1
 local carriers,ids={},{}
 for n=1,8 do local decal=art(c.Root,"retry"..n,0)
  ids[decal.Texture]="pending"; table.insert(carriers,{Instance=decal,Keys={decal.Texture}}) end
 c:Spawn(function()
  local _,restarted=p.Preload(ids,carriers,8)
  check(restarted,"retry invalidates caller attempt")
 end)
 c.Task.delay(0.1,p.Retry)
 c.Task.delay(0.2,function()
  local failed,restarted=p.Preload(ids,carriers,8)
  check(failed==0 and not restarted,"new retry completes only its own pass")
 end)
 c:Advance(0.5)
 check(#c.Calls==4 and p.IsBusy(),"retry waits for existing engine owner")
 c:Advance(4)
 check(c.Peak==4 and #c.Calls==12 and p.Settled()==8,"retry cannot multiply workers or count stale completions")
end
do
 local c=scenario(); local p=production(c)
 c.Root.GetDescendants=function() error("synthetic census error") end
 c:Spawn(p.Warm); c:Advance(1)
 check(c.Root.DescendantAdded:Count()==0 and #c.Calls==0,"background unexpected error cleans registered watches")
end
print("loading policy contract checks: "..checks)

end
