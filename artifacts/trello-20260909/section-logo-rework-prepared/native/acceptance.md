# Native logo acceptance

Installed the exact reviewed after-shield merge SHA749afb8362e159940ab1f719fe74f8f1bc9ce84a495d41bd08f6306b79768151. Only decorative helper and Upgrades glyph list changed; Entity Shield and all handlers remain.

Actual Studio screenshots: desktop.jpg, touch.jpg, narrow.jpg, restored.jpg. Desktop buttons280×64/280×48 have32×32 glyphs, inactive decorative children, TextFits captions and hidden original TextTransparency1. Synthetic568×320 touch buttons220×56/220×48 retain32×32 glyphs and captions fit; the Upgrades caption wraps to two lines. Synthetic320×568 narrow buttons132×56 use the preserved text-only fallback with TextFits=true, child content hidden and original text visible.

Real mouse clicks on desktop Upgrades glyph and Shop caption opened the terminal/Shop; both lobby buttons hid behind the modal. Touch-layout Shop glyph and Upgrades caption were also clicked successfully. The Upgrades opener retains the terminal's previously selected page as its unchanged handler specifies. An initial assertion incorrectly expected it always to switch back to Upgrades after Shop; this was corrected against the existing handler, with no production code change. First-open Upgrades and explicit Shop routing were separately verified.

QueueModalOpen and DispatchBriefingOpen each hid/deactivated both actual buttons and restored them afterward. A synthetic InRound change hid both buttons on this actual desktop device (UserInputService.TouchEnabled=false). Physical touch/DEV-phone behavior is covered by the unchanged source guard and existing code fixture, not claimed as a physical-device native test. Returning to ordinary lobby desktop restored captions and both32px glyphs. All four Contextual UIStroke instances were disabled while the replacement content was shown; the final screenshot has no ghost text.

All runtime attributes/viewport overrides were cleared and Play stopped. Complete native compile125/125 and source audit125matched/zero drift passed, with the established single trailing newline exception. Publication awaits the independent final10/10 requirement on this card.
