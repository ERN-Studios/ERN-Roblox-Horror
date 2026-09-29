# Level 5 old-geometry replacement audit — 2026-09-27

**Status:** Measured replacement inventory, not a Studio deletion instruction. Live Studio remains authoritative. The three builders were inspected in the tracked checkout (`Level 5 Architecture`, `Level 5 Neighbourhood Districts`, `Level 5 Landmark Districts`). A fresh Edit-mode read found place `131311258779917`, Source/editor equality for all three, and matching local byte lengths (54,897 / 9,788 / 28,127). The isolated count waited until `_L5VisualQA_TEMP` was absent. Its unparented diagnostic container was destroyed after the measurement; no game-world geometry was installed or edited. The local file SHA-256 identities are `d4d074863c4674fa470ebd82a2848d1bde5f5a2a477139299560bc7d8723dfc9`, `f36c23b01b1b6b03132007b7f5c2384fbbf787b4e5c255356a29a043250ca12d`, and `8b0f2a636fd6294cfd87cd10729134c5f4b5acccffa924935454da25869a0466` in that order. The count checked live Source/editor equality again afterward; it did not independently compute live SHA-256 for the latter two modules.

## Capacity to recover

The optimized static Architecture build measured **27,472 descendants**. The currently revised ten reference drafts are approximately **8,256 descendants** in isolation, so a direct overlay would be approximately **35,728** before preview and round objects. Fitting the hard **30,000** static cap requires removing at least **5,728** old descendants; the proposed **27,000** static target requires at least **8,728**. Replacing a model with a playable new counterpart may add more descendants than its scenic draft, so these are lower bounds. The draft builders make noncolliding facade pieces; they cannot replace collision floors, stairs, or gates on their own.

Current optimized zone counts are A 3,048; B 1,632; C 4,361; D 3,007; E 1,908; F 7,524; G 4,609; H 1,302, plus 81 instances outside zone descendants. These are measured zone totals, **not** the savings estimates below.

The isolated builder returned 27,416 descendants under `Level5_IndoorSuburbs`. Its separately parented `WindowWatcherAnchors` folder and 54 descendants, plus the `Level5_IndoorSuburbs` model itself, account for the other 56 instances in the 27,472 total. The first-pass selectors below are disjoint and remove **8,929** old zone descendants. With all current drafts attached, that gives a provisional **26,799** static descendants (27,472 + 8,256 − 8,929): **201** below the 27,000 working target and **3,201** below the hard cap. This leaves almost no budget for new collidable thresholds, interiors, circulation or visual corrections at the 27,000 target. Treat 8,256 as a moving draft count and recalculate after every edit.

## First removal pass: closed upper scenery

The following exact name patterns identify **231 closed upper `house()` models** plus F/G ornamental balcony siblings. Their current code creates them with `open=false` or a level above any walking route, with no clue or Watcher registration on those levels. Remove a model only as its corresponding new facade is installed and after confirming its attributes and anchor references in the fresh Studio build. The table does not count ground homes, F's y≤28 circulation rooms, the seven gates or H.

### Measured disjoint removal ledger

Paths begin at `Level5_IndoorSuburbs/`; the brace notation denotes the listed existing names, not a glob to execute. Savings count the selected instance **and** all its descendants for a `Model`, or the selected `BasePart` itself. The counted F/G sibling parts are direct children of their wall/tower parent, outside the selected home models.

| Zone | Existing path selector below `Level5_IndoorSuburbs/` | Class | Matched instances | Old descendants removed |
| --- | --- | --- | ---: | ---: |
| A | `A_BalconyAtrium/ResidentialAtriumStack_{-1,1}_{1..3}/AtriumHome_{level>=3}` | Model | 15 | 570 |
| A | `A_BalconyAtrium/AtriumInnerStack_{-1,1}_{1,2}` | Model | 4 | 156 |
| A | `A_BalconyAtrium/CentralHallResidence_{1,2}` | Model | 2 | 110 |
| **A total** | | | **21** | **836** |
| B | `B_LowEavesArcade/ArcadeResidence_{-1,1}_{1..4}_{1,2}` | Model | 16 | 544 |
| B | `B_LowEavesArcade/ArcadeCrossLaneHome_{1,2}_1` | Model | 2 | 100 |
| **B total** | | | **18** | **644** |
| C | `C_PastelVillage/PastelCourt_{1..4}/CourtHouse_{court}_{outsideBay}_{level>=1}`; outsideBay is 3 on courts 1/3 and 4 on courts 2/4 | Model | 18 | 652 |
| C | `C_PastelVillage/VillageInnerLaneHome_{-1,1}_{1..4}_{level>=1}` | Model | 12 | 488 |
| C | `C_PastelVillage/OuterVillageStack_{-1,1}_{1,2}_{1..3}` | Model | 12 | 448 |
| C | `C_PastelVillage/CrossStreetCottage_{-1,1}_2_{1,2}` | Model | 4 | 156 |
| **C total** | | | **46** | **1,744** |
| D | `D_FloralTerraces/FloralTowerHome_{-1,1}_{1..3}_{1..5}` | Model | 30 | 1,020 |
| D | `D_FloralTerraces/SunkenPocketStack_{-1,1}_{1,2}_{1,2}` | Model | 8 | 352 |
| **D total** | | | **38** | **1,372** |
| E | `E_DomesticLabyrinth/NestedThroughHouse_{1..3}_{1,2}` | Model | 6 | 396 |
| E | `E_DomesticLabyrinth/LabyrinthEndResidence_{1,2}_{1,2}` | Model | 4 | 200 |
| **E total** | | | **10** | **596** |
| F | `F_BayWindowCanyon/{WestContinuousDwellings,EastContinuousDwellings}/PlasterDwelling_{1..10}_{42,56,70}` | Model | 60 | 1,394 |
| F | Direct children of those two continuous-dwelling parents named `ProjectingDomesticBalcony`, `RailingTop`, `RailingBottom`, `RailingSpindle`, `BalconyMouldedUnderside` | Part | 435 | 435 |
| **F total** | | | **495** | **1,829** |
| G | `G_TiltedSubdivision/ImpossibleDomesticTower_{-1,1}_{1,2}/TowerDwelling_{level>=1}` | Model | 38 | 1,548 |
| G | Direct children of those four tower parents named `HighClosedPorch`, `RailingTop`, `RailingBottom`, `RailingSpindle` | Part | 360 | 360 |
| **G total** | | | **398** | **1,908** |
| **A–G total** | **231 Models + 795 sibling BaseParts** | | **1,026** | **8,929** |

The selectors were applied to an isolated build with the existing two F native window-trim unions, so F's previous 1,768-part union reduction is **already reflected**. None includes a `WindowWatcherAnchors` child, clue surface, gate or H model. The table identifies safe *candidates*, not an instruction to delete all 8,929 before adding their replacement facades: the upper silhouettes still contribute to the current view and must be retired in the same scoped integration step as their new equivalent.

| Zone | Exact old model names / selector | Source count | Why candidate; what stays |
| --- | --- | ---: | --- |
| A | `ResidentialAtriumStack_{-1,1}_{1,2,3}/AtriumHome_{level}` where `level >= 3`: **15 homes**; `AtriumInnerStack_{-1,1}_{1,2}`: **4 whole upper homes**; `CentralHallResidence_1`, `_2`: **2 homes** | 21 homes | Only `AtriumHome_0` at stacks 1/3 carries four `PuzzleClueIndex` markers; Watchers are stack 1 level 0. Retain all level 0–2 stack homes for upper balcony frontage and retain `ContinuousBalcony`, `FirstCrossBridge`, `UpperCrossBridge`, three stair/landing groups and their rails. `AtriumInnerStack_*_0`, `CentralHallResidence_0` and both waiting/rear cottages are enterable; retain pending route redesign. |
| B | `ArcadeResidence_{-1,1}_{1..4}_{1,2}`: **16 homes**; `ArcadeCrossLaneHome_{1,2}_1`: **2 homes** | 18 homes | Watchers are `ArcadeResidence_{-1,1}_1_0`; one reachable B `HousePuzzleCandidate` must survive for gate 2. The cross-lane ground houses `_0`, four `DetachedThroughRoom_*` and eight porch groups are **conditional** corridor replacements, not first-pass deletes. Keep `OchreArcadeCarpet`, a clear entrance to gate 2 at X 88, and threshold shell. |
| C | `PastelCourt_{1..4}/CourtHouse_{court}_{outsideBay}_{level>=1}`: **18 homes** (outside bay 3 on courts 1/3, bay 4 on courts 2/4); `VillageInnerLaneHome_{-1,1}_{1..4}_{level>=1}`: **12**; `OuterVillageStack_{-1,1}_{1,2}_{1..3}`: **12**; `CrossStreetCottage_{-1,1}_2_{1,2}`: **4** | 46 homes | All four court Watcher homes are `CourtHouse_{court}_1_0`; C needs three distinct reachable puzzle candidates at ground level. Retain `WhiteBridgeCarpet`, `WestBridgeFlight`, `EastBridgeFlight`, landings, support piers and their rails until an avatar-usable crossing is reverified. The four `PastelCourt_*` **parent Models** contain Watcher homes and must not be deleted wholesale. |
| D | `FloralTowerHome_{-1,1}_{1..3}_{1..5}`: **30 homes**; `SunkenPocketStack_{-1,1}_{1,2}_{1,2}`: **8 homes** | 38 homes | Watchers are `FloralTowerHome_{-1,1}_1_0`. Keep grade/sunken floors, `DownToSunkenStreet`, `StreetExitStair`, both returns, `RaisedCrossStreet`, promenades and edge rails. Ground `LowerFloralHome_*`, `SunkenCornerResidence`, pocket and tower level 0 stay until the D clue choice and lower path are remapped. |
| E | `NestedThroughHouse_{1..3}_{1,2}`: **6 homes**; `LabyrinthEndResidence_{1,2}_{1,2}`: **4 homes** | 10 homes | Watchers are `DomesticRoom_{-1,1}_1_1`; gate 5 needs a reachable E candidate. Keep `DomesticBroadloom` and at least one continuous central room path. `DomesticRoom_*`, cross-lane rooms and ground `_0` homes are conditional room-layout replacements. |
| F | Under each `WestContinuousDwellings` / `EastContinuousDwellings`, `PlasterDwelling_{1..10}_{42,56,70}`: **60 homes**; sibling `ProjectingDomesticBalcony` floor parts, their `Railing*` parts and `BalconyMouldedUnderside` at `y>=42` are **ornamental** | 60 homes + upper balcony pieces | Keep `TelevisionClueResidence` (west bay 3, y0), `NearGroundWindow` (west bay 2, y0), `MiddleCourtWindow` (east bay 9, y14), `FarUpperWindow` (west bay 9, y28), all y≤28 ledge homes until access test, `CarpetLedge_*`, crossings, stairs, pit, supporting foundations, guardrails, F route/rescue/clue waypoints and gate 6 approach. F union trim saving of 1,768 is already in the 27,472 baseline; **do not count it again**. |
| G | `ImpossibleDomesticTower_{-1,1}_{1,2}/TowerDwelling_{level>=1}`: **38 homes**; the towers' `HighClosedPorch` siblings at even upper levels: **18 floor/rail groups** | 38 homes + 18 porch groups | Watchers are `ImpossibleDomesticTower_{-1,1}_1/TowerDwelling_0`. Keep all four tower ground homes until Watcher and gate 7 clue selection is retested. The eight `ProjectingDomesticBay` models are already inside upper homes, so do **not** double-count them. Keep both playable terraces, entries/returns, crossing and foundations while references 5/6/9 are built separately. |

The first-pass closed-home total is **231**: A 21 + B 18 + C 46 + D 38 + E 10 + F 60 + G 38. The associated balcony parts are additional disjoint candidates; their descendants are not in this home count.

## Conditional replacement after a playable path exists

These old models can free further budget and clear reference sightlines, but deleting them before their replacement would remove usable rooms, furniture or clue candidates:

| Zone / reference section | Exact old names to replace together | Required replacement contract |
| --- | --- | --- |
| A / #1 | `CentralHallResidence_0`, `AtriumInnerStack_{-1,1}_0`, `GroundWaitingCottage_{-1,1}`, `AtriumRearCottage_{-1,1}`; optionally selected non-clue `ResidentialAtriumStack_*/AtriumHome_0` | Move four numbered clue surfaces **once each** only if their original homes change; retain both `AtriumWindow_*` supported tinted panes and the balcony/bridge route. Plant path and porch row must not hide gate 1. |
| B / #2 | `DetachedThroughRoom_1..4`, `ArcadeCrossLaneHome_{1,2}_0`, `CoveredPorch` ×8, `LowPorchCanopy` ×8, `PorchPost` ×16, `SharedDroppedCeiling` ×3 and `ArcadeDomesticColumn` ×6 | Create one straight, collidable carpet corridor and side room entrances. Keep the two `ArcadeWindow_*` supported panes in ground homes and one reachable candidate for gate 2. Ground `ArcadeResidence_*_0` may be refaced instead of removed. |
| C / #3 | Ground `CourtHouse_*_0` outside watcher bay, `VillageInnerLaneHome_*_0`, `OuterVillageStack_*_0`, `CrossStreetCottage_*_0`, four `CarpetCourtSquare` and the central runner/court connectors | Rebuild a distinct porch row plus apartment circulation, retain at least three separate candidate homes and all selected Watcher rooms or rebind their anchor `ObjectValue`s to new real panes. Keep the bridge/stair crossing traversable. |
| D / #4 | Selected ground `FloralTowerHome_*_0` and `SunkenPocketStack_*_0`, six `FloralPaperWallPanel` | Retain lower street and its return stairs, one reachable switch clue home and at least one valid D Watcher home. Do not delete `TerraceRetainingWall`, `RaisedPorchPromenade` or fall rails until replacement collision is tested. |
| E / #10 | `DomesticRoom_{-1,1}_{1,2}_{1..3}` except the two Watcher homes, `EastCrossLaneRoom`, `WestCrossLaneRoom`, selected `NestedThroughHouse_*_0` and `LabyrinthEndResidence_*_0` | The new sparse room must have a real floor route, protected inner balcony view, a reachable E clue home, two supported `DomesticWindow_*` panes or replacements, and a path around the central partitions to gate 5. |
| F / #7 and #8 | `ArrivalDomesticBlock_1..3`, `DepartureDomesticBlock_1..2` and selected non-Watcher y≤28 scenic facade portions only after replacement | Keep entry/departure collision, `TelevisionClueResidence`, all three F Watcher supports, the multi-level route, lower recovery crossing and pit bounds. A visual stair cutaway cannot substitute for the eight actual `flight()` stair models. |
| G / #5, #6, #9 | `FusedTiltedHouses_{-1,1}` (including four `TiltedClosedHome_*`), `CentralTerracedResidence_1,_2`, `PerchedAngledResidence`, `OuterGardenResidence_{-1,1}_{1,2}_1`, and selected `TerraceCottage_*` only after route/clue reassignment | Keep the actual 8/16-stud terraces and their flights/crossing until the replacement route works; retain a reachable gate-7 arrow clue home (currently `CentralTerracedResidence_0` candidate), both G Watcher ground towers and a usable gate-7 approach. The new sloped mass and skybridges require their own supported circulation, not scenery alone. |

The following **additional** selectors were measured on the same isolated build. They are disjoint from the 8,929 first-pass descendants and from one another. They are **conditional**, because some are open homes or route-adjacent structures; counts are a budgeting reserve, not immediate safe savings.

| Zone | Exact additional selector below its zone | Class | Matched instances | Old descendants |
| --- | --- | --- | ---: | ---: |
| A | `CentralHallResidence_0`, `AtriumInnerStack_{-1,1}_0`, `GroundWaitingCottage_{-1,1}`, `AtriumRearCottage_{-1,1}` | Model | 7 | 367 |
| B | `DetachedThroughRoom_{1..4}`, `ArcadeCrossLaneHome_{1,2}_0` | Model | 6 | 372 |
| B | Direct zone children `CoveredPorch`, `LowPorchCanopy`, `PorchPost`, `SharedDroppedCeiling`, `ArcadeDomesticColumn` | Part | 41 | 41 |
| C | All ground `CourtHouse_*_0` except bay 1 Watcher homes, ground `VillageInnerLaneHome_*_0`, `OuterVillageStack_*_0`, `CrossStreetCottage_*_0` | Model | 30 | 1,742 |
| D | Ground `FloralTowerHome_{-1,1}_{2,3}_0` and `SunkenPocketStack_{-1,1}_{1,2}_0` | Model | 8 | 412 |
| E | `DomesticRoom_{-1,1}_2_{1..3}`, `DomesticRoom_{-1,1}_1_{2,3}`, `EastCrossLaneRoom`, `WestCrossLaneRoom` | Model | 12 | 623 |
| F | `ArrivalDomesticBlock_{1..3}`, `DepartureDomesticBlock_{1,2}` | Model | 5 | 250 |
| G | `FusedTiltedHouses_{-1,1}` including their tilted homes and support pieces | Model | 2 | 184 |
| G | `CentralTerracedResidence_{1,2}`, `PerchedAngledResidence`, `OuterGardenResidence_{-1,1}_{1,2}_1` | Model | 7 | 352 |
| **Additional conditional total** | | **Models and Parts** | **118** | **4,343** |

Removing every first-pass and conditional selector would retire **13,272** old descendants, but the conditional paths need replacement floors/rooms, entrances, clues or Watcher supports. Reserve their measured savings for the exact playable rebuild in that zone rather than subtracting them from the budget ahead of time.

## Measurement procedure before any replacement

1. Wait for visual QA to remove `_L5VisualQA_TEMP` and for Edit mode. Verify the place ID, the live `Architecture`, `Neighbourhood Districts` and `Landmark Districts` Source/editor parity, and the unchanged local mirror hashes. Do not count from a dirty or Play-session datamodel.
2. Build `Architecture.Build` under one isolated unparented diagnostic Model using the live modules and current `ServerStorage.Level5GeometryTemplates`; traverse **without reparenting, deleting, or editing** zone children. Record `#model:GetDescendants()` for each exact candidate selector, plus ancestor/sibling decorative groups and the total. Destroy only the diagnostic root that this measurement created. Check no diagnostic root remains.
3. Produce a removal ledger with **disjoint** selectors. A whole upper home count already includes its nested `ProjectingDomesticBay`; a `PastelCourt_*` parent count includes its Watcher home and is not a safe removal count. For F and G, add upper balcony pieces only when they are siblings outside the home.
4. Integrate zone by zone against fresh Studio Source/editor baselines. Recount the full build after each replacement, and test candidate selection, Watcher floor rays, navigation, fall recovery, the seven gates and the DEV-only preview. Keep the final static count at or below 27,000 to reserve runtime headroom; the 30,000 hard cap is never raised.

**No visual 1:1 conclusion follows from these selectors.** They only identify old geometry that can be retired as the new reference sections become both recognizable and playable.
