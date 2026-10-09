# 568 × 270 compact Continue display fixture

Prepared against the installed RoundUI `eaf4053bfdd165089045413c3999dd91b3f78187ae528a1947e1068a0765f7de`. Nothing was executed in Studio and no production file was changed. Both full snippets compile; `prepared.json` records their hashes.

## Exact source finding

- `UIDevice` lines52–70 and667–672: `ForceTouchUI` changes the form-factor decision; `UIRegressionViewport` replaces the viewport used by the layout calculation. They do not set `Camera.ViewportSize` or resize any GuiObject.
- `UIDevice` lines752 onward builds synthetic inset rectangles; absent stated topbar margins use the host's measured topbar. `InsetArea` and `LocalPosition` use these synthetic rectangles. Therefore568×270 alone does not specify a universal available strip height. The observed58px topbar gives `floor(-58 + 270*.34 - 6 - 2) = 25` pixels. The earlier767×274 native case gave27. A36px topbar would give47 pixels and would not exercise compact mode.
- RoundUI lines1274 onward sets RoundEnding to Position(0,0), Anchor(0,0), Size(1,0,1,0) on every `applyLayout`. Its parent is the actual ScreenGui. Title geometry remains scale-based on that actual root. `completion.layoutChoices` uses the UIDevice frame and positions/sizes its list using offsets. Setting only the two attributes therefore can produce real568px list/text widths within a much larger actual root, while its title still resolves against the actual window.
- `UIRegression` lines3258–3273 explicitly documents this distinction. `ScreenGuiFrame`/`ResolveRect` at3314 onward resolve the intended synthetic rectangle analytically. They do not physically resize the root or turn synthetic coordinates into native-device evidence.

Do not label an attribute-only run as a physically568×270/emulator run. An actual Studio Device Emulator or physical client window must be measured separately with the viewport override cleared. `ForceTouchUI=true` alone also does not prove touch hardware.

## Root sequence

Use a quiet lobby on both server and chosen client, outside any real intermission. No actual objective or party state changes are needed.

1. Client Command Bar: run `client-fixture.luau` with `ACTION="apply"`. This borrows only `UIRegressionViewport=Vector2.new(568,270)` and `ForceTouchUI=true`, saves prior values and installs an automatic owned restoration after240seconds. It does not change RoundEnding.Size, any text, scroll or input state. Reapplying requires restoration first.
2. Server Command Bar: set `TARGET_USER_ID` explicitly if more than one real player exists. Run `server-display-six.luau` with its default `ACTION="begin-rows"`. The existing RoundStatus handlers receive a synthetic win and then six display rows in order. Row1 is exactly20W characters with CONTINUE; row5 is20alphabetical characters with CONTINUE. The other rows are named TEST_ fixtures. These are not six physical players. The negative serial cannot authorize a real transfer.
3. Client: run the same client file with `ACTION="measure"`. Require `Exact568CompactLayout=true`, `SixExpectedRows=true`, `List.Visible=true`, `AllGlyphsFitOwnRows=true` and `AllRowsHaveReachableFullScrollPosition=true`. If the compact flag isfalse, the topbar/inset configuration did not exercise this case; the report includes the inherited/stated inset evidence and must not be counted as compact acceptance.
4. Root can scroll the actual list with the mouse and re-run measure. `SuggestedScrollY` is diagnostic only and is never assigned by the snippet. Capture each row fully visible at some actual scroll position. `CurrentlyFullyInWindow` plus exact text and screenshot establishes visibility at the sampled position; mathematical reachability alone is not evidence of a successful mouse interaction. Check20W text especially—two compact columns can expose horizontal overflow.
5. Client `ACTION="restore"` restores the two borrowed values only while they still equal this fixture's expected values, and cancels its timer. Conflicting external values are reported and preserved. Server `ACTION="reset"` uses the existing lobby display event to hide/reset the synthetic completion UI. Neither step changes server round attributes, actual routing roster, Player identities, character state or production source.

For root's separate actual simulator/window check, clear the synthetic viewport through restoration, retain the real display and run only `ACTION="measure"` after the six-row display event. `NativeGeometryEvidence` requires no synthetic viewport and an actual root matching the engine inset frame. `ActualPhysicalDisplay568x270` measures `GuiService:GetInsetArea(None)`, not a guessed Camera viewport. Camera.ViewportSize may be device-safe rather than the full display. These fields do not certify physical touch hardware or successful scrolling by themselves.

## Metrics and limits

The probe reports native camera/display/ScreenGui rectangles, actual RoundEnding dimensions, the UIDevice requested frame, existing inset overrides and the actual title separately. It never combines them into a blanket UI-pass flag. While an override is active, root/frame mismatch is expected and is reported explicitly.

For every actual `PartyChoice1..6`, it checks exact synthetic identity/choice, glyph bounds within the row, TextFits and whether the entire row can fit at a reachable scroll position in the actual list's AbsoluteWindowSize. It distinguishes that from being fully visible now. All six visible row identities are required. The fixed-offset list can supply useful native font-width measurements even when the parent remains larger; those measurements do not establish title/list geometry on a568×270 physical display.

There is no new client hook for `completion.applyChoices`; it remains private. The server fixture deliberately reuses the already reviewed RemoteEvent display path. No local synthetic text rewrite is being presented as evidence that the real handler accepts/rendered the names. Full gameplay,15second transport, real multiplayer and input acceptance remain in root's separate native session evidence.
