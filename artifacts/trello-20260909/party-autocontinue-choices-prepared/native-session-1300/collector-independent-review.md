# Independent collector review — 9/10

Read the complete `collect_chunks.py` and `COLLECTOR.md`; independently ran `--self-test`, which passed the shuffled UTF-8, missing/duplicate/conflicting chunk, sequence-gap, identity, malformed-JSON, unrelated-output and invalid-index cases. **9/10 for this bounded log-reconstruction artifact; no blocker found.**

Only the three named native log files are read. Only matching CreatorOutput messages are extracted. Side/UserId/run/sequence identity is retained and checked against the joined JSON; parts must occur exactly once with consistent advertised totals. Incomplete messages, duplicate parts, missing sequences and parse errors remain explicit. Raw payloads and source timestamps/line references are preserved. No Studio, source, gameplay or log mutations occur.

The collector's success is not evidence of gameplay success or a completed observer window. Missing trailing messages require comparison with Armed/Stopped records, as documented. The three derived output files are deliberately replaced on each collection; preserve the accepted evidence snapshot before later runs or log rotation. Native acceptance remains a separate interpretation of complete, correctly attributed messages.
