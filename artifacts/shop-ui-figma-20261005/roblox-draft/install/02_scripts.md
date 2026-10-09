# 02 - install the three new scripts (SHOP_UI_L4_20261005)

Run after `01_templates.luau` reported `"ok": true`. `tools/install_new_scripts.py`
creates each script in Studio through `multi_edit` (the push tools cannot create
scripts), reads `.Source` back, compares it byte for byte, and only then writes a
`synced` manifest item.

## 1. Copy the drafts to their mirror paths (the main session does this)

From `G:/Roblox/MongoTV`:

```
mkdir -p ReplicatedStorage/ZyntraShopUI
cp "artifacts/shop-ui-figma-20261005/roblox-draft/ReplicatedStorage/ZyntraShopUI/ShopBinder.ModuleScript.lua" ReplicatedStorage/ZyntraShopUI/ShopBinder.ModuleScript.lua
cp "artifacts/shop-ui-figma-20261005/roblox-draft/ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua" ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua
cp "artifacts/shop-ui-figma-20261005/roblox-draft/StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua" "StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua"
```

All three are pure ASCII with LF endings (non-ASCII is written as `\u{...}`), so
`install_new_scripts.py`'s `json.dumps` path cannot break the Luau parse.

## 2. Dry run

```
python tools/install_new_scripts.py --dry-run ReplicatedStorage/ZyntraShopUI/ShopBinder.ModuleScript.lua ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua "StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua"
```

Expected, exactly three lines and exit code 0:

```
PLAN ModuleScript game.ReplicatedStorage.ZyntraShopUI.ShopBinder  <-  ReplicatedStorage/ZyntraShopUI/ShopBinder.ModuleScript.lua
PLAN ModuleScript game.ReplicatedStorage.ZyntraShopUI.ShopData  <-  ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua
PLAN LocalScript  game.StarterPlayer.StarterPlayerScripts.Zyntra Shop L4  <-  StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua
```

## 3. Real run

```
python tools/install_new_scripts.py ReplicatedStorage/ZyntraShopUI/ShopBinder.ModuleScript.lua ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua "StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua"
```

Expected: one `VERIFIED <path>` per script, exit code 0, and three new `synced`
items in `studio-sync-manifest.json` (`counts.scripts` goes up by 3).

- `DIFFERS ...` means a script of that name already exists with other source.
  Do not pass `--overwrite` blind: read what is there first (another session may
  have installed an older draft).
- `FAILED ... class` means the script landed with the wrong class or not at all.

The LocalScript is inert until `04_flag.luau` sets `ShopUIVersion`: with the flag
unset `wantsL4()` is false, the bridge answers false, and no skin is applied.

## 4. Compile probe

`tools/studio_compile_probe.luau` (or offline:
`luau-compile.exe -O0 --null <file>` on each of the three). They compiled offline
at 0.737 on 2026-10-06.

## Rollback

Delete the three scripts in Studio (Explorer, or `execute_luau`:
`game.StarterPlayer.StarterPlayerScripts["Zyntra Shop L4"]:Destroy()` and the two
modules under `ReplicatedStorage.ZyntraShopUI`), delete the three mirror files and
remove their three items from `studio-sync-manifest.json`. ZyntraStore needs no
change: with the LocalScript gone `FindFirstChild("ZyntraShopUIOpen")` is nil and
both routing hunks fall through to legacy.
