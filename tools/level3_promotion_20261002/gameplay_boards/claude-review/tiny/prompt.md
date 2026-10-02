Read-only Roblox Luau board-transfer code review. No tools. Return <=180 words: verdict and only material defect/minimal fix. No private reasoning. Source review is not gameplay evidence. Candidate SHA256 f5df8fc430d985722cd400cd69dc2af6db85b3f9e5a6043c72ee63c03b6c1799. Original ten-row TOP SUPPORTERS model renderer listens to ReplicatedStorage value and Rank/Name/Robux changes; cloning loses connections. Its AncestryChanged handler disconnects only when newParent=nil. Current startup builds original ServerLobby then R4 once. R4center(220,30,-760), target panel(190,37.15,-795), unrotated Right face +X points toward center. Board collision Xrelative[-33.05,-29.69] vs lowerwall[-34.85,-33.55], inferred behind; runtime occlusion unverified. Existing R4 must be Owned/Ready before helper called. Apply happens after polish inside pcall, before new model.Parent=workspace; failure restores transfer before model:Destroy(). Original-lobby full rebuild while R4 persists can create a second original board; evaluate this edge case.
```luau
local function supportBoardTransfer(destination, center)
    local installed = destination:FindFirstChild("ZyntraDonationLeaderboardBoard", true)
    if installed then
        assert(installed:IsA("Model"), "Inspect conflicting R4 support board")
        return nil
    end
    local lobby = assert(workspace:FindFirstChild("ServerLobby"), "Original server lobby must precede R4")
    local board
    for _, descendant in ipairs(lobby:GetDescendants()) do
        if descendant.Name == "ZyntraDonationLeaderboardBoard" then
            assert(descendant:IsA("Model") and board == nil, "Inspect conflicting original support boards")
            board = descendant
        end
    end
    assert(board, "Original support board is not ready")
    local panel = board:FindFirstChild("LeaderboardPanel")
    assert(panel and panel:IsA("BasePart") and panel:FindFirstChild("DonationLeaderboardDisplay"),
        "Inspect original support-board renderer before relocation")
    return {
        Board = board,
        Parent = board.Parent,
        Pivot = board:GetPivot(),
        TargetPivot = CFrame.new(center + Vector3.new(-30, 7.15, -35) - panel.Position) * board:GetPivot(),
    }
end
local function applySupportBoardTransfer(transfer, destination)
    if not transfer then return end
    transfer.Board:PivotTo(transfer.TargetPivot)
    -- Never assign a nil direct Parent: the original renderer tears down on nil.
    transfer.Board.Parent = destination
end
local function restoreSupportBoardTransfer(transfer)
    if not transfer then return end
    transfer.Board.Parent = transfer.Parent
    transfer.Board:PivotTo(transfer.Pivot)
end

```
