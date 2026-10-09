# Independent native unprotected control analysis

The full 53,875-byte JSON was parsed independently: 105 samples, three events, strictly increasing sample times, maximum interval 0.069202 seconds. Input SHA-256 is `8928a0c6c3356204c5e4ba2819ddfc1b459d7fdffc7ad250323438511b56e71d`.

Two actual entity touch callbacks (RightFoot and LeftFoot against `char1`) immediately precede capture `e05a8a7e-8194-4b2d-bbb3-a9b753375a71:1`. Capture starts 2.664407 seconds after the observer was armed.

| Observed transition | Seconds after capture event |
| --- | ---: |
| First active capture / anchored player / real Kill track sample | 0.034440 |
| First PlatformStand=true sample, beginning the pin | 1.499338 |
| First nearly horizontal player sample (absolute root-up Y <0.05) | 2.033421 |
| Last alive sample, HP100 | 4.083950 |
| First dead sample, HP0 | 4.149545 |

The actual `Kill_GroundPinPunch` track begins with observed phase 0.0375 and weight 0.3125, then reaches full weight. At the first dead sample it remains playing at phase 4.1499996 with weight1. The source's scheduled lethal time, 124/30 =4.133333 seconds, falls inside the measured last-alive/first-dead interval. Sampling brackets the death; it does not expose the exact Health assignment timestamp.

Every sample has private Active=false, Tokens5 and Charges2. There is no cancellation event, and the event list is far below its 160-entry cap. This is a useful unprotected capture/animation/death baseline, **not a protection-cancellation result**. Root's late Q/rejection observation is separate evidence; this server trace does not record keyboard input timing.

The observer correctly ends as `InterruptedByLifeOrRoundChange` at death, after 6.814029 of the requested20seconds. It therefore does not document the normal cleanup scheduled at five seconds after capture. For a future restoration comparison, use the last stable pre-capture position rather than the position when Arm was first called: physics can settle between setup and contact.

Machine-readable values, absolute timestamps and retained sample details are in `native-unprotected-control-analysis.json`. The analysis script only reads the recorded JSON and writes these analysis artifacts. No Studio, runtime or gameplay operations were performed.
