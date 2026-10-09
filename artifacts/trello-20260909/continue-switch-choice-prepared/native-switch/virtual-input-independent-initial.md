# Initial VirtualInput fixture review

**7/10 pending a small cancellation correction.** This concerns only the diagnostic fixture, not production Continue behavior.

The initial source `1c22a024c50f1e0c6ad06513eb61205c6d76cdd393bc48caebd409b49b9226ce` can resume from RenderStepped after Stop/lobby has cleared `alive`, then send a new mouse-down anyway. A stop during the subsequent 0.04-second wait releases the owned button, but the resumed run sends a duplicate mouse-up. Add a fresh alive/window/deadline and target/input check after RenderStepped, and release after the hold only if the fixture still owns `pressed`. No new broad harness is needed for this small fixture correction.

The public API signatures and current security contract were independently checked against Roblox's [VirtualInput reference source](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/VirtualInput.yaml) and [UserInputService reference source](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/UserInputService.yaml). The mouse API deliberately errors on duplicate requested button state. The declared use of actual button centers and subsequent authoritative same-serial revisions is otherwise appropriate. Native construction availability is root's separate evidence; no input was executed by this review.
