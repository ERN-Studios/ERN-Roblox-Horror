-- Bounds from actual patched anchor validation; native CFrame/support checked by parent.
local function finite(value)
	return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function valid(surfaceLift)
 if surfaceLift==nil then surfaceLift=0 end
 return not (not finite(surfaceLift) or surfaceLift<0 or surfaceLift>.48)
end
local n=0
local function check(v,expect,why) n+=1;assert(valid(v)==expect,why) end
check(nil,true,"legacy zero")
check(0,true,"zero")
check(.12,true,"one layer")
check(.36,true,"three layers")
check(.48,true,"closed maximum")
check(-.00001,false,"negative")
check(.480001,false,"above cap")
check(math.huge,false,"infinity")
check(-math.huge,false,"negative infinity")
check(0/0,false,"NaN")
check("0.12",false,"string")
check(false,false,"boolean")
check({},false,"table")
print("PASS "..n.." floor-surface input bounds")
