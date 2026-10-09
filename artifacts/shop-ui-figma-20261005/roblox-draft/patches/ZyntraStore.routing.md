# ZyntraStore routing patch for the L4 shop (SHOP_UI_L4_20261005)

Two hunks, applied **in Studio** with `ScriptEditorService:UpdateSourceAsync`
(Studio-first rule), **after** the pull of the drifted ZyntraStore
(`python tools/pull_source_from_studio.py`; Studio was +2015 bytes newer than the
repo on 2026-10-05). Then mirror it back and confirm `--audit` reports 0 drift.

Never apply this to the repo copy and push it: the repo copy is older than Studio.

## What it does

- `openKioskShop(tab)` (SHOP rail button, `PlayerScripts.ZyntraOpenTerminal`, the
  shop prompts) first asks `PlayerScripts.ZyntraShopUIOpen:Invoke(tab)`. If the L4
  window answers `true` it has opened and legacy returns. Anything else
  (no bindable, flag off, RECORDS / SETTINGS / DEV, in a round, a binding
  failure, an error) falls through to the unchanged legacy code.
- The UPGRADES rail button asks the same bridge with `"Upgrades"` (lobby only),
  which also ends the "opens the last tab" bug. `toggleMain` itself is untouched,
  so the dev phone, J and UIRegression's `probe("open")` keep opening legacy.
- No new top-level local (ZyntraStore is near Luau's 200-register ceiling); the
  lookups are locals inside the two function bodies. `player:WaitForChild("PlayerScripts")`
  is ZyntraStore's own idiom (it never yields: this script lives in PlayerScripts)
  and is what `test_zyntra_store_compact.py`'s routing fixture fakes.
- `pcall` around `Invoke`: the bridge's own `OnInvoke` never yields and returns
  `false` on any internal error, and the pcall makes even a missing/odd bindable
  inert.

## Anchors to re-find in the PULLED copy

1. `local function openKioskShop(tab)`, and inside it the block
   ```lua
   	if tab == "Rewards" then
   		openDailyRewards()
   		return
   	end
   ```
   It must be the first statement block, and it must stay **before** hunk 1
   (`"Rewards"` opens Daily Rewards, never the shop).
2. The UPGRADES handler, today exactly:
   ```lua
   openButton.Activated:Connect(function()
   	toggleMain()
   end)
   ```
3. Confirm these still hold in the pulled copy (they decide whether the hunks are
   still correct, not just whether they apply):
   - `player` is the local `Players.LocalPlayer` in scope at both anchors;
   - `ZyntraOpenTerminal`'s handler still calls `openKioskShop(tab)`, and the tab
     names it receives are still `Shop`/`Upgrades`/`Skins`/`Donate`/`Colors`/
     `Records`/`Settings`. **If the +2015 bytes added an `Achievements` tab**, it
     falls through to legacy automatically (the bridge only accepts the five shop
     tabs); decide whether the L4 header needs an entry for it (plan section 3.4);
   - `setMainVisible` still writes `ZyntraStoreOpen` (the L4 window re-asserts
     the attribute against those writes);
   - the rail names `ZyntraShopButton`, `ZyntraOpenButton`, `ZyntraRewardsButton`,
     `ZyntraWheelButton`, `ZyntraMusicButton`, each with
     `SectionButtonContent > SectionCaption`, `SquareSectionBorder` and (REWARDS,
     WHEEL) `NotificationDot` -- the L4 rail skin finds them by these names.

Each anchor must occur exactly once (the dry run below checks that).

## Hunk 1 -- `openKioskShop`, directly after the Rewards block

```diff
 	if tab == "Rewards" then
 		openDailyRewards()
 		return
 	end
+	-- SHOP_UI_L4_20261005: the L4 window ("Zyntra Shop L4") takes the five shop
+	-- tabs when workspace.ShopUIVersion lets it. It answers false for anything
+	-- else (RECORDS, SETTINGS, DEV, in a round, a binding failure) and this
+	-- terminal opens exactly as before. pcall'd: a fault there never costs the shop.
+	do
+		local alt = player:WaitForChild("PlayerScripts"):FindFirstChild("ZyntraShopUIOpen")
+		if alt and alt:IsA("BindableFunction") then
+			local ok, used = pcall(alt.Invoke, alt, type(tab) == "string" and tab or "Shop")
+			if ok and used == true then return end
+		end
+	end
 	if player:GetAttribute("InRound") == true or modalBlocksStore()
```

Inserted text, verbatim (tabs):

```lua
	-- SHOP_UI_L4_20261005: the L4 window ("Zyntra Shop L4") takes the five shop
	-- tabs when workspace.ShopUIVersion lets it. It answers false for anything
	-- else (RECORDS, SETTINGS, DEV, in a round, a binding failure) and this
	-- terminal opens exactly as before. pcall'd: a fault there never costs the shop.
	do
		local alt = player:WaitForChild("PlayerScripts"):FindFirstChild("ZyntraShopUIOpen")
		if alt and alt:IsA("BindableFunction") then
			local ok, used = pcall(alt.Invoke, alt, type(tab) == "string" and tab or "Shop")
			if ok and used == true then return end
		end
	end
```

## Hunk 2 -- the UPGRADES rail handler

```diff
 openButton.Activated:Connect(function()
-	toggleMain()
-end)
+	-- SHOP_UI_L4_20261005: UPGRADES opens the L4 window on Upgrades when it
+	-- answers true, which also ends "opens the last tab". In a round this button
+	-- is the dev phone, so the bridge is not asked there.
+	local alt = player:WaitForChild("PlayerScripts"):FindFirstChild("ZyntraShopUIOpen")
+	if alt and alt:IsA("BindableFunction") and player:GetAttribute("InRound") ~= true then
+		local ok, used = pcall(alt.Invoke, alt, "Upgrades")
+		if ok and used == true then return end
+	end
+	toggleMain()
+end)
```

Replacement, verbatim (tabs):

```lua
openButton.Activated:Connect(function()
	-- SHOP_UI_L4_20261005: UPGRADES opens the L4 window on Upgrades when it
	-- answers true, which also ends "opens the last tab". In a round this button
	-- is the dev phone, so the bridge is not asked there.
	local alt = player:WaitForChild("PlayerScripts"):FindFirstChild("ZyntraShopUIOpen")
	if alt and alt:IsA("BindableFunction") and player:GetAttribute("InRound") ~= true then
		local ok, used = pcall(alt.Invoke, alt, "Upgrades")
		if ok and used == true then return end
	end
	toggleMain()
end)
```

## Apply in Studio (after the pull, in this session's Studio slot)

1. Read the live source via `execute_luau` reading `.Source` (never `script_read`).
2. Assert each anchor occurs exactly once; insert hunk 1 after anchor 1, replace
   anchor 2 with hunk 2; write with `ScriptEditorService:UpdateSourceAsync`.
3. Read `.Source` back and compare byte for byte with the intended text.
4. `python tools/pull_source_from_studio.py` (or `tools/record_synced_source.py`),
   then `python tools/pull_source_from_studio.py --audit` -> 0 drift.
5. Run `tools/studio_compile_probe.luau` (register ceiling).
6. Re-run `test_zyntra_store_compact.py`, `test_rail_dots_intro.py`,
   `test_reentry_dismissal.py`.

## Offline dry run already done (2026-10-05, against the REPO copy at HEAD)

- Both anchors found exactly once; the patched file compiles with
  `luau-compile -O0` (no "Out of local registers").
- With the patched copy swapped in (temp directory, mirror untouched):
  `test_zyntra_store_compact.py` 544 checks OK, `test_rail_dots_intro.py` 20 OK,
  `test_reentry_dismissal.py` 37 OK.
- `test_lobby_shop_display.py` fails **with or without** the patch
  ("expected 8 product textures, found 10"): pre-existing at HEAD, unrelated.

## Validated against the Studio copy (2026-10-05 evening)

Source: `_local/shop-ui-figma/studio-turn/src/ZyntraStore.studio.lua` (201,295 B, LF).
The machine-applicable form is `ZyntraStore.routing.json` (`[{name, old, new}]`);
`apply_patch.py` applies it and refuses unless every `old` occurs exactly once
before and every `new` exactly once after (so a second run fails, never doubles).

- Both anchors exist exactly once. Hunk 1's `old` is the Rewards block plus the
  legacy guard right after it, so the insert lands between the two.
- Answers to section 3 above, read from that copy: `player` is
  `Players.LocalPlayer` (line 17); `ZyntraOpenTerminal` still calls
  `openKioskShop(tab)`; the tab list is unchanged (Upgrades, Shop, Skins, Donate,
  Colors, Records, Settings, + Dev for developers): **no Achievements tab** (the
  achievements are published as the player attribute `ZyntraAchievements` by
  ZyntraMonetization; no ZyntraStore page reads it); `setMainVisible` still
  writes `ZyntraStoreOpen` (line 3624); all five rail names, `SectionButtonContent >
  SectionCaption`, `SquareSectionBorder` (a UIStroke; legacy writes only its
  Transparency and Enabled) and `NotificationDot` are unchanged.
- The +2,784 B against the repo copy are a DEV row (`DROP A BODY`, Level 5), the
  legacy Shop page's SHOP_GRID_20261003 grid + detail pane, and
  `Level6PlaygroundPreview` in the re-entry modal's round test. None touches
  the anchors, the rail or the modal flag.
- `apply_patch.py` -> `ZyntraStore.patched.lua` (202,362 B). `luau-compile -O0
  --null` compiles it. Register headroom, measured by appending top-level locals
  until "Out of local registers ... exceeded limit 200": **45 before and 45
  after** (155 top-level locals; the hunks add none).
- Existing tests, with the Studio copy and then the patched copy swapped into a
  temp tree: `test_rail_dots_intro.py` 20 OK and `test_reentry_dismissal.py` 37 OK
  on both. `test_zyntra_store_compact.py` FAILS on both, identically, at its
  static shop-card checks ("the shop cell height is unchanged", then a
  KeyError on `IconTop`): its arithmetic mirror is of the pre-SHOP_GRID list
  card. Run lane by lane, its routing lane passes 39 checks on the patched copy
  (rail 123, layout 121, modals 19, tabs/supplies OK); only the shop lane is
  stale. That harness needs updating to SHOP_GRID_20261003 after the pull,
  whoever owns that change; it is not caused by this patch.

Before writing to Studio, re-run `apply_patch.py` against the live `.Source`
(read via `execute_luau`), write the result with `UpdateSourceAsync`, and read
`.Source` back: it must equal the script's output byte for byte.

## Rollback

Revert these two hunks (Studio first, then mirror): `install/03_zyntrastore_patch.py --revert`
reverses them on the live source through the same compare-and-swap. With the L4 LocalScript
absent or disabled the hunks are inert anyway: `FindFirstChild` finds no bindable.
