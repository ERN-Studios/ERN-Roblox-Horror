# Lobby music setting: independent prepared-code review

Reviewer: `/root/critic`. Date: 2026-09-10. **Score: 9/10 for the bounded proposed code. No required correction. Native installation/audio/UI acceptance remains pending.**

The complete diff is confined to the Config setting and LobbyMusicController eligibility/listener. `LobbyMusicEnabled` defaults to true, uses the existing generic persisted accessibility-setting path and renders through the existing Store settings list. Saved false values survive normalization. No new remote, persistence implementation, track, gain, crossfade or level-audio behaviour is introduced.

The controller requires the attribute to be explicitly true before starting either deck. The reviewer checked the actual server load flow: settings attributes are published from the normalized loaded session, not from an earlier default profile. Consequently an unset attribute remains quiet during loading, and a saved OFF does not receive a preliminary default-ON playback. OFF uses the existing 1.4-second fade/stop path; ON reuses the existing track-readiness and lobby guards. The existing briefing duck and late-lobby/InRound guards remain intact.

The reviewer independently reran `test_music.py`: **49 checks passed**, the original whole-controller negative control failed as expected, and both complete proposed files compiled. The tests execute the whole controller and actual existing settings snippets; they are deterministic Roblox API hosts, not native audio or live DataStore tests. Both production files still match their recorded unchanged baselines.

Reviewed proposal hashes: Config `a1100e3697c0c27b65016d3e9c0452a92614e9e3350816c502e3bf225c438ed0`; controller `7f9ecdeda7b62256ccd3f25484e7116fd31e0437dd1e692074b53f07bb966c38`.

Focused native acceptance should show the real Settings toggle, normal ON/default playback, OFF fading both lobby decks to silence, and ON restoration. A saved-OFF/profile-readiness observation should remain silent; existing level audio should not be represented as modified. Layout/audio observations are enough for this small integration; no new general runtime test framework is requested.
