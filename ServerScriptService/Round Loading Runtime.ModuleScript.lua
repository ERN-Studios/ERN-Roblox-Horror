-- One deadline owns admission, generation, character loading and client entry.
-- The injected scheduler lets the suite exercise the production timeout policy
-- without a real engine request or sixty seconds of wall time.
local Loading = {}
Loading.TimeoutSeconds = 60
Loading.Version = "2026-09-05.2"

-- StarterCharacter is temporarily parked during a lobby avatar load, so every
-- engine character request shares this gate. An expired caller cannot release
-- a worker's token, and a cancelled queue entry never starts an engine request.
function Loading.NewCharacterGate(wait)
 local gate = {Owner = nil}
 function gate:Acquire(allowed)
  while self.Owner do
   if allowed and not allowed() then return nil end
   wait()
  end
  if allowed and not allowed() then return nil end
  local token = {}
  self.Owner = token
  return token
 end
 function gate:Release(token)
  if not token or self.Owner ~= token then return false end
  self.Owner = nil
  return true
 end
 return gate
end

function Loading.New(env)
 local serial = 0
 local runtime = {}
 function runtime:Begin(members)
  serial += 1
  local attempt = {
   Token = tostring(env.Identity or "loading") .. ":" .. tostring(serial),
   Deadline = env.Now() + Loading.TimeoutSeconds,
   State = "loading", Members = {}, Expected = {},
  }
  function attempt:SetMembers(group)
   if self.State ~= "loading" then return false end
   self.Members = table.clone(group)
   return true
  end
  function attempt:Fail(reason)
   if self.State ~= "loading" then return false end
   self.State, self.Reason = "failed", reason
   env.Failed(self, reason)
   return true
  end
  function attempt:IsOpen()
   if self.State == "loading" and env.Now() >= self.Deadline then
    self:Fail("LOADING_TIMEOUT")
   end
   return self.State == "loading"
  end
  function attempt:Remaining()
   return math.max(0, self.Deadline - env.Now())
  end
  -- The worker may still be inside an uncancellable engine operation when its
  -- caller times out. It owns its lock until it really returns; callers must
  -- check IsOpen again before applying its result.
  function attempt:Run(work)
   if not self:IsOpen() then return false end
   local done, result = false, nil
   env.Spawn(function()
    result = table.pack(pcall(work))
    done = true
   end)
   while self:IsOpen() and not done do env.Wait(.05) end
   if not self:IsOpen() then return false end
   if not result[1] then
    self:Fail("LOADING_ERROR")
    if env.Warn then env.Warn(tostring(result[2])) end
    return false
   end
   return true, table.unpack(result, 2, result.n)
  end
  function attempt:Prepare(member, character, level, position)
   if not self:IsOpen() or not table.find(self.Members, member) then return false end
   self.Expected[member] = {Character = character, Level = level, Position = position, Ready = false}
   env.Prepare(member, self, self.Expected[member])
   return true
  end
  function attempt:Acknowledge(member, payload)
   if not self:IsOpen() or type(payload) ~= "table" or payload.Token ~= self.Token then return false end
   local expected = self.Expected[member]
   if not expected or payload.Character ~= expected.Character or payload.Level ~= expected.Level
    or not env.Present(member) or not env.Validate(member, expected) then return false end
   expected.Ready = true
   expected.ReadyAt = env.Now()
   return true
  end
  function attempt:AwaitReady()
   local nextNotice = 0
   while self:IsOpen() do
    local live, pending = 0, 0
    for _, member in ipairs(self.Members) do
     if env.Present(member) then
      live += 1
      local expected = self.Expected[member]
      if not expected or not expected.Ready or env.Now() - (expected.ReadyAt or 0) > 2
       or not env.Validate(member, expected) then
       pending += 1
       if expected and env.Now() >= nextNotice then
        env.Prepare(member, self, expected)
       end
      end
     end
    end
    if live == 0 then self:Fail("PARTY_LEFT"); return false end
    if pending == 0 then return true end
    if env.Now() >= nextNotice then nextNotice = env.Now() + 1 end
    env.Wait(.1)
   end
   return false
  end
  function attempt:Commit()
   if not self:IsOpen() then return false end
   local live = 0
   for _, member in ipairs(self.Members) do
    if env.Present(member) then
     live += 1
     local expected = self.Expected[member]
     if not expected or not expected.Ready or env.Now() - (expected.ReadyAt or 0) > 2
      or not env.Validate(member, expected) then return false end
    end
   end
   if live == 0 then self:Fail("PARTY_LEFT"); return false end
   self.State = "ready"
   return true
  end
  attempt:SetMembers(members or {})
  env.Delay(Loading.TimeoutSeconds, function() attempt:IsOpen() end)
  return attempt
 end
 return runtime
end

-- A final source snapshot resolves early Continue estimates even when the last
-- undecided member opts out and nobody remains to carry a final teleport packet.
function Loading.CohortSnapshot(sessionId, level, userIds)
 local ids, seen = {}, {}
 for _, id in ipairs(userIds) do
  if type(id) == "number" and id % 1 == 0 and not seen[id] then
   seen[id] = true
   ids[#ids + 1] = id
  end
 end
 table.sort(ids)
 return {SessionId = sessionId, Level = level, UserIds = ids, Version = 1}
end

function Loading.ReadCohort(snapshot, sessionId, level)
 if type(snapshot) ~= "table" or snapshot.Version ~= 1
  or snapshot.SessionId ~= sessionId or snapshot.Level ~= level
  or type(snapshot.UserIds) ~= "table" or #snapshot.UserIds > 6 then return nil end
 local ids = {}
 for _, id in ipairs(snapshot.UserIds) do
  if type(id) ~= "number" or id % 1 ~= 0 or ids[id] then return nil end
  ids[id] = true
 end
 return ids, #snapshot.UserIds
end

-- Source departures still belong to the travelling cohort. Only a member this
-- DESTINATION has actually observed can cease to be expected when they leave.
-- Keep final packet authority after its carrier leaves, and key presence by
-- UserId so a reconnect with a new Player instance restores that expectation.
function Loading.NewArrivalTracker(selectSession)
 local sessions, present = {}, {}
 local tracker = {}
 local function remember(group)
  local record = sessions[group.SessionId]
  if not record then
   record = {SeenHere = {}, Level = group.Level}
   sessions[group.SessionId] = record
  end
  if record.Level ~= group.Level then return nil end
  if group.Final == true and type(group.Expected) == "number" then
   record.Final = true
   record.Expected = math.max(record.Expected or 0, group.Expected)
  end
  if group.CohortUserIds then record.CohortUserIds = table.clone(group.CohortUserIds) end
  return record
 end
 function tracker:RememberArrival(entry)
  local member = entry.Member
  if not member or type(member.UserId) ~= "number" then return end
  local group = selectSession({entry})
  if group then
   local record = remember(group)
   if record then record.SeenHere[member.UserId] = true end
  end
 end
 function tracker:Observe(entries)
  present = {}
  for _, entry in ipairs(entries) do
   local member = entry.Member
   if member and type(member.UserId) == "number" then
    -- An unreadable packet is not a departure: arrivalEntries still includes
    -- this Player, even when GetJoinData's pcall returned no usable data.
    present[member.UserId] = true
    self:RememberArrival(entry)
   end
  end
 end
 function tracker:Apply(group)
  if not group then return nil end
  local record = remember(group)
  if not record or not record.Final then return group end
  local result = table.clone(group)
  result.Final = true
  local departed = 0
  for id in pairs(record.SeenHere) do
   if not present[id] and (not record.CohortUserIds or record.CohortUserIds[id]) then
    departed += 1
   end
  end
  result.Expected = math.max(0, record.Expected - departed)
  if record.CohortUserIds then
   result.CohortUserIds = record.CohortUserIds
   result.Members = {}
   for _, member in ipairs(group.Members) do
    if record.CohortUserIds[member.UserId] then result.Members[#result.Members + 1] = member end
   end
  end
  return result
 end
 return tracker
end

return Loading
