"""Post a markdown file to a channel as the bot.

Run: python tools/discord_trello_bot/post.py <channel-name> <file.md>
The channel is matched by substring ("rules" finds "📖-rules"). The file is split into
separate messages on lines that contain only "---"; each part must fit Discord's
2000-character limit. Discord renders **bold**, *italics*, # headings and lists.
"""
import pathlib
import sys

import discord

from bot import env, load_dotenv

sys.stdout.reconfigure(encoding="utf-8")
load_dotenv()
channel_name, path = sys.argv[1], pathlib.Path(sys.argv[2])
parts = [p.strip() for p in path.read_text(encoding="utf-8").split("\n---\n") if p.strip()]
too_long = [i for i, p in enumerate(parts, 1) if len(p) > 2000]
if too_long:
    sys.exit(f"part(s) {too_long} exceed 2000 characters; add a --- line to split them")


class Post(discord.Client):
    posted = False

    async def on_ready(self):
        if self.posted:  # on_ready fires again after a gateway reconnect
            return
        self.posted = True
        try:
            channel = next(c for g in self.guilds for c in g.text_channels if channel_name in c.name)
            for part in parts:
                await channel.send(part)
            print(f"posted {len(parts)} message(s) in #{channel.name}")
        finally:
            await self.close()


Post(intents=discord.Intents.default()).run(env("DISCORD_TOKEN"))
