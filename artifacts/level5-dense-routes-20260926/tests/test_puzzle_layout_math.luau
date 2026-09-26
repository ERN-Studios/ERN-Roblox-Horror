-- Offline diagnostic of the current client layout arithmetic; not a native GUI
-- test. Actual font fitting and platform safe areas require the client inspector.
local Catalog=require("../../../ServerScriptService/Level 5 Systems/Level 5 Puzzle Catalog.ModuleScript")
local assertions=0
local function check(value,message) assertions+=1;assert(value,message) end
local function box(x,y,w,h) return {x=x,y=y,w=w,h=h} end
local function intersects(a,b)
	return math.min(a.x+a.w,b.x+b.w)-math.max(a.x,b.x)>0
		and math.min(a.y+a.h,b.y+b.h)-math.max(a.y,b.y)>0
end
local function layout(vw,vh,count)
	local width=math.clamp(vw-32,248,600)
	local height=math.clamp(vh-64,248,330)
	local cell=(width-32-8*(count-1))/count
	local wheelHeight=math.clamp(height-204,44,104)
	local boxes={Title=box(16,12,width-84,30),Close=box(width-52,8,44,44),Instructions=box(16,56,width-32,28),
		Feedback=box(16,95+wheelHeight,width-32,36),Unlock=box(16,height-60,width-32,44)}
	for i=1,count do boxes["Wheel"..i]=box(16+(i-1)*(cell+8),89,cell,wheelHeight) end
	return width,height,boxes
end
local cases={
	{"fallback",800,600,800,564},{"small portrait",320,568,320,532},{"small landscape",568,320,568,284},
	{"phone portrait",390,844,390,766},{"phone landscape",844,390,756,335},{"tablet portrait",768,1024,768,988},
	{"tablet landscape",1024,768,1024,732},{"desktop",1920,1080,1920,1044},{"minimum panel width",280,568,280,532},
}
for gate=1,7 do
	local public=Catalog.Public(gate)
	for _,case in ipairs(cases) do
		local name,vw,vh,safeW,safeH=table.unpack(case)
		local w,h,boxes=layout(vw,vh,public.count)
		check(w<=safeW and h<=safeH,name..": panel exceeds modeled safe bounds")
		for key,b in pairs(boxes) do
			check(b.x>=0 and b.y>=0 and b.x+b.w<=w+.0001 and b.y+b.h<=h+.0001,name..": "..key.." outside panel")
			if key=="Close" or key=="Unlock" or key:sub(1,5)=="Wheel" then check(b.w>=44 and b.h>=44,name..": small touch target") end
			for other,c in pairs(boxes) do if key<other then check(not intersects(b,c),name..": "..key.." overlaps "..other) end end
		end
	end
end
local _,tinyHeight=layout(320,280,4)
check(tinyHeight>244,"Keep tiny-viewport limitation explicit rather than silently claiming all dimensions fit")
print("PASS: "..assertions.." arithmetic assertions across 7 puzzles × "..#cases.." modeled viewport/safe-area pairs.")
print("Known edge: hard minimum 248px height exceeds a 244px usable frame (example 320×280 viewport with 36px top inset). Not a native device or text-fit result.")
