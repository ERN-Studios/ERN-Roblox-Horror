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
