# One final announcement — route inspected, nothing sent

`announcement-final-prepared.md` is **not sendable**: its remaining literal `[PENDING ...]` square-button clause is a release gate, not a published claim. The light sentence was promoted only after confirmed v1873/9 publication. The existing `announcement-draft-published-only.md`, `discord-announcement-state.json` and bot sources are unchanged. No channel/history request or bot process was started during this preparation; the destination information below is the earlier verified discovery and must be refreshed at send time.

## Final content gate

After root verifies the actual square-button publication, replace the last pending clause with its plain player-facing sentence and record the real release version/evidence in `announcement-gates.json`. Loftlys v1873 is already confirmed there. Do not guess versions. Keep the new PLAYER ESP/free developer respawn out: the user deferred both, and the unpublished ESP installation was reverted. The earlier two-developer access restriction remains published, but does not need a player-facing announcement bullet.

Finish the user's agreed two-feature scope and Git commit/push, then create the actual `artifacts/trello-20260909/final-announcement.md` only from the finalized verified text. Require one `@everyone`, no `[PENDING`, no standalone `---`, and fewer than 2,000 characters **after the same `.strip()` that post.py applies**. Record SHA-256 of that exact stripped UTF-8 content, count and attempt time in the existing announcement state before any send. The current prepared copy is under the one-message limit; no split is needed.

## Existing route and its limitations

- Existing command: `python tools/discord_trello_bot/post.py announcements artifacts/trello-20260909/final-announcement.md`.
- Source inspection: `post.py` matches a channel name substring across every joined guild and takes the first match. Its `posted` flag only prevents a second on_ready send inside that process. It has no persistent dedupe, message-ID print or exactly-once retry guarantee.
- Bot: **1545383192704581702**, expected guild **1545382354594562068**, announcements channel **1545397231639597056**. Expected name `📢-announcements`; do not confuse patch-notes **1545397233145479198**.
- Reuse `bot.load_dotenv()` and `bot.env("DISCORD_TOKEN")` internally for authenticated read-only checks. Importing bot does not start its worker (`main()` is guarded). Do not print the token, headers, environment-file contents or entire API responses. No token is placed in a shell argument or URL.
- The already-running forum-to-Trello worker is independent; do not restart it or run `setup_server.py`. Its automatic Done reactions/replies do not deduplicate an announcements post.

## Minimal reliable one-send sequence for root

1. **Read before sending:** with the existing credential loader, confirm current bot identity and exact guild/channel ID; enumerate accessible text-channel names so substring `announcements` has exactly one match, the expected channel. Read recent messages from this channel and compare author ID plus exact stripped content/hash. If an earlier attempt exists, paginate as far back as that attempt time; a latest-100 window alone is not proof of absence in a busy channel. An already matching message means record its receipt, not send again.
2. Record state `sending` and `attemptStartedAt`; keep the frozen final content/hash. Invoke the existing post.py command **once**. Its `posted 1 message(s)` output is only an acknowledgement, not the final receipt.
3. **Read after sending:** fetch the destination history, locate exactly one matching message by bot ID + content/hash + the attempt time window, and fetch that concrete message ID again. Verify channel, author, exact content and `mention_everyone=true`. Save only message ID, timestamp, hash, mention flag and URL `https://discord.com/channels/1545382354594562068/1545397231639597056/<messageId>`; mark state `sent`.
4. If the CLI times out or the response is uncertain, retain `uncertain`, first ensure the same process is no longer running and inspect history. **Do not invoke post.py again just because its success line was lost.** If history read is denied or inconclusive, stop without a second send. A known message ID can be fetched directly. Do not delete/repost or add a second @everyone message to repair uncertainty.

These are the same channel/history methods recorded in `discord-announcement-handoff.md`, with the substring and missing-ID limitations made explicit. Use the existing Discord client/aiohttp read route rather than a new bot framework. No send, crosspost, channel change, process restart, UI, staging, commit or push was performed for this document.
