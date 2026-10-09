# Independent contact-copy review — 10 September 2026

The actual contact-copy builder was executed in a small, isolated Luau instance-data host against the original authored clip export. This did not run Studio, alter any input curve, change production source or upload an asset. Input SHA256 values and reproducible output are in `critic-pool-slide-contact-review.json`; rerun with `LUAU_BIN` using the adjacent Python artifact.

## Child channels and Root-Y math

All 19 child channels in each of Idle, Walk and Run retain their complete original timestamp, CFrame, easing and weight lists: 3,287 original child-pose keys are identical. The 170 inserted keys contain only RootPart → Root. The actual builder preserves loop/priority/markers and excludes Attack. Across original, inserted and dense sample phases, 32,927 child-channel interpolation brackets are identical. This proves preservation of the channel data and of interpolation under a per-channel evaluator. The host does not impersonate or certify Roblox Animator's native sparse-key evaluation.

The Root bind inverse converts the world-up correction into the actual imported bone axes; dividing the desired displacement by model scale6 is consistent with the measured identity Root poses and upright 180-degree Y bind. Root's native corrected full-skin report independently supports the resulting scale: comparing the same foot groups and times against the original report gives maximum X/Z discrepancy0.002184 studs and maximum Y discrepancy after subtracting the predicted Root correction0.002220 studs. Attack's compared foot samples are exactly identical. This is strong evidence against a child-channel identity reset at inserted keys; it is not a comparison of every native child rotation at every time.

The corrected native full-skin minimum plane gaps are Idle0.079649, Walk0.079763 and Run0.080099 studs. These are full mesh bounds, not only the selected foot groups. Unchanged Attack still reaches −0.220911 studs at its beginning and remains a separate correction/review. Continuous-time extrema, transition blends, contact on actual terrain and horizontal slip are not certified by frozen samples.

## Optional minimal Walk loop candidate — do not apply now

The original candidate has equal Root-Y values at time0 and length1.0333333015. Its piecewise-linear endpoint velocities differ by4.514465 studs/s. The smallest change that preserves those endpoint values and uses the existing key grid changes only the adjacent keys:

| Time | Existing world-Y delta | Optional world-Y delta |
|---:|---:|---:|
| 0.0166666662 | −1.4435043335 | −1.4058837891 |
| 1.0166666354 | −1.3456802368 | −1.3080596924 |

Both keys rise0.0376205444 studs. The two wrap slopes become −2.934723 studs/s. With the same linear Root interpolation this only raises the original curve, so it cannot add penetration relative to that curve. Predicted lowest-foot gap rises at those samples from0.08 to0.117621; the near-end sampled minimum remains0.079924 because the measured last pose was length−0.0001. The affected window extends0.033333 seconds on each side of the loop.

This does **not** make the entire motion smoother: it moves acceleration to nearby keys, with the largest adjacent slope jump increasing from8.303833 to8.724060 studs/s. Root motion is compensating the authored Hips movement; judging Root velocity alone can therefore recommend a harmful change.

Root's subsequent native continuous Walk report covers200 frames/3.315081 seconds and three wraps at approximately0.924 clip rate. I independently recomputed the three wrap hip-Y frame changes as0.007950,0.006737 and0.005524 studs, versus the overall maximum0.051460. This evidence gives no reason to apply Root-only smoothing. Keep the existing candidate; the separate optional curve is retained for comparison only if an actual body-motion problem is observed. The evidence is numeric and static-image inspection, not a watched video or full rig release approval.
