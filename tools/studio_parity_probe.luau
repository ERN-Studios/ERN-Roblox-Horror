-- Prints one line per LuaSourceContainer in the open place:
--     <full path>\t<ClassName>\t<bytes>:<fnv1a32>:<djb2-32>
-- Paste into a Studio command bar / execute_luau run and capture the return.
-- The fingerprint deliberately is NOT the manifest's sha256: tools/verify_studio_parity.py
-- recomputes it from the mirrored files, so nothing in the comparison is taken
-- from the record being checked.
-- x * 16777619 mod 2^32, done in halves. A Luau number is a double, so the
-- direct product (up to 2^56) silently loses its low bits and the hash stops
-- agreeing with the Python side -- which is exactly how the first version of
-- this probe reported all 114 scripts as drifted.
local FNV_PRIME = 0x01000193
local function fnvMul(x)
	local lo = bit32.band(x, 0xFFFF)
	local hi = bit32.rshift(x, 16)
	local low = lo * FNV_PRIME
	local high = bit32.band(hi * FNV_PRIME, 0xFFFF) * 65536
	return bit32.band(low + high, 0xFFFFFFFF)
end

local function fingerprint(source)
	local fnv, djb = 0x811C9DC5, 5381
	local n = #source
	local i = 1
	while i <= n do
		local last = math.min(i + 4095, n)
		local bytes = {string.byte(source, i, last)}
		for k = 1, #bytes do
			local b = bytes[k]
			fnv = fnvMul(bit32.bxor(fnv, b))
			djb = bit32.band(djb * 33 + b, 0xFFFFFFFF)
		end
		i = last + 1
	end
	return string.format("%d:%08x:%08x", n, fnv, djb)
end

local function pathOf(instance)
	local parts, node = {}, instance
	while node and node ~= game do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end

local lines = {}
for _, d in ipairs(game:GetDescendants()) do
	if d:IsA("LuaSourceContainer") then
		lines[#lines + 1] = pathOf(d) .. "\t" .. d.ClassName .. "\t" .. fingerprint(d.Source)
	end
end
table.sort(lines)
return table.concat(lines, "\n")
