Level 6 RETURN prompt visibility fix

The actual Play issue was reported by the root agent: the RETURN prompt was at the tube landing underfoot and became visible only when looking down. This proposed existing-Source-only change mounts that prompt on an owned runtime Attachment ahead of the normal arrival camera. No Studio or native Edit instances were changed by this author.

Exact current live Source/editor baseline supplied by root: `0829dc2fed34719fde2937a51a7a18f22f7ea64aa5d89ae06cbc2bb54b193868`, 12632 bytes. Final proposed Source: `bc8e8f0722f023e22f5daedffa9929d4232eef62a170d592c473a7852f48d8f3`, 14689 bytes.

Full-source syntax and 23 actual changed-source fragment regressions passed using native Vector3/CFrame and a mocked Instance/player/streaming graph. The inverse-scope test exactly reconstructs the live baseline by reverting only the RETURN constants/helpers/two parent guards/queue-ready lookup. These are offline checks and do not demonstrate actual E visibility, real streaming or multiplayer.

Actual Claude Opus 5.5/max reviewed the initial `3cd367…` candidate and completed successfully in 317.578 seconds with literal PASS. Root then requested two mechanical corrections to its nonblocking range/portrait findings: offset `(1, 1.5, -4)` and mounted RETURN MaxActivationDistance `7.5`. Codex reviewed/tested those exact corrections; Claude did not review the final `bc8e…` candidate. The triangle-inequality proof gives an activation-distance bound of 11.887482193696 studs, inside the preserved 12-stud server guard. Actual arrival distance is 4.6733 studs, and native geometric tests verify the normal camera and 9:16 portrait view fit at a 70-degree vertical FOV. ENTER remains 10 studs; all other RETURN properties/identity are preserved.

Root owns fresh guarded live CAS and subsequent actual Play verification. PBR reviewer owns the eight-source final catalog and must pin this Source only after root verifies the live result. Existing permission, campaign, entry prompts, streaming and Runtime.Join/Leave paths remain intact. The new Attachment exists only in the generated runtime world and disappears when Play stops.
