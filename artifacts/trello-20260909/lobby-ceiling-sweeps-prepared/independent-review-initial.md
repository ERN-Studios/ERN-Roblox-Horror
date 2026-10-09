# Initial independent artifact review — 7/10

Read the complete controller, its actual-source host, current Builder lamp contract and server Party controller. Viewed the five-pattern preview. Independently reran 63 checks, two negative controls and whole-file compilation. All existing checks pass; no runtime or Studio changes were made.

One required correction remains: the ownership guard currently runs only during restoration. If server Party colour/brightness replicates one Heartbeat before PartyModeActive, update writes over the foreign values and records the overwritten values as its own. The later cancellation then restores the old cyan values. The original test puts the property change and flag update next to each other and misses that interleaving.

`independent-delayed-party-flag.luau` executes the actual controller with one additional update between the replicated values and flag. It fails `one heartbeat before Party flag preserves replicated values`. This is a controlled scheduling reproduction, not a claim that native replication already exhibited the race.

Recommended bounded correction: before writes, detect ownership loss against the last own native readback, or the captured baseline before the first write. Abort the ambient sweep and restore only still-owned properties, keeping Party's changed properties. Preserve existing Party flag gating and quiet interval. Cover both mid-sweep and pre-first-write delayed flags. Native Party overlap/order remains a later acceptance step.

The remaining scope is sound: five distinct broad spatial highlights, conservative brightness, loaded ReduceFlashing gate, normal-round/Party exclusion and owned cleanup. No other required change was found in this pass.
