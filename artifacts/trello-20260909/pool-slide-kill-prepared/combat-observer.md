# Read-only combat observation

`CombatReadOnly.Server.Script.lua` is a Play-only normal server Script, installed beside the existing WithFoam helper. It creates only `ServerStorage.PoolSlideCombatReadOnly`. It does not call Begin, activate pumps, require a fresh controller instance, or change gameplay. It accepts `:Invoke("Snapshot", actualUserId)` during an already running round. Its expected Controller source is the reviewed10.5-stud candidate9f8b2598…1d60; root's source audit establishes installation identity, not this constant in a diagnostic report.

The callback reads the existing normal server cache's exported NAV foot, actual player HRP, character ForceFields, range/vertical/arc geometry and a fresh LOS ray with precisely the Controller's runtime/entity-node/buoyant-prop/player-character exclusions, IgnoreWater and RespectCanCollide. It measures the actual model pivot LookVector, whose writer is Navigator._placeFoot's CFrame.lookAt using Facing. The first observed ATTACK snapshot is retained per world/model/AttackSerial for facing-drift comparison. That is a source-backed proxy; it does not expose private Navigator.Facing or the private windup HitAt/HitChecked. FirstObservedAttackAt can lag the actual start by the sampling interval.

`PlayerProtection.IsActive` is exported but can call Clear on expired/invalid state and mutate attributes/epoch. The module has no pure private snapshot API. Consequently this strict observer does not call it: it returns PrivateReadAvailable=false with the reason and separately records display attributes. Geometry alone, apparent display protection and ForceField visibility do not certify eligibility or attribution of damage. ForceFields are never removed.

The sidecar's independent diagnostic review is9/10; whole source compiles. It was not a native combat acceptance by the author. Root owns installation/execution.

## Minimal combined capture

Root first uses the existing WithFoam Begin for the fresh normal Level2 round. Run `sample-combat-30s.luau` once before pump2. It gets the real tester from that helper, requires a live tester/current original round, immediately starts a bounded task and returns. Change LABEL and SECONDS if needed; duration is0.5–30seconds. No new module or remote is required. Both existing Bindable snapshots are sampled every task.wait(.05), with before/after timestamps because the pair is not an atomic damage event.

Results are stored in the owned `ServerStorage.TestSamples` Folder. Poll its Finished attribute; Completed requires the requested duration, unchanged round and successful serialization. Interrupted/Error are explicit. Completion of sampling is not proof of gameplay success. Death itself does not stop capture, but original-round replacement does. Removing the owned Folder cancels subsequent sampling; it does not stop either encounter.

The sampler also received independent diagnostic9/10 after a full read and compile. Frozen SHA-256: `9490825ed9801cae611a24b6f7c1961781c5240e3de99a8e4b79f790f755a2e7`. The sidecar SHA-256 is `80564882184fbca360ba4d61660f32529841a0ebe50d455feb1ea9720ea3e7f5`.

After Finished, read `Chunks`, then StringValues `Chunk001` through that count in order. Concatenate with no inserted characters, verify the UTF-8 byte count equals `Bytes`, and parse JSON. Each chunk is at most40,000bytes and ends on a UTF-8 boundary. Partial serialization failure sets Error and must not be silently accepted. Export/remove the old TestSamples Folder before running a new capture; the script refuses to overwrite it. Existing WithFoam windows/reports are untouched.

The helper and sampler are never production scripts and must be absent before publishing. All source/controller/entity/health/economy state remains under root's normal test flow.
