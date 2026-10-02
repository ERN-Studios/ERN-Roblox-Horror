The requested Level 5/6 closure is confined to the revised R4 lobby. The new `R4DevGateController` creates local industrial shutters and Coming Soon notices for users outside each existing preview allowlist, hides their owned queue labels and preview prompts, and leaves authorized developers' normal queue/preview route open. Shared developers are mikkelczar and LaverSneglen; ZenMeister02 retains the owner's earlier explicit Level 6 preview permission only. No general developer permission is added.

Client shutters are presentation and local walking collision. They are **not** the security boundary. Existing server controllers remain authoritative and unchanged:

| Entry or continuation path | Current server check |
| --- | --- |
| R4 pad create/join/admission | GameManager `playerInsideZone` calls `Bridge.AllowsPreview`; the exact active Level 5/6 controller's callback requires `readyPlayer` or `playerReady`. |
| Level 5 direct E preview | `readyPlayer` requires `DevAccess.IsAllowed`, a live unanchored avatar, no active campaign round, and no reserved round server; checked again after streaming. |
| Level 6 direct E preview | `playerReady` requires `DevAccess.IsLevel6PreviewAllowed` and the same live-avatar/public-lobby constraints; transport readiness and post-stream validation use that predicate again. |
| R4 frozen queue cohort launch | `Bridge.ValidateQueueAdmission` invokes the controller allowlist at initial admission, after streaming, immediately before moving the cohort, and before/after each commit. Any invalid participant aborts or rolls back the cohort. |
| Level 6 runtime membership | `Runtime.Join` checks `IsLevel6PreviewAllowed`; the running runtime periodically rejects revoked membership. |
| Unauthorised arrival in Level 5 bounds | The existing Level 5 controller returns unallowlisted avatars to the original lobby. |
| Normal campaign queue/arrival/Continue | GameManager's `canAccessLevel` rejects levels above `Routing.MaxLevel=3`; `Routing.NextLevel` stops at 3. No campaign continuation into Level 5/6 exists. |

The new controller accepts only the top-level owned `LobbyReimaginedPreview` with `LobbyVisualRevision=4` and `Ready=true`. It derives the shutter transform from the actual native header CFrame, covering the measured 19.9 by 15.6 stud doorway with a 20 by 15.6 stud shutter. It observes Ready/ownership/revision publication and top-level model arrival, disconnects owned hooks on removal, restores only its locally hidden properties, and refuses a conflicting gate folder. No polling task, global prompt toggle, original lobby geometry, server gate property, or existing source is changed.

Offline verification compiles the exact candidate and executes 14 meaningful policy, mounting and lifecycle cases. These include ordinary IDs, spoofed tables/usernames, strings, NaN/infinity, both shared developers, Zen's Level 6 exception, missing/erroring access modules, late model/kiosk arrival, local Enabled re-hide, cross-model reparent cleanup, 10 repeated Ready resets without growing connection counts, atomic streaming removal/reappearance, conflicting folders, and both door orientations. The receipt explicitly does not claim an actual Roblox Play, multiplayer test, or proof from source alone. Root must perform actual Studio inspection and real allowed preview entry before publication.

No Studio mutation or UI control was performed by this sub-agent. Its independent read-only Studio fetch confirmed the current DevAccess source and editor source match the root's fresh SHA256 `49b292d585f47604b84486585af39edf9915e08f3eaf7e253485769260e4b29f` baseline. The root applies only the new owned LocalScript against its fresh live baseline and preserves all existing server authorization sources.
