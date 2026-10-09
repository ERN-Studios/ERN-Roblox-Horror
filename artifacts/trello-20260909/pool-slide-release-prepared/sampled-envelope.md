# Sampled envelope union at scale 6

Use **AnimatedEnvelopeRadius = 7.3** and **AnimatedEnvelopeHeight = 16.1** for the reviewed candidate, conditional on uploading the exact reviewed curves and the remaining native encounter acceptance. These round the saved finite-sample union upward. They do not prove an upper bound over every unsampled animation instant.

| Included evidence | Radius | Minimum Y | Maximum Y | Union height | Poses/frames |
| --- | ---: | ---: | ---: | ---: | ---: |
| Native static full box (8 corners) | 6.095187664032 | -6.000000000000 | 6.000000000000 | 12.000000000000 | 1 |
| Idle | 5.979034423828 | -6.000404357910 | 5.848510742188 | 11.848915100098 | 521 |
| Walk | 6.138674259186 | -6.004219055176 | 6.215194702148 | 12.219413757324 | 159 |
| Run | 6.743620395660 | -6.004425048828 | 7.781372070312 | 13.785797119141 | 117 |
| Attack | 7.219158649445 | -6.001052856445 | 9.711853027344 | 15.712905883789 | 196 |
| 72 valid frozen blend cases | 7.218271255493 | -6.211700439453 | 9.321090698242 | 15.532791137695 | 1224 |
| 28 valid fresh quarter-loop fades | 7.157289505005 | -6.301979064941 | 9.099945068359 | 15.401924133301 | 580 |
| **Combined union** | **7.219158649445** | **-6.301979064941** | **9.711853027344** | **16.013832092285** | |

Exact binary-decimal values, source hashes and selection checks are in `sampled-envelope.json`; reproduce the reduction with `python compute_sampled_envelope.py`. No engine probe is run by this script.

The V2 dense SOLO Attack supplies the largest radius and maximum Y. The fresh Walk→Idle fade at outgoing phase0.5 supplies the minimum Y. Height is **global maxY minus global minY**, not the largest individual case height. The existing scale-6 native full-box measure is radius6.095187664031982, Y−6 to+6, height12, and pivot-to-lowest-bounds GroundOffset6; all three skin reports agree. No new static probe is needed to establish this saved measurement.

The 12 guarded native quarter-loop parity cases compare20 bones at weight1 with one active track per side. Their maximum position difference is 1.1944189282076e-07 studs, angle difference 0.000690533954184502 radians. Together with the reviewed curve-preserving quarter-loop builder, this supports carrying forward the SOLO Walk curve's sampled bounds under a phase shift; it contributes no new skin vertices or extrema. The older frozen grid uses original Walk phase coordinates and remains conservative additional sampled blend coverage, not a claim that its schedule is the new quarter-loop runtime schedule.

The72 frozen cases contain1224 samples with effective weight sum exactly1. The report's top-level `ok=false` belongs to its later failed realtime branch, which is excluded. Its `maxInactiveRawWeight=1` is a stopped track, with validated inactive endpoint/reference handling; it is not active blend influence. The dense V2 report's invalid transition matrix (`maxWeightError=1`) and aggregate `sampledSkin` are entirely excluded. Only its four independently observed SOLO clip measurements are included.

The28 fresh quarter-loop fades contain580 full-skin frame samples and are validly executed with maximum weight error 8.94069671630859e-08. Their contactPass remains **false** (minimum plane gap−0.22197906494140623): this numerical union does not relabel the residual blend penetration as planted-foot success. Root/critic's native-result review treats it as a disclosed cosmetic limitation pending actual in-game viewing.

Rounding adds radius margin0.080841350555 and height margin0.086167907715 above these samples. The unchanged controller then requires agent radius≥7.4 and height≥16.4; configured **7.5 /16.7** exceeds those requirements by0.1 /0.3. Both static and animated assertions fit. This arithmetic does not replace moving-navigation, contact, attack, cleanup or owned-upload acceptance. Verification flags remain false until those requirements are satisfied.
