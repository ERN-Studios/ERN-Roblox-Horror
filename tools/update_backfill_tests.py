from pathlib import Path
p=Path(__file__).resolve().parent/'tests/test_leaderboard_backfill.py'
s=p.read_text(encoding='utf-8')
a=s.index('        -- Two rows the import');b=s.index('\n    }\nend',a)
s=s[:a]+s[b:]
s=s.replace('Rows = opts.rows or rows()}','''Rows = opts.rows or rows(), Baselines = {
        ["101"]={DonationRobux=0,UtilityRobux=29,ReceiptIds={"live-a","live-old"}},
        ["102"]={DonationRobux=0,UtilityRobux=29,ReceiptIds={"syn-102-a"}},
        ["103"]={DonationRobux=0,UtilityRobux=0,ReceiptIds={}},
        ["104"]={DonationRobux=10,UtilityRobux=0,ReceiptIds={"live-b"}},
        ["105"]={DonationRobux=0,UtilityRobux=0,ReceiptIds={"old105"}},
    }}''')
s=s.replace('ReceiptIds = {"live-a"}', 'ReceiptIds = {"live-a", "live-old"}')
s=s.replace('w.db.u_104 = w.normalize', 'w.db.u_105 = w.normalize({ReceiptIds={"old105"}})\n    w.db.u_104 = w.normalize')
s=s.replace('{UtilityRobux = 0, Tokens = 5}', '{UtilityRobux = 0, Tokens = 5, ReceiptIds={"old105"}}')
s=s.replace('{UtilityRobux = 0, Tokens = 0}', '{UtilityRobux = 0, Tokens = 0, ReceiptIds={"old105"}}')
s=s.replace('ZyntraSalesImportRowsInvalid, 2','ZyntraSalesImportRowsInvalid, 0')
s=s.replace('ZyntraSalesImportRowsApplied, 5','ZyntraSalesImportRowsApplied, 7')
s=s.replace('ZyntraSalesImportRowsAlreadyCounted, 2','ZyntraSalesImportRowsAlreadyCounted, 0')
s=s.replace('ZyntraSalesImportIdMatches, 1','ZyntraSalesImportIdMatches, 0')
s=s.replace('ZyntraSalesImportAmbiguous, 1','ZyntraSalesImportAmbiguous, 0')
s=s.replace('#w:profile(101).ReceiptIds, 1','#w:profile(101).ReceiptIds, 2')
s=s.replace('SalesImport.Sources.src_b, nil','SalesImport.Sources.src_b, true')
s=s.replace('second.attrs.ZyntraSalesImportProfilesChanged, 0','second.attrs.ZyntraSalesImportProfilesChanged, 1')
s=s.replace('eq(w:profile(105).UtilityRobux, 29, "the ceiling never lowers spend recorded this session")','eq(w:profile(105).UtilityRobux, 58, "old missing sale plus later receipt both survive")')
s=s.replace('eq(w.sessions[player].data.UtilityRobux, 29, "the session copy still matches the profile")','eq(w.sessions[player].data.UtilityRobux, 58, "the session copy includes old and later spend")')
s=s.replace('str(Path(directory) / "out.lua"), "--source-key", "src_test"]','str(Path(directory) / "out.lua"), "--source-key", "src_test", "--profile-audit", str(path)]')
anchor='-- Absent module, unusable module, and Studio are all no-ops.'
extra='''-- Reject drift before changing any field or marking the source.
for _, mode in {"missing-receipt", "reduced-total", "missing-baseline", "bad-count"} do
    local w = seed(world())
    if mode == "missing-receipt" then w.db.u_101.ReceiptIds = {"live-a"}
    elseif mode == "reduced-total" then w.db.u_101.UtilityRobux = 10
    elseif mode == "missing-baseline" then w.source.Baselines["101"] = nil
    else w.source.Baselines["101"].ReceiptIds = {"live-a"} end
    local before = w.db.u_101.UtilityRobux
    w.run()
    eq(w.db.u_101.UtilityRobux, before, mode .. " cannot mutate money")
    eq(w.db.u_101.SalesImport.Sources.src_a, nil, mode .. " cannot mark source")
    eq(w.db.salesimport_src_a.Done, false, mode .. " leaves job incomplete")
end

-- Later receipts before migration are additive, not a reason to use max().
do
    local w=seed(world())
    w.db.u_101.UtilityRobux += 30
    table.insert(w.db.u_101.ReceiptIds,"after-export")
    w.run()
    eq(w.db.u_101.UtilityRobux,88,"58 export + 30 later; ceiling would wrongly give 59")
end

-- Invalid rows abort the entire source before a claim is acquired.
do
    local w=seed(world())
    table.insert(w.source.Rows,{UserId=0,Price=5,Stream="utility",Marker="bad"})
    w.run()
    eq(w.writes,0,"invalid rows never produce a partial import")
    eq(w.attrs.ZyntraSalesImportStatus,"invalid-rows","invalid source reports refusal")
end

'''
s=s.replace(anchor,extra+anchor)
s=s.replace('Covers: per-stream ceiling never double counts and never lowers a total;', 'Covers: audited corrections preserve later purchases without double counting;')
p.write_text(s,encoding='utf-8')
print('Updated fake-store scenarios for audited deltas and drift guards')
