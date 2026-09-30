# Level 6 Worn Party — offline audio

Five original ElevenLabs Sound Effects v2 sources were selected from four takes per prompt. The package contains the untouched selected MP3s in `raw/`, 48 kHz stereo 24-bit PCM WAV masters in `mastered/`, and 48 kHz stereo 192 kb/s MP3 alternatives. Three 19.75-second ambiences loop; the two interaction cues are three-second one-shots. [manifest.json](manifest.json) records each source generation, exact prompt, SHA-256 hash, format, processing chain, and QC result. The [ElevenLabs flow](https://elevenlabs.io/app/flows/Zlw8w6brtdpGTVh66twg) retains the generation history.

| Asset | Intended use | WAV decoded peak | Quiet / seam result |
| --- | --- | ---: | --- |
| `party_hall_ambience` | Beige party hall / birthday rooms | −21.40 dBFS | Loop boundary −74.39 dBFS |
| `budget_arcade_ambience` | Budget arcade zone | −8.18 dBFS | Quiet high band −85.31 dBFS |
| `maintenance_workshop_ambience` | Maintenance workshop | −20.96 dBFS | Loop boundary −74.08 dBFS |
| `arcade_credit_button` | Arcade play / credit action | −7.08 dBFS | Final half-second −138.85 dBFS |
| `breaker_switch` | Maintenance power-switch candidate | −7.41 dBFS | Final half-second −84.10 dBFS |

The ambience retains the intended low HVAC, ventilation, transformer and cabinet sounds. The arcade source also had broadband high-frequency residue between its sparse bleeps. I split it into a continuous sub-600 Hz bed and a gated/denoised 600–6000 Hz event band. In the quietest half-second, energy above 4.5 kHz fell from **−70.27 dBFS in the source to −85.31 dBFS in the WAV master**, after final level matching. This addresses the AI-static issue without muting the machine atmosphere. The party and workshop ambiences use gentler FFT denoising and low-pass filtering.

The one-shots use high-pass and low-pass shaping, FFT denoising, a downward gate, a 4 ms start fade, and a 300 ms end fade. Arcade credit source/final tail RMS changed from −72.36 to −138.85 dBFS; breaker source/final tail RMS changed from −55.94 to −84.10 dBFS. They were normalized with stereo-to-mono playback headroom: decoded WAV and MP3 peaks both measure below −6 dBFS. Each ambience received a 250 ms circular crossfade. The WAV and MP3 loop boundary steps are all below the 99.9th percentile of natural adjacent-sample steps within their own files, so the file seam shows no exceptional sample click. In-game looping and spatial balance still need a listening test after import.

For later Roblox import, the WAV masters are preferred for seamless ambience loops. The MP3s are compact alternatives. Both satisfy Roblox's documented single-stream format, ≤48 kHz sample rate, channel and file-size requirements; every WAV is under 6 MB. Studio will transcode uploads, so the final in-game result must be checked there. [Roblox audio import requirements](https://create.roblox.com/docs/audio/assets).

The ElevenLabs workspace was checked in its authenticated Subscription and Invoices pages on 2026-09-30. It showed a paid Creator plan renewing on October 1 and a paid September 1 invoice; the same workspace opened the exact source flow linked above. The selected sounds were generated on September 29, within that paid billing period. ElevenLabs says paid-plan generations carry commercial rights; the [ElevenLabs billing documentation](https://elevenlabs.io/docs/overview/administration/billing) and [Sound Effects Terms](https://elevenlabs.io/sound-effects-terms) apply. Roblox Creator Dashboard and Studio upload attempts stalled; no completed upload or asset ID has been verified, and these new sounds have not been bound to a Studio instance.

Processing is reproducible from the included `raw/` sources with `master_audio.py`; objective frame RMS, quiet-tail, high-band and loop-boundary measurements come from `audio_qc.py`. `raw-qc.json`, `build-results.json` and `final-qc.json` are the captured measurement and build records. Selected source masters are retained byte-for-byte in `raw/` so future mastering changes can be compared against the original output.
