# CharacterRemoving gap regression

The added actual-source fixture queues initial, late-Head and pass-style refreshes, fires CharacterRemoving, and deliberately keeps Player.Character pointing at the retired character while flushing those jobs.

Before the fix the exact fixture FAILED: `queued initial/Head/pass work cannot resurrect tags during the removal gap`.

The corrected proposal keeps one server-local active character per player. CharacterRemoving clears that identity before removing badges. Both generic tag refresh and the deferred character callback require that identity, in addition to Players membership and current Player.Character. The same fixture now passes, including no deferred Head cosmetics, replacement Head during the gap, queued round/pass refresh, eventual new CharacterAdded, and stale CharacterRemoving for the old character after replacement.

Final current run: 83 actual-source lifecycle/style/authority checks pass; full proposed monetization script compiles. Runtime monetization and DevAccess still match the exact saved baseline hashes. Native billboard rendering remains untested.
