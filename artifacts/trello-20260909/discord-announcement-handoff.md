# Final Discord announcement — prepared route, not sent

The user explicitly authorized one announcement about the published changes,
tagging **@everyone**, **when the whole requested work is finished**. This record
does not satisfy that timing condition and no message was sent during discovery.
Server messages are in English according to the existing project memory.

## Existing bot and verified destination

- Project: `G:\Roblox\MongoTV\tools\discord_trello_bot`.
- Running process observed: Python **PID 31000**, script argument
  `tools/discord_trello_bot/bot.py`. No process was restarted or modified.
- Bot: **ERN Studios**, user/client ID **1545383192704581702**.
- Server: **Backrooms: Stay Quiet Development**, ID **1545382354594562068**.
- Destination: **📢-announcements**, channel ID **1545397231639597056**,
  <https://discord.com/channels/1545382354594562068/1545397231639597056>.
- `📋-patch-notes` is a distinct channel, ID **1545397233145479198**.
- Read-only Discord API checks confirmed the bot has Administrator and therefore
  View Channel, Send Messages, Read Message History and Mention Everyone.
- A read of the latest 100 announcements messages returned **zero messages** at
  discovery on 9 September 2026. Re-read immediately before eventual sending;
  this is a dated observation, not a permanent guarantee that the channel is empty.

The existing `bot.load_dotenv()` reads the gitignored `.env` beside `bot.py`.
Use that loader and `env("DISCORD_TOKEN")` internally. Do not print, copy, inline
or rewrite the credentials. Discovery used this existing credential path only
for authenticated read-only channel/guild/permission/history requests. No token
or environment-file contents were emitted.

## Existing posting command

`post.py` already posts a markdown file as this bot and closes its separate
client afterward; the running forum-to-Trello worker can remain active.
It does not create a Trello card. The command for **later**, from the project
root, is:

```powershell
python tools/discord_trello_bot/post.py announcements artifacts/trello-20260909/final-announcement.md
```

The draft file does not exist yet; write it only after the actual final published
scope is known. Begin it with a single `@everyone`, describe only verified
published changes, and include material gameplay limitations such as any entity
still disabled. The present published releases are v1813 (Level 2 spawn hotfix)
and v1814 (Level 3 run-in exit), but later work must be reflected before sending.

The CLI matches channel names by **substring across all joined guilds**, then
sends to the first match. Discovery found exactly one matching announcements
channel. Reconfirm that uniqueness and the guild/channel IDs immediately before
running it. It splits content on a standalone `---` and refuses parts longer
than 2000 characters. Prefer **one message under 2000 characters** to avoid
partial multi-message sends and duplicate @everyone notifications.

## One-send tracking and retry behavior

The CLI's `posted` flag only prevents a repeat inside the same process after a
gateway reconnect. **It has no persistent idempotency or receipt journal.**
Do not infer safe retry from its exit code or a missing success line.

1. Once all work is finished, finalize the exact draft, compute its SHA-256 and
   character count, and record the digest in `discord-announcement-state.json`.
   Keep one message and one @everyone mention.
2. Re-read announcements history and confirm no message from bot ID
   1545383192704581702 already has exactly the draft content/hash. Confirm the
   unique destination above and write status `sending` with an attempt time.
3. Invoke the existing CLI **once**. No bot restart or server-layout script is
   needed; do not run `setup_server.py`.
4. Read the destination history, find the bot's exact-content message, verify
   `mention_everyone=true`, and record its message ID, timestamp, content digest
   and message URL with status `sent`.
5. If output, timeout or connection failure makes the outcome uncertain, retain
   status `uncertain` and inspect history first. Do not resend while a prior
   attempt may still be running or before resolving whether it already posted.
   The CLI itself cannot guarantee exactly-once delivery across crashes.

The bot's normal Trello Done watcher is separate: it polls every 60 seconds and
uses its own reactions to prevent repeating a short reply in a linked bug or
feedback forum thread. That mechanism does not deduplicate a general release
announcement.

Relevant source: `tools/discord_trello_bot/post.py`, `bot.py`, `README.md`, and
`setup_server.py`. Only documentation/artifact files were written for this task;
no bot code, config, process, Trello card or Discord content was changed.
