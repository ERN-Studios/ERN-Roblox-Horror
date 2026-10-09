"""B6 hold/leave contract now runs against actual imported Framewisp controls.

The former UIStyle fake did not model the new template tree. The shared B6/B7
runner executes the entire exit client, drives L/View and real signal handlers,
15/60/240 FPS, cancellation gates, pending/latch, refusal/retry and stale timers.
It also verifies the prompt/hiding integrations that share its RoundHud APIs.
Native cursor, glyph and platform Menu input require the Studio pass.
"""
from test_hud_b6_b7 import main

if __name__ == "__main__":
    main()
