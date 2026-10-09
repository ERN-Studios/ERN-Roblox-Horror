# Native verification — in progress

First installed candidate Store `cdae3e9610561db95fa281edfb5ca6a735ff817dd2ddf51e68bb9f4852d478c0`, RoundUI `a851f6315bad4806698ab40627a9092955b1455a88b6da4f62ad95b9e65eb7f3`.

- Desktop showed three equal 64px squares, x8 and y205/277/349 in the 617px safe area. All three image assets loaded, lowercase captions fit, and controls were selectable after loading. The complete 208px column is centered to within pixel rounding.
- **Initial side-click failed to establish OFF.** `native-desktop-off.json` preserves that failure despite its filename: caption `unmute`, attribute still true, Deck A still playing at0.12. Do not treat this as a successful mute test. A later read showed the caption reverted. Cause still under investigation.
- Native Upgrades opened the terminal; Settings > Lobby music OFF then set the actual attribute false and both decks stopped at volume0. Closing the terminal showed side caption unmute. The subsequent native side Unmute set the actual attribute true and Deck A resumed at0.12. Initial preference restored.
- A user-input safety interruption prevented one attempted Upgrades click; it was retried only after a fresh window capture. It is not a successful action.
- The owner then required all three controls to remain available during Dispatch and capitalized captions. That focused revision and its fresh native checks are pending; these first screenshots do not certify the final design.

## Final candidate cb9396a4

Final Store `cb9396a4a796810a1725426c5f3732c808f96fe6e0c5c60740c601756ae290b0` capitalizes Shops/Upgrades/Mute/Unmute and permits the lobby controls during Dispatch. RoundUI remains the exact a851 restoration.

- Fresh desktop session, before opening Store: a native Music click generated exactly one server `SetAccessibility` request with `Enabled=false`. Both server and client attributes became false; both loaded music decks stopped at volume0. `native-first-click-observed.json` records the actual event. The simultaneous `native-desktop-dispatch-off.jpg` shows the active dispatch subtitle and all three buttons. Its JSON field `dispatch=false` means the saved **mute preference is false**, not that Dispatch is inactive.
- Native Upgrades click opened the terminal while the briefing was active. Settings displayed OFF after the side click. Native Settings ON restored the actual attribute and music at0.12; after closing Settings, the side button displayed Mute. No remote-binding fix was made: the original mismatch was not reproduced and its cause remains unknown.
- Native iPhone13 Studio simulator: 749x368 viewport, 749x310 safe area. All three buttons are56x56, x8, y29/91/153, with6px equal gaps. The column shifts36px up from ideal centering to leave8px above the visible joystick glyph (x29/y217,74x74). Desktop remains centered with64px squares and8px gaps.
- `native-phone-dispatch-on.json` explicitly records `briefing=true` and `dispatchActive=true`, all three controls visible/active/selectable, all images loaded and all capitalized captions fitting. `native-phone-shop-during-dispatch.jpg` records the Shop terminal opened by the actual Shops icon click.
- Native phone Music OFF and ON both changed the actual preference and stopped/resumed the music decks. Unmute also fits the56px button. Both Music taps were consumed as Touch UI input, max MoveDirection0 and displacement0. A separate joystick drag was unprocessed by UI, reached MoveDirection1 and moved the character0.260586 studs. This is simulator input evidence, not a physical-phone or simultaneous multi-touch certification.
- The original Dispatch controls and mute preference remain unchanged. Music preference restored to true; Dispatch mute remains false. Temporary server/input observers were disconnected and removed before Play stopped. No source fixtures or new DEV changes remain.
- Final stopped-Edit audit:126/126 matching sources, zero drift, the pre-existing permitted one-LF difference in Level2Lighting unchanged. Git diff whitespace check passed. Independent final review and publication are recorded separately.

No Discord resend has occurred. The revised preview is held for the chat.
