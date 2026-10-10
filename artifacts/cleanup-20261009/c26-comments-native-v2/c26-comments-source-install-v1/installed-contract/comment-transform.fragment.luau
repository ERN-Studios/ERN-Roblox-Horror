-- Function fragment only; Root must wrap fresh native exact identity/metadata/Source/editor CAS.
-- SHA and patches must come from the reviewed immutable proposal. No native calls here.
local function transformC26(current, reverse, patches, fromSHA256, toSHA256, sha)
 assert(sha(current)==fromSHA256,"Current native Source changed")
 local result=current
 for i=1,#patches do
  local index=if reverse then #patches-i+1 else i
  local patch=patches[index]
  local old,new=if reverse then patch.new else patch.old,if reverse then patch.old else patch.new
  assert(#old>0 and #new>0,"Exact nonempty comment anchors required")
  local start,finish=result:find(old,1,true)
  assert(start and not result:find(old,finish+1,true),"Unique exact comment anchor changed")
  result=result:sub(1,start-1)..new..result:sub(finish+1)
 end
 assert(sha(result)==toSHA256,"Comment transform differs from reviewed Source")
 return result
end
