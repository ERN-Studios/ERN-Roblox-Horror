# Level 5 DEV gallery: landing and fall audit (2026-09-27)

## Read-only finding

Roblox Studio was in **Edit** mode when checked; `Workspace.StreamingEnabled` was `true`. Live `Level 5 Rework Gallery`, `Level5PreviewAccess`, and `Level5GalleryCamera` each had matching `Source` and Script Editor source. No Play client remained for a direct reproduction. This note changes no Studio instance or script.

The Section 01 cell origin is `(45875, 24, 0)`. Its `GalleryViewPad` is centered at `(45867, 23.75, -58)`, measures `14 × 0.5 × 14` studs, and has a collidable top at Y=24. The landing marker is centered at `(45867, 27, -58)`. Four invisible, collidable 8-stud guards surround the pad. These are constructed by `cameraPad` in `Level 5 Rework Gallery` (lines 218–251).

The observed HumanoidRootPart position `(45883.7, -52.4, -48.2)` was about 16.7 studs to the right and 9.8 studs beyond the pad center, outside its ±7-stud footprint and guard box. That X/Z point lies above the visible courtyard lawn/path. Section 01–04 facade builders intentionally create *all* `b.piece` parts with `CanCollide=false` and `CanQuery=false` (`Level 5 Reference Facades`, lines 145–153); this includes Section 01’s `DarkLawn` and `CurvedPaleWalk` (lines 439–445). A QA `PivotTo` or other scripted displacement beyond the guard would therefore lead to a fall. The position alone does not establish that an ordinary player passed through the landing pad.

`Level5PreviewAccess` checks a raycast against the destination pad before gallery teleport and rechecks after `RequestStreamAroundAsync` (lines 267–313). The client `Level5GalleryCamera` changes camera heading/FOV only (lines 147–177); it does not move the character. Because streaming is enabled, a pad or guard arriving late on the **client** remains a plausible cause if a fall repeats during normal prompt travel. Server-side raycast success does not prove client-side replication at arrival.

## Future natural-walk Play reproduction

1. Start a fresh Play session as an authorized developer; leave normal camera and movement controls enabled. Use the lobby `Level5SealedDoor` preview prompt, then the hub stand’s `VIEW SECTION 01` prompt. Do not set the character CFrame/PivotTo or enable fly/noclip during this run.
2. Log server and client HumanoidRootPart position at arrival and approximately 1 and 3 seconds later. Record the landing marker position, pad CFrame/size/`CanCollide`, and count/CFrames/`CanCollide` of the four `GalleryViewGuard` parts. On the **client**, explicitly record whether these five safety parts are present when the avatar arrives.
3. Observe whether the avatar stays on the pad at Y≈27 and whether the `RETURN TO HUB` prompt works. Repeat from a fresh session if the client safety parts were missing or the player fell; record stream errors and the times at which each part appeared.
4. As a separate negative control only, move a test character by script to Section 01’s visible path outside the guard box. Falling there is expected with the current view-only decorative facade and should not be counted as a prompt-travel regression.

## Play result after the new gallery source was installed

A fresh Studio Play session used the authorized developer account's actual door and section prompts. QA moved the avatar beside the door and hub stands by script to save walking time; it did not move the avatar into any section cell. The path lobby door → hub → section 01 succeeded. The client reported the section 01 pad present and collidable, and the avatar remained at (45867, 27.16, -58) three seconds after arrival, above the pad centered at (45867, 23.75, -58). The RETURN TO HUB prompt then worked. The same prompt flow reached sections 08 and 09; their streamed client pads were present and collidable, and both avatars remained at Y≈51.16 and Y≈27.16, respectively, after three seconds. Section 09 returned through hub to the lobby.

This single authorized-client run did not reproduce an ordinary prompt-travel fall. It does not settle intermittent streaming or non-developer multiplayer behavior. The earlier off-pad position remains consistent with a scripted displacement onto decorative, noncolliding scenery. A persistent safety model or client acknowledgement would be justified only after a prompt-only reproduction.
