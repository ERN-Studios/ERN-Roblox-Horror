local function reward(player,mutate)
-- Card 71. Insert this block inside refreshPasses(player), after its initial
-- `if not sessions[player] then return end` guard. Claude owns that shared file.
-- Official username lookup 2026-09-14: Kecoalmutt / AdminNBCRxAria, 10152463945.
-- The user requested the package's two capacity upgrades and ten tokens.
-- Keep a separate grant key so a later real Advanced Equipment purchase still
-- awards its normal benefits. Never alter ReceiptIds or fake pass ownership.
if player.UserId == 10152463945 then
    mutate(player, function(data)
        if data.Grants.FeedbackThanks20260914 == true then return false end
        data.Grants.FeedbackThanks20260914 = true
        data.StaminaLevel += 1
        data.BatteryLevel += 1
        data.Tokens += 10
        return true, "Thanks for your feedback: +5% stamina, +5% battery and 10 Research Tokens", "success"
    end)
end

end
local profile={Grants={},StaminaLevel=3,BatteryLevel=7,Tokens=2,ReceiptIds={'kept'}}
local function apply(_,fn) return fn(profile) end
reward({UserId=99},apply)
assert(profile.Tokens==2)
reward({UserId=10152463945},apply)
reward({UserId=10152463945},apply)
assert(profile.Tokens==12 and profile.StaminaLevel==4 and profile.BatteryLevel==8)
assert(profile.ReceiptIds[1]=='kept' and profile.Grants.AdvancedEquipment==nil)
print('PASS gift transformation: intended user only, repeat no-op, additive upgrades, receipt/pass flags preserved')
