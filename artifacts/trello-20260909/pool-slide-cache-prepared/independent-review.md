# Independent cache and probe review

Reviewer: `/root/audio_readiness`. **9/10**, bounded diagnostic artifact. No code blocker found. This score does not certify a production rig or native candidate result.

I independently read the extractor, reader, transfer/schema validator and all declared source seams, reran 15,136 actual-source extractor/reader/original-mapping checks plus 13 Python transfer/negative/preservation checks, and compiled all five complete Luau sources. Both cached probes reverse to their complete original sources; mesh mapping, coverage, weights, phase/endpoint assertions and cleanup are unchanged.

The actual exported cache SHA is `c783fd090b22802aee5ec3e13cd6a4319ef355f6f5854cca1e44e56464061e61`: 7,931,138 bytes, 199 chunks, 15,091 vertices, 20 bones per mesh and 60,364 influences. My separate inverse-bind calculation over every influence found maximum unscaled error 2.0859052438704221e-7. I verified the XML's complete byte-for-byte cache roundtrip independently.

The extractor is Edit-only, checks restpose and exact identity/counts, cleans every opened EditableMesh on success/failure, compares the rig before/after yielding reads and only publishes complete scratch data. The loader retains uniform-scale/rest/parent/mesh fingerprint checks, corruption checks and inverse-bind consistency. The cache contains raw mesh-local data: the inherited probe still derives actual clone bind scale and checks rest-space and vertex mapping rather than guessing an origin or reusing only bone bounds.

Native Animator sampling, rendered feet, finite-phase coverage and the eventual production mechanism remain separate acceptance. The local DJB2 checks are corruption/transfer guards, not an adversarial signature; the external payload SHA establishes artifact identity. No settings, runtime files, Studio objects or asset IDs were changed by this review.

Reviewed hashes are recorded in `independent-review.json`.
