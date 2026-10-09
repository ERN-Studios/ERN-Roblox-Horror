# Permanent lobby copy of MUTE DISPATCH

The owner confirmed copying **MUTE DISPATCH**, rather than the separate lobby-music setting. This proposal changes only RoundUI; the companion Store layout is owned by `side-buttons-revision`. Production, Studio, Trello and Discord were not changed here.

## Actual source semantics

- `RoundUI.LocalScript.lua:21–45` owns private `dispatchAudio` state and `SoundService.ZyntraDispatchAudio`. Unknown preferences fail quiet. `refresh` at119 and `requestToggle` at257 implement optimistic playback, shared pending state, the existing12-second fallback and server-attribute acknowledgement at291. The original button is built at1968, invokes this handler at1982, and only exists while a transmission is active. Original M/LB shortcuts remain active-transmission-only.
- The same SoundGroup is assigned to the lobby intro and all three level briefing/radio sounds around2298–2363. Muting does not stop the transmission, remove subtitles, restart the intro, or silence unrelated game/music sounds.
- `ZyntraMonetization.Script.lua:2380` accepts the existing boolean `SetMuteDispatch` command; `queueMuteDispatch` at2000 uses the existing session/lease/coalesced durable write path. `applyAttributes` at557 publishes `ZyntraMuteDispatch`. This proposal introduces no server code, remotes, new persistence or live DataStore test.
- Lobby music is a different preference: `ZyntraConfig.ModuleScript.lua:160` defines `LobbyMusicEnabled`; Store Settings sends `SetAccessibility` around2049. `LobbyMusicController.LocalScript.lua:107–110` gates only its two music decks on that setting. If a later user asks for music mute, that setting is the appropriate route; DISPATCH must not silently be broadened to every sound.

Graphify located the dispatch call graph, but its line map predates the current release. The current source and frozen bytes above are authoritative.

## Small composition contract

Store creates a direct transparent, inactive Frame:

`PlayerGui.ZyntraStore.ZyntraSideMuteSlot`

Store owns its position below Upgrades with an8px gap,64/56px width (52px constrained fallback),44px height, and safe visibility. The slot remains available during briefing even when the old opener guards hide Store buttons; its geometry must avoid the actual briefing and movement controls. Full modals/queue/rounds suppress it.

RoundUI waits for this one slot and creates `SideDispatchMuteButton` there inside a scoped task. It uses the **same private** `dispatchAudio` state, label selection, action and acknowledgement path as the original. There is no extra SoundGroup, global state, Bindable or Remote. The copy reads `mute\ndispatch` / `unmute\ndispatch`, with honest loading/offline/saving states,11px Code text at56px+ or10px below56. A slot-size observer updates the face regardless of UIDevice callback order.

Only the copy calls `requestToggle(true)`, allowing a saved dispatch preference to be selected while idle. Original button and M/LB behavior retain their existing active-transmission requirement. The copy revalidates visibility and enabled state immediately before requesting. RoundUI additionally respects InRound, screen-owning modals, PartyDown, disabled Store and a missing slot parent. Briefing is deliberately not a suppressor.

Install the matching Store-slot and RoundUI proposals together after root review. Each has a frozen before-copy and narrow transform; use the exact immediate source hashes and preserve the published square/copy changes. Installing RoundUI alone leaves its slot task waiting and does not create the new copy. No new top-level local is added to RoundUI's200-local main chunk.

## Validation and native acceptance

`python artifacts/trello-20260909/side-mute-revision/test_mute.py` executes38 checks against actual refresh/request/ack/setup/callback source. It covers loading/offline, idle selection, shared pending/ack in both directions, duplicate clicks, existing timeout rollback, original active-only guard, briefing visibility, round/modal/slot suppression, actual resize callbacks and explicit Border stroke mode. The original active-only handler fails the specific idle-copy regression. A literal inverse reconstructs the entire baseline and the whole proposed RoundUI compiles. Runtime baseline SHA is unchanged. See `manifest.json` and `validation.json`.

Root's short native acceptance:

1. In the ordinary loaded lobby, measure the left stack and copy on desktop and phone emulator; check both full labels fit the actual52/56/64px slot,44px target, and no briefing/movement overlap.
2. While dispatch is active, click the copy and then the original. Observe both captions/pending state and `ZyntraMuteDispatch`; `ZyntraDispatchAudio.Volume` should follow the same preference. Keep subtitles/transmission running. Lobby music remains governed by its own setting.
3. After dispatch finishes, the copy remains visible and can change the saved preference. The original controls disappear normally. Open/close Store and queue, enter a normal round and return: no hidden active copy or duplicate button; lobby restoration remains correct.

The host does not certify native font fit, layout, Roblox input, or real durable save/rejoin behavior. No purchase, broadcast, replayed intro or artificial extra player is required. Independent review and actual native acceptance are recorded separately.
