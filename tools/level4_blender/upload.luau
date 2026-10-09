-- Level 4 cinema import: pull chunks from the loopback server, build an EditableMesh (with UVs),
-- upload it to the group as a Mesh asset, report the id. LIMIT/BACKGROUND are
-- substituted by the caller. Restores HttpService.HttpEnabled when it stops.
local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local BASE = "http://127.0.0.1:8765"
local LIMIT = __LIMIT__
local GROUP = 1039373905

local function build(b)
	local nv, nn, nu, nf = buffer.readu32(b, 0), buffer.readu32(b, 4), buffer.readu32(b, 8), buffer.readu32(b, 12)
	local em = AS:CreateEditableMesh()
	local vid, nid, uid = table.create(nv), table.create(nn), table.create(nu)
	local o = 16
	for i = 1, nv do
		vid[i] = em:AddVertex(Vector3.new(buffer.readf32(b, o), buffer.readf32(b, o + 4), buffer.readf32(b, o + 8)))
		o += 12
	end
	for i = 1, nn do
		nid[i] = em:AddNormal(Vector3.new(buffer.readf32(b, o), buffer.readf32(b, o + 4), buffer.readf32(b, o + 8)))
		o += 12
	end
	for i = 1, nu do
		uid[i] = em:AddUV(Vector2.new(buffer.readf32(b, o), buffer.readf32(b, o + 4)))
		o += 8
	end
	for _ = 1, nf do
		local v1, n1, u1 = buffer.readu32(b, o) + 1, buffer.readu32(b, o + 4) + 1, buffer.readu32(b, o + 8) + 1
		local v2, n2, u2 = buffer.readu32(b, o + 12) + 1, buffer.readu32(b, o + 16) + 1, buffer.readu32(b, o + 20) + 1
		local v3, n3, u3 = buffer.readu32(b, o + 24) + 1, buffer.readu32(b, o + 28) + 1, buffer.readu32(b, o + 32) + 1
		o += 36
		local f = em:AddTriangle(vid[v1], vid[v2], vid[v3])
		em:SetFaceNormals(f, {nid[n1], nid[n2], nid[n3]})
		em:SetFaceUVs(f, {uid[u1], uid[u2], uid[u3]})
	end
	return em
end

local function run()
	local wasEnabled = HS.HttpEnabled
	HS.HttpEnabled = true
	local ok, err = pcall(function()
		local pending = __ONLY__ or HS:GetAsync(BASE .. "/pending", true)
		local n = 0
		for id in string.gmatch(pending, "%d+") do
			if n >= LIMIT or shared.__l4stop then break end
			n += 1
			shared.__l4status = "chunk " .. id .. " (" .. n .. ")"
			local okc, res = pcall(function()
				local b64 = HS:GetAsync(BASE .. "/chunk/" .. id, true)
				local b = ENC:Base64Decode(buffer.fromstring(b64))
				local em = build(b)
				local status, assetId
				for attempt = 1, 4 do
					status, assetId = AS:CreateAssetAsync(em, Enum.AssetType.Mesh, {
						Name = "L4_Cinema_" .. id, Description = "Level 4 cinema (Blender) import chunk " .. id,
						CreatorId = GROUP, CreatorType = Enum.AssetCreatorType.Group,
					})
					if status == Enum.CreateAssetResult.Success then break end
					task.wait(5 * attempt)
				end
				em:Destroy()
				if status ~= Enum.CreateAssetResult.Success then error(tostring(status)) end
				return assetId
			end)
			if okc then
				HS:PostAsync(BASE .. "/result?id=" .. id .. "&asset=" .. tostring(res), "")
			else
				HS:PostAsync(BASE .. "/result?id=" .. id .. "&error=fail", tostring(res))
				shared.__l4lastError = tostring(res)
			end
		end
	end)
	HS.HttpEnabled = wasEnabled
	shared.__l4status = if ok then "finished" else ("stopped: " .. tostring(err))
end

if __BACKGROUND__ then
	shared.__l4stop = false
	task.spawn(run)
	return "started"
end
run()
return tostring(shared.__l4status) .. " lastError=" .. tostring(shared.__l4lastError)
