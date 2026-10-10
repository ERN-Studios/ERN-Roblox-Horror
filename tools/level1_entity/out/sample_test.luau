-- ENTITY_MOTION_20261010: standalone mock; actual clip excerpts, exact player sampling functions.
-- Rebuild this fixture with: python3 work/write_sample_test.py
local function jsonDecode(text)
	local p = 1
	local parse
	local function ws()
		while string.match(string.sub(text, p, p), "%s") do p += 1 end
	end
	local function stringValue()
		p += 1
		local start = p
		while string.sub(text, p, p) ~= '"' do
			assert(p <= #text, "unterminated JSON string")
			assert(string.sub(text, p, p) ~= "\\", "fixture uses only unescaped ASCII names")
			p += 1
		end
		local value = string.sub(text, start, p - 1)
		p += 1
		return value
	end
	parse = function()
		ws()
		local token = string.sub(text, p, p)
		if token == '"' then return stringValue() end
		if token == "{" or token == "[" then
			local object, close, result = token == "{", token == "{" and "}" or "]", {}
			p += 1; ws()
			if string.sub(text, p, p) == close then p += 1; return result end
			while true do
				local key
				if object then
					assert(string.sub(text, p, p) == '"', "expected JSON key")
					key = stringValue(); ws()
					assert(string.sub(text, p, p) == ":"); p += 1
				end
				local value = parse()
				if object then result[key] = value else table.insert(result, value) end
				ws()
				local separator = string.sub(text, p, p); p += 1
				if separator == close then break end
				assert(separator == ",", "expected JSON separator"); ws()
			end
			return result
		end
		for literal, value in pairs({["true"] = true, ["false"] = false}) do
			if string.sub(text, p, p + #literal - 1) == literal then p += #literal; return value end
		end
		local number = string.match(string.sub(text, p), "^%-?%d+%.?%d*[eE]?[%+%-]?%d*")
		assert(number and tonumber(number), "expected JSON value at " .. p)
		p += #number
		return tonumber(number)
	end
	local result = parse(); ws(); assert(p > #text, "trailing JSON")
	return result
end

local HttpService = {JSONDecode = function(_, raw) return jsonDecode(raw) end}
local Vector3 = {}
local VectorMT = {}
VectorMT.__index = VectorMT
function Vector3.new(x, y, z) return setmetatable({X = x, Y = y, Z = z}, VectorMT) end
function VectorMT:Lerp(other, t)
	return Vector3.new(self.X + (other.X - self.X) * t, self.Y + (other.Y - self.Y) * t, self.Z + (other.Z - self.Z) * t)
end
local CFrame = {}
local FrameMT = {}
FrameMT.__index = FrameMT
local function frame(x, y, z, qx, qy, qz, qw)
	return setmetatable({Position = Vector3.new(x, y, z), q = {qx, qy, qz, qw}}, FrameMT)
end
function CFrame.new(x, y, z, qx, qy, qz, qw)
	if type(x) == "table" then return frame(x.X, x.Y, x.Z, 0, 0, 0, 1) end
	return frame(x or 0, y or 0, z or 0, qx or 0, qy or 0, qz or 0, qw or 1)
end
function FrameMT:Lerp(other, t)
	local a, b, dot = self.q, other.q, 0
	for i = 1, 4 do dot += a[i] * b[i] end
	local sign = dot < 0 and -1 or 1
	dot = math.clamp(math.abs(dot), 0, 1)
	local w0, w1 = 1 - t, t
	if dot < 0.9995 then
		local angle = math.acos(dot)
		w0, w1 = math.sin((1 - t) * angle) / math.sin(angle), math.sin(t * angle) / math.sin(angle)
	end
	local q, norm = {}, 0
	for i = 1, 4 do q[i] = w0 * a[i] + w1 * sign * b[i]; norm += q[i] * q[i] end
	norm = math.sqrt(norm)
	for i = 1, 4 do q[i] /= norm end
	local v = self.Position:Lerp(other.Position, t)
	return frame(v.X, v.Y, v.Z, q[1], q[2], q[3], q[4])
end
function FrameMT.__mul(a, b)
	-- sampleBone multiplies a translation by a rotation, so no position rotation is needed here.
	assert(a.q[1] == 0 and a.q[2] == 0 and a.q[3] == 0 and a.q[4] == 1, "unexpected mock multiplication")
	return frame(a.Position.X + b.Position.X, a.Position.Y + b.Position.Y, a.Position.Z + b.Position.Z, b.q[1], b.q[2], b.q[3], b.q[4])
end
CFrame.identity = CFrame.new()
local IDENTITY = CFrame.identity

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function decodeClip(raw)
	local data = HttpService:JSONDecode(raw)
	assert(type(data) == "table" and finite(data.frames) and data.frames >= 2 and data.frames % 1 == 0, "invalid frames")
	assert(finite(data.fps) and data.fps > 0 and type(data.loop) == "boolean" and type(data.bones) == "table", "invalid metadata")
	local count = data.frames
	assert(count <= 600, "clip too large")
	local tracks = {}
	for name, quaternions in pairs(data.bones) do
		assert(type(name) == "string" and type(quaternions) == "table" and #quaternions == count * 4, "invalid bone track")
		local frames = table.create(count)
		for f = 0, count - 1 do
			local i = f * 4
			local x, y, z, w = quaternions[i + 1], quaternions[i + 2], quaternions[i + 3], quaternions[i + 4]
			assert(finite(x) and finite(y) and finite(z) and finite(w), "invalid quaternion")
			local norm = math.sqrt(x * x + y * y + z * z + w * w)
			assert(norm > 0.01, "zero quaternion")
			frames[f + 1] = CFrame.new(0, 0, 0, x / norm, y / norm, z / norm, w / norm)
		end
		tracks[name] = frames
	end
	local hips = nil
	if data.hips ~= nil then
		assert(type(data.hips) == "table" and #data.hips == count * 3, "invalid hips track")
		hips = table.create(count)
		for f = 0, count - 1 do
			local i = f * 3
			local x, y, z = data.hips[i + 1], data.hips[i + 2], data.hips[i + 3]
			assert(finite(x) and finite(y) and finite(z), "invalid hips position")
			hips[f + 1] = Vector3.new(x / 1000, y / 1000, z / 1000)
		end
	end
	local contacts = data.contacts
	if contacts ~= nil then
		assert(type(contacts) == "table" and (#contacts == 2 or (not data.loop and #contacts == 0)), "invalid contacts")
		for _, contact in ipairs(contacts) do assert(finite(contact) and contact >= 0 and contact < 1, "invalid contact phase") end
	end
	return {frames = count, fps = data.fps, duration = count / data.fps, loop = data.loop,
		tracks = tracks, hips = hips, stride = tonumber(data.stride) or 0, speed = tonumber(data.speed) or 0,
		contacts = contacts or {0, 0.5}}
end

local function atPhase(c, p)
	local f = c.loop and ((p % 1) * c.frames) or (math.clamp(p, 0, 1) * (c.frames - 1))
	local i = math.floor(f)
	local nextIndex = c.loop and ((i + 1) % c.frames + 1) or math.min(i + 2, c.frames)
	return i + 1, nextIndex, f - i
end

local function sampleBone(c, name, i0, i1, a)
	if not c then return nil end
	local frames = c.tracks[name]
	local target = frames and frames[i0]:Lerp(frames[i1], a) or nil
	if name == "Hips" and c.hips then
		target = CFrame.new(c.hips[i0]:Lerp(c.hips[i1], a)) * (target or IDENTITY)
	end
	return target
end

local function crossedContacts(c, fromPhase, toPhase)
	local count = 0
	for _, contact in ipairs(c.contacts) do count += math.floor(toPhase - contact) - math.floor(fromPhase - contact) end
	return count
end
local RAW_WALK = [==[{"frames":72,"fps":60.0,"loop":true,"stride":9.6,"speed":8.0,"contacts":[0,0.5],"hips":[19,-1120,-64,37,-1091,-58,54,-1043,-51,71,-1008,-45,88,-969,-39,104,-934,-34,120,-906,-29,135,-884,-24,149,-865,-20,162,-845,-16,173,-823,-12,184,-799,-8,193,-772,-4,201,-743,0,207,-714,4,212,-685,8,215,-656,11,217,-629,14,217,-605,17,215,-584,19,213,-567,21,208,-554,22,203,-547,22,195,-545,22,187,-550,21,177,-563,18,167,-588,15,155,-626,10,143,-678,4,130,-742,-4,116,-824,-13,101,-912,-23,86,-987,-32,70,-1057,-42,54,-1105,-51,36,-1114,-57,19,-1120,-64,1,-1091,-69,-17,-1043,-72,-35,-1008,-77,-52,-969,-81,-69,-934,-85,-85,-906,-89,-100,-884,-94,-114,-865,-98,-127,-845,-101,-139,-823,-104,-150,-799,-107,-160,-772,-108,-168,-743,-109,-176,-714,-109,-182,-685,-109,-186,-656,-108,-190,-629,-106,-191,-605,-104,-191,-584,-101,-190,-567,-98,-187,-554,-95,-182,-547,-91,-176,-545,-88,-168,-550,-84,-159,-563,-81,-148,-588,-78,-136,-626,-76,-122,-678,-74,-107,-742,-73,-90,-824,-74,-73,-912,-74,-55,-987,-74,-36,-1057,-74,-18,-1105,-72,1,-1114,-68],"bones":{"Hips":[-637,0,-188,9978,-660,57,-161,9977,-684,114,-135,9975,-711,169,-110,9973,-737,223,-85,9970,-765,276,-61,9967,-791,326,-38,9963,-817,373,-16,9960,-840,418,5,9956,-862,459,24,9952,-881,497,43,9949,-896,531,60,9945,-908,561,75,9943,-916,587,89,9940,-921,608,101,9938,-921,625,112,9937,-917,637,120,9937,-909,645,126,9937,-898,648,130,9938,-884,646,132,9939,-867,639,131,9941,-847,628,128,9943,-826,611,123,9946,-804,591,115,9949,-781,565,105,9953,-758,535,93,9956,-736,501,78,9960,-716,463,60,9963,-696,421,41,9967,-679,376,19,9970,-665,328,-5,9972,-653,277,-32,9975,-644,225,-60,9977,-638,170,-90,9978,-635,114,-121,9978,-634,57,-154,9979,-637,0,-188,9978,-641,-57,-223,9977,-648,-114,-259,9975,-656,-169,-294,9973,-665,-223,-330,9970,-675,-276,-364,9967,-685,-326,-398,9963,-694,-373,-430,9960,-703,-418,-461,9956,-710,-459,-489,9952,-716,-497,-515,9949,-720,-531,-538,9945,-721,-561,-557,9943,-721,-587,-573,9940,-718,-608,-586,9938,-712,-625,-594,9937,-704,-637,-599,9937,-695,-645,-600,9937,-683,-648,-598,9938,-670,-646,-591,9939,-656,-639,-581,9941,-641,-628,-568,9943,-626,-611,-553,9946,-612,-591,-534,9949,-598,-565,-513,9953,-586,-535,-490,9956,-576,-501,-466,9960,-568,-463,-440,9963,-562,-421,-413,9967,-560,-376,-385,9970,-561,-328,-357,9972,-565,-277,-329,9975,-573,-225,-300,9977,-584,-170,-272,9978,-599,-114,-243,9978,-616,-57,-216,9979],"Head":[-960,-348,-10,9948,-960,-347,-2,9948,-960,-345,5,9948,-960,-344,12,9948,-960,-342,19,9948,-960,-341,26,9948,-960,-340,33,9948,-960,-338,39,9948,-961,-337,45,9948,-961,-336,51,9948,-961,-335,56,9948,-961,-334,60,9948,-961,-333,64,9948,-961,-333,68,9948,-961,-332,70,9948,-961,-332,73,9948,-961,-331,74,9948,-961,-331,75,9948,-961,-331,76,9948,-961,-331,75,9948,-961,-331,74,9948,-961,-332,73,9948,-961,-332,70,9948,-961,-333,68,9948,-961,-333,64,9948,-961,-334,60,9948,-961,-335,56,9948,-961,-336,51,9948,-961,-337,45,9948,-960,-338,39,9948,-960,-340,33,9948,-960,-341,26,9948,-960,-342,19,9948,-960,-344,12,9948,-960,-345,5,9948,-960,-347,-2,9948,-960,-348,-10,9948,-960,-350,-17,9948,-959,-351,-25,9948,-959,-353,-32,9948,-959,-354,-39,9948,-959,-356,-46,9947,-959,-357,-53,9947,-959,-358,-59,9947,-959,-359,-65,9947,-959,-361,-70,9947,-959,-362,-75,9947,-959,-362,-80,9947,-959,-363,-84,9947,-958,-364,-87,9947,-958,-365,-90,9947,-958,-365,-93,9947,-958,-365,-94,9947,-958,-366,-95,9947,-958,-366,-95,9947,-958,-366,-95,9947,-958,-365,-94,9947,-958,-365,-93,9947,-958,-365,-90,9947,-958,-364,-87,9947,-959,-363,-84,9947,-959,-362,-80,9947,-959,-362,-75,9947,-959,-361,-70,9947,-959,-359,-65,9947,-959,-358,-59,9947,-959,-357,-53,9947,-959,-356,-46,9947,-959,-354,-39,9948,-959,-353,-32,9948,-959,-351,-25,9948,-960,-350,-17,9948]}}]==]
local RAW_RUN = [==[{"frames":68,"fps":99.99999999999999,"loop":true,"stride":18.496000000000002,"speed":27.2,"contacts":[0,0.5],"hips":[17,-961,-57,23,-989,-58,30,-1013,-59,36,-1033,-60,42,-1045,-60,48,-1047,-60,53,-1039,-59,57,-1021,-58,61,-993,-55,64,-956,-52,67,-911,-49,69,-860,-45,71,-805,-40,72,-746,-36,72,-688,-31,72,-630,-26,72,-577,-22,71,-528,-18,70,-489,-14,69,-460,-11,67,-444,-9,65,-444,-9,63,-463,-9,61,-503,-12,59,-555,-15,56,-611,-19,53,-681,-24,50,-738,-28,46,-794,-33,42,-836,-37,37,-865,-41,32,-896,-45,27,-917,-49,22,-937,-53,17,-961,-57,12,-989,-62,7,-1013,-66,2,-1033,-70,-2,-1045,-74,-7,-1047,-76,-12,-1039,-78,-16,-1021,-79,-21,-993,-80,-25,-956,-79,-30,-911,-77,-34,-860,-75,-37,-805,-72,-41,-746,-69,-44,-688,-65,-46,-630,-61,-49,-577,-57,-50,-528,-54,-51,-489,-50,-52,-460,-47,-51,-444,-44,-50,-444,-43,-48,-463,-42,-45,-503,-43,-41,-555,-44,-37,-611,-46,-32,-681,-49,-26,-738,-51,-21,-794,-53,-15,-836,-54,-9,-865,-55,-2,-896,-55,4,-917,-56,10,-937,-56],"bones":{"Hips":[-1712,0,-506,9839,-1743,85,-454,9836,-1775,169,-403,9832,-1808,251,-352,9826,-1842,331,-303,9819,-1874,408,-255,9811,-1906,481,-210,9803,-1935,549,-166,9794,-1962,613,-125,9786,-1985,672,-87,9778,-2005,724,-52,9770,-2021,771,-21,9763,-2031,811,7,9758,-2038,845,31,9754,-2039,871,50,9751,-2036,891,64,9750,-2029,903,74,9750,-2018,907,79,9752,-2002,904,80,9755,-1984,894,75,9760,-1963,876,65,9766,-1940,851,50,9773,-1916,818,31,9781,-1891,778,7,9789,-1865,732,-22,9797,-1841,679,-55,9805,-1818,620,-92,9813,-1796,555,-133,9821,-1776,485,-178,9827,-1759,411,-227,9833,-1745,333,-278,9837,-1733,252,-332,9840,-1723,169,-388,9841,-1716,85,-447,9841,-1712,0,-506,9839,-1709,-85,-567,9836,-1709,-169,-627,9832,-1709,-251,-688,9826,-1710,-331,-747,9819,-1712,-408,-805,9811,-1713,-481,-860,9803,-1714,-549,-913,9794,-1715,-613,-962,9786,-1713,-672,-1007,9778,-1711,-724,-1047,9770,-1707,-771,-1081,9763,-1701,-811,-1111,9758,-1694,-845,-1134,9754,-1685,-871,-1151,9751,-1674,-891,-1161,9750,-1662,-903,-1166,9750,-1650,-907,-1164,9752,-1637,-904,-1156,9755,-1624,-894,-1142,9760,-1612,-876,-1122,9766,-1601,-851,-1097,9773,-1591,-818,-1068,9781,-1583,-778,-1034,9789,-1577,-732,-996,9797,-1575,-679,-955,9805,-1576,-620,-911,9813,-1580,-555,-865,9821,-1588,-485,-816,9827,-1600,-411,-766,9833,-1615,-333,-715,9837,-1635,-252,-664,9840,-1657,-169,-611,9841,-1683,-85,-559,9841],"Head":[-961,-334,62,9948,-961,-332,70,9948,-961,-331,78,9948,-961,-329,85,9948,-961,-327,93,9948,-961,-326,100,9948,-961,-325,107,9948,-962,-323,113,9948,-962,-322,119,9948,-962,-321,125,9948,-962,-320,130,9948,-962,-319,135,9948,-962,-318,138,9948,-962,-318,142,9948,-962,-317,144,9948,-962,-317,146,9948,-962,-316,147,9948,-962,-316,147,9948,-962,-316,147,9948,-962,-317,146,9948,-962,-317,144,9948,-962,-318,142,9948,-962,-318,138,9948,-962,-319,135,9948,-962,-320,130,9948,-962,-321,125,9948,-962,-322,119,9948,-962,-323,113,9948,-961,-325,107,9948,-961,-326,100,9948,-961,-327,93,9948,-961,-329,85,9948,-961,-331,78,9948,-961,-332,70,9948,-961,-334,62,9948,-961,-335,54,9948,-961,-337,46,9948,-960,-338,38,9948,-960,-340,31,9948,-960,-341,24,9948,-960,-343,17,9948,-960,-344,10,9948,-960,-345,4,9948,-960,-347,-1,9948,-960,-348,-6,9948,-960,-348,-11,9948,-960,-349,-15,9948,-960,-350,-18,9948,-960,-350,-20,9948,-959,-351,-22,9948,-959,-351,-23,9948,-959,-351,-24,9948,-959,-351,-23,9948,-959,-351,-22,9948,-960,-350,-20,9948,-960,-350,-18,9948,-960,-349,-15,9948,-960,-348,-11,9948,-960,-348,-6,9948,-960,-347,-1,9948,-960,-345,4,9948,-960,-344,10,9948,-960,-343,17,9948,-960,-341,24,9948,-960,-340,31,9948,-960,-338,38,9948,-961,-337,46,9948,-961,-335,54,9948]}}]==]
local RAW_FLIGHT = [==[{"frames":85,"fps":198.5981308411215,"loop":false,"stride":0,"speed":0,"contacts":[],"hips":[-84,-1884,286,-82,-1877,277,-74,-1855,251,-62,-1821,211,-47,-1776,158,-28,-1722,93,-6,-1659,19,19,-1590,-63,45,-1516,-151,72,-1438,-243,100,-1358,-338,128,-1277,-433,156,-1198,-528,183,-1120,-620,209,-1046,-708,233,-978,-789,255,-916,-863,274,-862,-928,290,-817,-981,302,-783,-1020,309,-762,-1046,312,-755,-1055,312,-755,-1055,312,-755,-1055,312,-756,-1056,313,-757,-1058,313,-759,-1059,314,-760,-1061,314,-762,-1063,315,-764,-1065,316,-766,-1067,316,-767,-1070,317,-769,-1072,318,-771,-1074,318,-773,-1076,319,-775,-1078,319,-777,-1080,320,-778,-1082,320,-780,-1084,321,-781,-1085,321,-782,-1086,321,-782,-1087,321,-782,-1087,322,-784,-1088,322,-790,-1090,323,-799,-1094,325,-812,-1099,327,-843,-1107,330,-868,-1115,332,-876,-1122,334,-885,-1131,337,-908,-1140,340,-931,-1150,343,-955,-1161,346,-980,-1171,349,-1004,-1181,352,-1028,-1191,355,-1051,-1201,358,-1073,-1211,361,-1093,-1219,363,-1112,-1227,365,-1128,-1234,367,-1142,-1240,368,-1153,-1245,369,-1161,-1248,370,-1165,-1250,369,-1166,-1250,369,-1175,-1247,367,-1191,-1242,365,-1213,-1235,363,-1241,-1226,360,-1274,-1216,356,-1310,-1205,353,-1349,-1192,349,-1390,-1180,345,-1431,-1167,341,-1473,-1154,337,-1513,-1141,334,-1550,-1129,331,-1585,-1118,328,-1616,-1109,326,-1641,-1101,324,-1661,-1095,323,-1673,-1091,322,-1677,-1090],"bones":{"Hips":[-2749,0,-813,9580,-2755,0,-815,9578,-2771,0,-819,9573,-2798,0,-827,9565,-2832,0,-837,9554,-2874,0,-850,9540,-2922,0,-864,9525,-2975,0,-879,9507,-3031,0,-896,9487,-3091,0,-914,9466,-3151,0,-932,9445,-3213,0,-950,9422,-3273,0,-968,9399,-3332,0,-985,9377,-3388,0,-1002,9355,-3440,0,-1017,9334,-3487,0,-1031,9316,-3528,0,-1043,9299,-3561,0,-1053,9285,-3586,0,-1060,9274,-3602,0,-1065,9268,-3608,0,-1067,9265,-3609,0,-1067,9265,-3612,0,-1068,9264,-3617,0,-1069,9262,-3623,0,-1071,9259,-3630,0,-1073,9256,-3639,0,-1076,9252,-3649,0,-1079,9248,-3659,0,-1082,9243,-3670,0,-1085,9239,-3681,0,-1088,9234,-3692,0,-1092,9229,-3704,0,-1095,9224,-3714,0,-1098,9219,-3725,0,-1101,9215,-3734,0,-1104,9211,-3743,0,-1107,9207,-3751,0,-1109,9203,-3757,0,-1111,9201,-3761,0,-1112,9199,-3764,0,-1113,9197,-3765,0,-1113,9197,-3767,0,-1114,9196,-3770,0,-1115,9195,-3775,0,-1116,9193,-3782,0,-1118,9190,-3790,0,-1120,9186,-3799,0,-1123,9182,-3810,0,-1126,9177,-3822,0,-1130,9172,-3834,0,-1133,9166,-3847,0,-1137,9160,-3860,0,-1141,9154,-3873,0,-1145,9148,-3886,0,-1149,9142,-3899,0,-1153,9136,-3912,0,-1157,9130,-3924,0,-1160,9125,-3935,0,-1163,9119,-3945,0,-1166,9115,-3954,0,-1169,9111,-3961,0,-1171,9107,-3967,0,-1173,9104,-3971,0,-1174,9102,-3973,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101,-3974,0,-1175,9101],"Head":[-93,-454,-1,9989,-93,-453,0,9989,-93,-452,4,9989,-93,-451,10,9989,-93,-448,18,9990,-93,-445,27,9990,-93,-442,38,9990,-93,-439,51,9990,-93,-435,64,9990,-93,-431,78,9990,-93,-426,92,9990,-93,-422,106,9990,-93,-418,120,9990,-93,-414,134,9990,-93,-410,147,9990,-94,-406,160,9990,-94,-403,171,9990,-94,-400,180,9990,-94,-398,188,9990,-94,-396,194,9990,-94,-395,198,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,199,9990,-94,-395,198,9990,-94,-395,196,9990,-94,-396,195,9990,-94,-396,193,9990,-94,-397,191,9990,-94,-398,189,9990,-94,-398,186,9990,-94,-399,184,9990,-94,-400,181,9990,-94,-401,179,9990,-94,-401,176,9990,-94,-402,174,9990,-94,-403,171,9990,-94,-404,169,9990,-94,-404,167,9990,-94,-405,165,9990,-94,-405,163,9990,-94,-406,162,9990,-94,-406,161,9990,-94,-406,160,9990,-94,-406,159,9990,-94,-406,159,9990,-94,-407,158,9990,-94,-407,157,9990,-94,-408,155,9990,-93,-408,153,9990,-93,-409,151,9990,-93,-410,148,9990,-93,-411,145,9990,-93,-412,142,9990,-93,-413,138,9990,-93,-414,135,9990,-93,-414,132,9990,-93,-415,129,9990,-93,-416,126,9990,-93,-417,124,9990,-93,-417,122,9990,-93,-418,120,9990,-93,-418,119,9990,-93,-418,119,9990]}}]==]

local raw = {Walk = jsonDecode(RAW_WALK), Run = jsonDecode(RAW_RUN), Flight = jsonDecode(RAW_FLIGHT)}
local walk = decodeClip(RAW_WALK)
local run = decodeClip(RAW_RUN)
local flight = decodeClip(RAW_FLIGHT)
local checks = 0
local function check(ok, message) assert(ok, message); checks += 1 end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-9) end
local function equivalent(a, b)
	local dot = 0
	for i = 1, 4 do dot += a.q[i] * b.q[i] end
	return near(math.abs(dot), 1, 1e-8) and near(a.Position.X, b.Position.X) and near(a.Position.Y, b.Position.Y) and near(a.Position.Z, b.Position.Z)
end
local function pose(c, name, phase)
	local i0, i1, a = atPhase(c, phase)
	return sampleBone(c, name, i0, i1, a)
end
for _, c in ipairs({walk, run, flight}) do
	check(near(c.duration, c.frames / c.fps), "advertised duration")
	for _, track in pairs(c.tracks) do
		for _, transform in ipairs(track) do
			local norm = 0
			for _, q in ipairs(transform.q) do norm += q * q end
			check(near(norm, 1, 1e-10), "decode normalizes quantized quaternion")
		end
	end
end
local i0, i1, a = atPhase(walk, 0)
check(i0 == 1 and i1 == 2 and a == 0, "loop phase zero")
i0, i1, a = atPhase(walk, 1)
check(i0 == 1 and i1 == 2 and a == 0, "loop one wraps exactly")
i0, i1, a = atPhase(walk, (walk.frames - 0.5) / walk.frames)
check(i0 == walk.frames and i1 == 1 and near(a, 0.5), "last frame interpolates to first")
i0, i1, a = atPhase(flight, 1)
check(i0 == flight.frames and i1 == flight.frames and a == 0, "nonloop endpoint holds")
check(equivalent(pose(walk, "Hips", 0), pose(walk, "Hips", 1)), "whole pose wraps")
check(pose(walk, "MissingBone", 0.25) == nil, "absent bone passes through")
local hips = pose(walk, "Hips", 0)
check(near(hips.Position.X, raw.Walk.hips[1] / 1000) and near(hips.Position.Y, raw.Walk.hips[2] / 1000), "hips translation uses local studs")
local left, right = pose(walk, "Hips", 0.37), pose(run, "Hips", 0.37)
local mockBone = {Transform = CFrame.identity}
mockBone.Transform = left:Lerp(right, 0.35)
local blend = mockBone.Transform
check(near(blend.Position.X, left.Position.X * 0.65 + right.Position.X * 0.35), "blend position")
check(equivalent(left:Lerp(right, 0), left) and equivalent(left:Lerp(right, 1), right), "blend endpoints")
local norm = 0
for _, q in ipairs(blend.q) do norm += q * q end
check(near(norm, 1, 1e-10), "blend normalized")
check(equivalent(left:Lerp(frame(left.Position.X, left.Position.Y, left.Position.Z, -left.q[1], -left.q[2], -left.q[3], -left.q[4]), 0.5), left), "shortest quaternion hemisphere")
check(crossedContacts(walk, 0.49, 0.51) == 1, "right contact")
check(crossedContacts(walk, 0.99, 1.01) == 1, "left contact across wrap")
check(crossedContacts(walk, 0.1, 2.1) == 4, "large update keeps all contacts")
local phase = 0
for _ = 1, 120 do phase += walk.speed / 120 / walk.stride end
check(near(phase, walk.speed / walk.stride), "distance matched phase")
check(near(raw.Walk.stride, walk.stride) and near(raw.Run.stride, run.stride), "actual authored clip metadata")
print("PASS " .. checks .. " checks; real Walk/Run/Flight excerpts decode, wrap, sample, blend and contact-count on a pure-Luau mock")
