-- Studio plugin context. Uploads only; never changes a place instance.
-- Optional direct asset path for the revised material-split Level 6 kit.
-- The persistent raw-source installer remains the supported fallback when
-- CreateAssetAsync is unavailable in this Studio security context.
local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local BASE = "http://127.0.0.1:8890"
local LIMIT = 64
local ONLY = nil -- Optional comma-separated manifest IDs for a bounded retry.
local GROUP = 1039373905

assert(game.PlaceId == 131311258779917 and game.CreatorId == GROUP, "Wrong experience or owner")
assert(not shared.__l6uploadRunning, "An upload worker is already active")

local function build(b)
	assert(buffer.len(b) >= 20 and buffer.readu32(b, 0) == 0x364D564C, "Wrong mesh format")
	local nv, nn, nu, nf = buffer.readu32(b, 4), buffer.readu32(b, 8), buffer.readu32(b, 12), buffer.readu32(b, 16)
	assert(nv > 0 and nv <= 60000 and nf > 0 and nf <= 20000, "Mesh exceeds geometry budget")
	assert(buffer.len(b) == 20 + nv * 12 + nn * 12 + nu * 8 + nf * 36, "Truncated mesh")
	local em = assert(AS:CreateEditableMesh(), "EditableMesh memory unavailable")
	local ok, err = pcall(function()
		local vertices, normals, uvs = table.create(nv), table.create(nn), table.create(nu)
		local offset = 20
		for i = 1, nv do
			vertices[i] = em:AddVertex(Vector3.new(buffer.readf32(b, offset), buffer.readf32(b, offset + 4), buffer.readf32(b, offset + 8)))
			offset += 12
		end
		for i = 1, nn do
			normals[i] = em:AddNormal(Vector3.new(buffer.readf32(b, offset), buffer.readf32(b, offset + 4), buffer.readf32(b, offset + 8)))
			offset += 12
		end
		for i = 1, nu do
			uvs[i] = em:AddUV(Vector2.new(buffer.readf32(b, offset), 1 - buffer.readf32(b, offset + 4)))
			offset += 8
		end
		for _ = 1, nf do
			local v, n, uv = {}, {}, {}
			for corner = 1, 3 do
				v[corner] = assert(vertices[buffer.readu32(b, offset) + 1], "Invalid vertex index")
				n[corner] = assert(normals[buffer.readu32(b, offset + 4) + 1], "Invalid normal index")
				uv[corner] = assert(uvs[buffer.readu32(b, offset + 8) + 1], "Invalid UV index")
				offset += 12
			end
			local face = em:AddTriangle(v[1], v[2], v[3])
			em:SetFaceNormals(face, n)
			em:SetFaceUVs(face, uv)
		end
	end)
	if not ok then em:Destroy(); error(err) end
	return em
end

local function run()
	local previousHttp = HS.HttpEnabled
	HS.HttpEnabled = true
	local ok, err = pcall(function()
		local manifest = HS:JSONDecode(HS:GetAsync(BASE .. "/manifest", true))
		assert(manifest.schema == "level6-blender-prefabs-v2" and manifest.groupId == GROUP
			and #manifest.chunks == 279 and manifest.uniqueTriangles == 74092, "Wrong revised Level 6 manifest")
		local byId = {}
		for _, chunk in ipairs(manifest.chunks) do byId[tostring(chunk.id)] = chunk end
		local pending = ONLY or HS:GetAsync(BASE .. "/pending", true)
		local count = 0
		for id in pending:gmatch("%d+") do
			if count >= LIMIT or shared.__l6uploadStop then break end
			count += 1
			local chunk = assert(byId[id], "Unknown manifest ID")
			shared.__l6uploadStatus = "uploading " .. chunk.name .. " (" .. count .. ")"
			local mesh
			local success, result = pcall(function()
				mesh = build(ENC:Base64Decode(buffer.fromstring(HS:GetAsync(BASE .. "/chunk/" .. id, true))))
				local last
				for attempt = 1, 4 do
					local called, status, asset = pcall(AS.CreateAssetAsync, AS, mesh, Enum.AssetType.Mesh, {
						Name = "L6_Party_" .. chunk.name,
						Description = "Reusable Blender-authored Level 6 party Backrooms kit. Source SHA256 " .. chunk.sha256,
						CreatorId = GROUP, CreatorType = Enum.AssetCreatorType.Group,
					})
					if called and status == Enum.CreateAssetResult.Success then return asset end
					last = tostring(status) .. " " .. tostring(asset)
					if attempt < 4 then task.wait(5 * 2 ^ (attempt - 1)) end
				end
				error(last)
			end)
			if mesh then mesh:Destroy() end
			if success then
				HS:PostAsync(BASE .. "/result?id=" .. id .. "&asset=" .. tostring(result), "")
			else
				HS:PostAsync(BASE .. "/result?id=" .. id, tostring(result))
				shared.__l6uploadError = tostring(result)
			end
			task.wait(1.5)
		end
	end)
	HS.HttpEnabled = previousHttp
	shared.__l6uploadRunning = nil
	shared.__l6uploadStatus = if ok then "finished" else "failed: " .. tostring(err)
end

shared.__l6uploadRunning = true
shared.__l6uploadStop = false
task.spawn(run)
return "Level 6 mesh upload started; inspect shared.__l6uploadStatus"
