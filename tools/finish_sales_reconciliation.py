"""Replace the ceiling import with an audited baseline correction."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'ServerScriptService/ZyntraMonetization.Script.lua'
s=p.read_text(encoding='utf-8')
a=s.index('-- OVERLAP RULE.');b=s.index('local SALES_IMPORT_STREAM_FIELDS',a)
s=s[:a]+'''-- Each export includes a separately audited per-buyer snapshot. The complete
-- pre-cutoff receipt sets were checked in Creator Dashboard; CSV ids are NOT
-- PurchaseIds. Add (CSV total - audited recorded total) once. Later receipts
-- remain on top, unlike max(current, CSV), which loses old missing purchases
-- whenever newer purchases overlap. Refuse drift below the baseline or missing
-- audited receipts. Pass/private-server rows have their own permanent markers.
'''+s[b:]
s=s.replace('or type(source.SourceKey) ~= "string"','or type(source.Baselines) ~= "table"\n\t\tor type(source.SourceKey) ~= "string"',1)
s=s.replace('salesImportReadback("RowsInvalid", invalidRows)','salesImportReadback("RowsInvalid", invalidRows)\n\tif invalidRows > 0 or userCount == 0 then return salesImportReadback("Status", "invalid-rows") end',1)
s=s.replace('-- max or marker-guarded.','-- guarded by a permanent source/row marker.',1)
s=s.replace('store:UpdateAsync(claimKey, function(current)\n\t\t\tif type(current)', 'store:UpdateAsync(claimKey, function(current)\n\t\t\tclaimed = false\n\t\t\tif type(current)',1)
a=s.index('\tlocal function applyRows(data, rows, outcome)');b=s.index('\n\tfor userId, rows in pairs(byUser) do',a)
s=s[:a]+'''\tlocal function applyRows(data, rows, outcome, userId)
		outcome.Pending, outcome.Applied, outcome.Skipped = false, 0, 0
		outcome.Recorded = recordedSupportRobux(data)
		outcome.Rejected, outcome.Ambiguous, outcome.IdMatches = false, false, 0
		if data.SalesImport.Sources[sourceKey] then
			outcome.Skipped = #rows
			return false
		end
		local baseline = source.Baselines[tostring(userId)]
		local totals, productRows, passAdd = {DonationRobux=0, UtilityRobux=0}, 0, 0
		local markers = data.SalesImport.Rows
		for _, row in ipairs(rows) do
			if row.Field == "PassRobux" then
				if not markers[row.Marker] then passAdd += row.Price end
			else
				productRows += 1
				totals[row.Field] += row.Price
				-- A different source already touched this product row. It needs a
				-- newly audited baseline, never an automatic second correction.
				if markers[row.Marker] then outcome.Rejected = true end
			end
		end
		if type(baseline) ~= "table" or type(baseline.ReceiptIds) ~= "table"
			or #baseline.ReceiptIds ~= productRows then outcome.Rejected = true end
		local receipts, audited = {}, {}
		for _, id in ipairs(data.ReceiptIds) do receipts[id] = true end
		if not outcome.Rejected then
			for _, id in ipairs(baseline.ReceiptIds) do
				if type(id) ~= "string" or audited[id] or not receipts[id] then outcome.Rejected = true end
				audited[id] = true
			end
		end
		local additions, totalAdd = {}, passAdd
		if not outcome.Rejected then
			for field, total in pairs(totals) do
				local before = baseline[field]
				if not isSafeSupportAmount(before) or before > total or data[field] < before then
					outcome.Rejected = true
				else
					additions[field] = total - before
					totalAdd += total - before
				end
			end
		end
		if outcome.Rejected or totalAdd > MAX_SAFE_SUPPORT - outcome.Recorded then
			outcome.Rejected = true
			return false
		end
		-- All validation precedes the first mutation. UpdateAsync retries get a
		-- fresh profile and either add this same delta or see the source marker.
		for field, add in pairs(additions) do data[field] += add end
		data.PassRobux += passAdd
		for _, row in ipairs(rows) do markers[row.Marker] = true end
		data.SalesImport.Sources[sourceKey] = true
		outcome.Applied = #rows
		outcome.Recorded = recordedSupportRobux(data)
		outcome.Pending = true
		return true
	end
	local processed = 0
'''+s[b:]
s=s.replace('applyRows(data, rows, outcome)','applyRows(data, rows, outcome, userId)')
s=s.replace('\t\tif okWrite then\n\t\t\t-- Changed,','\t\tprocessed += 1\n\t\tif okWrite and not outcome.Rejected then\n\t\t\t-- Changed,',1)
s=s.replace('if recorded > 0 then syncSupportTotal(userId, recorded) end','if recorded > 0 and not syncSupportTotal(userId, recorded) then failed += 1 end',1)
s=s.replace('\n\tsalesImportReadback("Buyers", userCount)','\n\tfailed += userCount - processed -- shutdown cannot mark unvisited buyers done\n\tsalesImportReadback("Buyers", userCount)',1)
p.write_text(s,encoding='utf-8')
print('Reconciliation now adds audited deltas; failed guards/ordered writes keep job incomplete')
