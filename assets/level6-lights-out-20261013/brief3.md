You are the single helper. Use ONLY your ElevenLabs connector (its `elevenlabs_creative_*` flow tools). Do not touch
Roblox Studio, do not start subagents, do not edit any file except `notes3.md` in
/Users/zeanjuul4/Projects/stayquiet-poolrooms-audio-20261009/assets/level6-lights-out-20261013/ .

Job: TWO sound-effect prompts, four takes each, in the existing flow "stayquiet l6 lights out 20261013"
(flow id GegOpOtkHf1I0hTZstHY). The first four takes kept a steady hum to the very end; these must die away.
Model eleven_text_to_sound_v2, prompt_influence 0.7, loop false, 4 generations per prompt. Send the prompts EXACTLY
as written (both are under 450 characters).

Prompt C, duration_seconds 3:
A big industrial power switch slams off with one loud heavy clunk, then the electricity powers down: a fluorescent light hum drops in pitch and dies away to complete silence within two seconds. Dry and close. No music, no voice.

Prompt D, duration_seconds 3:
Power cut in a large hall: one loud breaker clunk, then four big ceiling lights shut off one after another with heavy relay clacks, each quieter and further away. Silence at the end. Dry, realistic. No hum at the end, no music, no voice.

Your shell has no network: do not try to download. For every finished take print its address on its own line in
your final message as `FILE l6_lights_out_C<N>.mp3 <url>` or `FILE l6_lights_out_D<N>.mp3 <url>` and list the same
lines in notes3.md with the length the connector reports. If the connector asks for a login or refuses, write
`NEEDS_LOGIN` (or the exact error) as the first line of notes3.md and of your final message, and stop. Do not retry
more than once. Do not generate anything else.
