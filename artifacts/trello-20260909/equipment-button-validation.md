# Clearer lobby Equipment button

Trello: IS3zOeKP. Only `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` changed. Exact backup: `equipment-button-before.lua`; exact diff: `equipment-button.diff`.

The lobby opener now reads **UPGRADES & GEAR** in the existing Gotham Bold/teal/dark style. Desktop uses 280×64 at the same 18-pixel right margin and 20-pixel top offset. Touch requests 280×64 on tablets and 220×56 on phones, clamped by the existing safe-area/control-column calculation. Text is 18 pixels and may wrap inside a narrow lobby button.

The developer's in-round touch chip retains its 136-pixel requested width, 44-pixel minimum height, 11-pixel caption, position, transparency and label. Its prior unwrapped behavior is explicit. The stable `ZyntraOpenButton` instance name, activation path and all modal/briefing/input guards are unchanged. No Shop button or other feature was added; the top anchor leaves the lower area for that later card.

The complete ZyntraStore file compiled successfully (2 KLOC, 85 KB bytecode). `git diff --check` found no whitespace errors. No new mirror tests were introduced for this small reversible UI change.

Independent code review found no required changes and compiled the complete file again. The critic reserves the final score for the root's native desktop/phone/tablet evidence.

## Root-owned native pass

Batch desktop, phone and tablet inspection together. Verify the actual label fits, the button stays inside the safe area and outside touch movement controls, and it opens the existing terminal. Confirm that closing restores the button, the queue/briefing/terminal suppress both visibility and input, and the in-round DEV chip remains unchanged.

Existing validation tools locate the stable instance name, so no UIRegression rename is required:

- `UIRegression.Compact("BriefingExclusionMatrix")` exercises opener suppression and restoration, including interaction state.
- `UIRegression.Check()` / `ResolveRect` can inspect the actual lobby layout on each native device class.
- `ZyntraStore.UIRegressionZyntraStoreProbe:Invoke("open")` and `:Invoke("close")` use the existing production terminal paths when a deterministic test is useful. A real click/tap should still prove the enlarged opener works.

Native rendering remains the final check; if a concrete defect appears, fix it in one batch and confirm once. The implementation agent did not control Studio, push or publish.

## Completed root verification

Independent critic: **9/10**, with direct inspection of all five native images. No blocking findings. Desktop label bounds were 155×18 inside the 280×64 button. Actual opener and close clicks worked; opening hid/deactivated the opener, and closing restored it. QueueModalOpen and DispatchBriefingOpen guards were also verified with injected states.

Studio Device Simulator: iPhone 13 portrait actual viewport 387×762 and landscape 749×368 showed the 220×56 touch opener; iPad 10 portrait 816×1177 and landscape 1177×819 showed 280×64. All labels fit, remained on screen and avoided shown movement controls. The emulator retained both keyboard and mouse capability after injected input, so the existing Studio-only ForceTouchUI flag selected the touch branch. No fake viewport attribute was used. These are simulator checks, not physical hardware certification. A scaled-emulator MCP close click missed; a native mouse click on the visible X closed it correctly.

Existing TouchTargetMatrix: 428 checks, zero failures across nine device fixtures plus the then-current viewport. The test session was restarted afterwards. See equipment-button-native.json and equipment-button-*.jpg. Final Edit compilation: **122/122**, no failures or unstaged scripts. Repo audit: **122 matched, zero drift**, with one explicitly permitted trailing-newline difference. All Play-only overrides were removed by Stop Play.

## Release journal

Root published through the native mouse menu **File → Publish to Roblox**, confirmed by Studio Output as **v1821 on 9 September 2026 at 23:47:13.677 Europe/Copenhagen**. Final independent critic score: **9/10**. Trello IS3zOeKP was updated with the preserved original request and this evidence, moved to Done and marked complete. This release covers the larger, clearer Equipment opener; the separate direct Shop button is the next card.
