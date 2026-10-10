# S04 nonserialized reference boundary

The existing evidence does not prove these hidden pointers empty. All five
forests remain preserved. This review changed no frozen capture files and made
no Studio, native, selection or Studio CLI calls.

Root's actual S04 V2 receipt contains **61283 compatible nonserialized slots**:
61277 PhysicsRepRootPart holders and six other holders. These counts describe
that trial's epoch; no fresh Player-zero census is available in the reviewed
receipts. The same exact native archive has 549 Part/MeshPart objects inside the
retired forests, all anchored. Its six object classes include no WorldModel,
joint or constraint. Consequently 549 physics holders are internal to the
retired package; **60734 compatible holders are external** at that epoch. This
classifies owners, not hidden pointer values.

| Holder / property | Observed total | Retired internal | External | Disposition |
|---|---:|---:|---:|---|
| MeshPart.PhysicsRepRootPart | 9660 | 498 | 9162 | Hidden pointer pending |
| Part.PhysicsRepRootPart | 43804 | 51 | 43753 | Hidden pointer pending |
| Seat.PhysicsRepRootPart | 1204 | 0 | 1204 | Hidden pointer pending |
| Terrain.PhysicsRepRootPart | 1 | 0 | 1 | Hidden pointer pending |
| UnionOperation.PhysicsRepRootPart | 6608 | 0 | 6608 | Hidden pointer pending |
| GuiService.CoreEffectFolder / CoreGuiFolder | 2 | 0 | 2 | Protected Folder pointers pending |
| Selection.ActiveInstance | 1 | 0 | 1 | Editor pointer pending |
| StudioService.HoverInstance | 1 | 0 | 1 | Editor pointer pending |
| Player.PendingRequestedTool | 2 | 0 | 2 | Fresh holder census / pointer pending |

The primary [assemblies contract](https://create.roblox.com/docs/physics/assemblies)
limits functioning joints to Workspace or WorldModel. The official
[BasePart reference](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/BasePart.yaml)
documents AssemblyRootPart as nil outside Workspace, GetJoints as the connected
joints/constraints, and GetConnectedParts as rigid connections. Together with
the exact ServerStorage parent/tree baseline, this supports a concrete public
physics-isolation check. **Inference:** these retired parts do not participate
in an ordinary active assembly while preserved under ServerStorage. The hidden
PhysicsRepRootPart is absent from the public contract; neither the public root
nor an empty public joint list proves its exact value or retention semantics.

The [Selection contract](https://create.roblox.com/docs/reference/engine/classes/Selection)
explicitly limits that service to Studio and describes Get as the current
selection. It does not define hidden ActiveInstance or prove its equivalence to
Get. The [StudioService contract](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/StudioService.yaml)
describes Studio/plugin state but omits HoverInstance. Therefore current editor
selection/hover is a separate transient development-state concern, rather than
a demonstrated gameplay caller. The retired authoring workflows no longer
require their old selection state, but preserving unrelated active selection
and plugins remains necessary. A scoped decision about retired transient state
would not certify global reference absence.

The current public [GuiService](https://create.roblox.com/docs/reference/engine/classes/GuiService)
and [Player](https://create.roblox.com/docs/reference/engine/classes/Player)
references provide no contract for the other three hidden fields. Prior native
reads failed with missing RobloxScript capability for the two GUI folders,
Selection and Hover; PendingRequestedTool failed as an invalid Player member.
None of these errors establishes nil. No privileged hidden-getter workaround
is proposed.

A useful next Root-only read can stay bounded:

1. Capture current holder identities in one guarded descendants census. Yield
   and check mode/owned lease/epoch every 1000 nodes, and keep all 213 Source/editor
   and exact-five-tree guards. If there are actually no contained Player objects,
   exclude their current slots by owner absence; do not extrapolate to later Play
   sessions or unknown detached objects held outside the DataModel.
2. For exactly 549 pinned retired Part/MeshPart identities, read AssemblyRootPart,
   GetJoints and GetConnectedParts(false). Record every error and external returned
   identity. Yield/checkpoint every 50 targets, cap returned entries and refuse
   unexpected scope. Do not recursively expand assemblies, move parts or create
   test joints. This is a public physics crosscheck, not a hidden-pointer pass.
3. Read the four small GUI/editor slots and any actual current Player slots with
   ordinary native getters. Preserve exact successful type/membership or the
   failure. Selection:Get and a separately owned SelectionChanged connection
   provide supplementary evidence only. Do not change selection or hover.
4. Independently disconnect owned listeners and recheck mode, lease, Source/editor
   and exact original native bytes. Errors retain pending status. Permanent removal
   still needs accounted external hidden values or an applicable primary engine
   contract, plus a fresh final removal guard.

No new native port was executed. The complete raw-input pins, owner arithmetic,
official-source links and remaining proof requirements are in review-v1.json.
The serialized raw capture is a separate gate and cannot settle these slots.
