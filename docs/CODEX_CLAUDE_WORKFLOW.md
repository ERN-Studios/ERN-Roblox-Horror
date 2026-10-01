# Codex and Claude collaboration

Owner preference, October 1, 2026: use Codex together with actual Claude Opus
5.5 for this game's design and code work. Codex remains responsible for Studio
inspection, scoped edits, integration and verification. Ask Claude for an
independent critique using the relevant fresh evidence, then reconcile its
recommendations against the live game and the owner's request.

Use the highest supported effort for Claude Code. The installed CLI2.1.286
supports `max`; it does not expose an `ultra code` effort option. A successful
call must report the real canonical model (`claude-opus-5-5`) and requested
effort. Preserve a compact receipt of success, model, effort and tool use.
Do not claim Claude participated from a Codex sub-agent alone. If the actual
Claude connection is unavailable, report that limitation and continue useful
independent work without inventing a Claude review.

Send only task-relevant source, observations and images. Do not send credentials,
cookies, unrelated private records or entire caches. Give reviewers read-only
scope and keep one owner of Studio/UI mutations to avoid conflicting edits.

The owner's [Studio-authoritative workflow](../AGENTS.md) still governs source
baselines, backups, concurrent work, verification, commits and publication.
Concept images are design proposals; their generation does not install Blender
assets or revise the Roblox experience.
