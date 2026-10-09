# Actual image IDs, source still prepared

Root uploaded exactly the approved `shops-v2.png` and `upgrades-v2.png` through the existing Studio tool. The verbatim two-entry response is `upload-result.json`; its file was saved **2026-09-10 12:34:44.4261175 UTC**. That timestamp describes the saved evidence file, not an invented tool execution timestamp. Root closed the temporary local file server.

| Image | Actual returned image asset |
| --- | --- |
| shops | `rbxassetid://132462891522145` |
| upgrades | `rbxassetid://119432640057145` |

Root subsequently reported that actual-client `ContentProvider:PreloadAsync` returned `Enum.AssetFetchStatus.Success` for both assets in the experience. The temporary disabled ScreenGui was removed; the immediate ImageLabels still reported **IsLoaded=false**. Therefore this is fetch evidence only, not a claim of rendered icons or native button acceptance. The actual installed buttons still require `Image`/`IsLoaded`/pixel, Gotham, click and guard checks and final independent **10/10**.

The ID-filled proposals are now frozen:

- Current Store `749afb83…8151` → **`e9cd247637428f721bb05588e7c4b07242271aa565d379e40818123f0370d6db`**.
- ESP + copy `88f25ffe…cbb6` → **`4745afcf3e9e0117fc38ca2fb463aa47811789b5ff9780d84e62b200a750e8c1`**.
- With DEV respawn `596ff4f4…4093` → **`d1cf6172a1643ce2266a000eb120fed47ad1d7a40c0b106e70ba6b5ef9dc221a`**.

`pre-upload/` preserves the prior reviewed empty-ID sources and reports. `verify_image_ids.py` proves byte-for-byte that each new whole source differs from its reviewed counterpart only in the two image strings. The actual builder test verifies both ImageLabel values against the saved upload response; **319 checks / nine layouts / one specific negative / three whole compiles pass**. No source was installed or published by this agent. `manifest.installable=true` means actual image IDs are supplied, not that native acceptance or publication occurred.
