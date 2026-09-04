"""Discord forum posts -> Trello cards, and Trello "Done" -> a tick in the thread.

One forum post in the bugs or feedback forum becomes one card. The bot's own
reactions on the post are its only state, so there is no database:
  eyes  = a card exists (a post without it gets a card on startup)
  tick  = the card reached the Done list; the bot also replies and tags the post
The Done list is polled once a minute; each card carries its thread link in
the description. Manual setup lives in README.md.
"""
import asyncio
import os
import pathlib
import re
import sys

import aiohttp
import discord

TRELLO = "https://api.trello.com/1"
BOARD_ID = "6a9808124df96806af3f205d"  # BACKROOMS: STAY QUIET - Development
LIST_TODO = "6a980822a4600c96defb1f7d"
LIST_IDEAS = "6a981231562730357340e9ed"
LIST_DONE = "6a980826fad773b14dcac79f"
EYES, TICK = "\N{EYES}", "\N{WHITE HEAVY CHECK MARK}"
DONE_POLL_SECONDS = 60
DESC_LIMIT = 5000
THREAD_LINK = re.compile(r"https://discord\.com/channels/\d+/(\d+)")
DOTENV = pathlib.Path(__file__).with_name(".env")


def build_card(title, body, author, thread_url, attachment_urls=()):
    """Pure mapping from a forum post to Trello's POST /cards fields."""
    header = "\n".join([thread_url, f"- {author}", *attachment_urls])
    body = body.strip() or "(ingen tekst)"
    desc = f"{header}\n\n{body}"
    if len(desc) > DESC_LIMIT:
        desc = desc[: DESC_LIMIT - 3] + "..."
    return {"name": title[:16384], "desc": desc}


def thread_id_of(card_desc):
    """Thread id from the link build_card put first in the description, or None."""
    m = THREAD_LINK.search(card_desc or "")
    return int(m[1]) if m else None


def has_own_reaction(message, emoji):
    return any(r.emoji == emoji and r.me for r in message.reactions)


def env(name, default=None):
    value = os.environ.get(name) or default
    if not value:
        sys.exit(f"missing environment variable {name} (set it or put it in {DOTENV})")
    return value


def load_dotenv():
    """KEY=VALUE lines from a gitignored .env next to this file, for local runs."""
    if DOTENV.exists():
        for line in DOTENV.read_text(encoding="utf-8").splitlines():
            key, sep, value = line.partition("=")
            if sep and not line.lstrip().startswith("#"):
                os.environ.setdefault(key.strip(), value.strip())


class Bot(discord.Client):
    def __init__(self, routes, key, token):
        intents = discord.Intents.default()
        intents.message_content = True  # needed to read the post body
        super().__init__(intents=intents)
        self.routes = routes  # forum channel id -> route dict, see main()
        self.auth = {"key": key, "token": token}
        self.labels = {}  # label name -> id
        self.caught_up = False

    async def trello(self, method, path, **params):
        async with self.session.request(method, TRELLO + path, params={**params, **self.auth}) as r:
            r.raise_for_status()
            return await r.json()

    async def setup_hook(self):
        self.session = aiohttp.ClientSession()
        for label in await self.trello("GET", f"/boards/{BOARD_ID}/labels"):
            self.labels.setdefault(label["name"], label["id"])
        for route in self.routes.values():
            name, colour = route["label"]
            if name not in self.labels:
                made = await self.trello("POST", "/labels", name=name, color=colour, idBoard=BOARD_ID)
                self.labels[name] = made["id"]
        self.loop.create_task(self.watch_done())

    async def close(self):
        if getattr(self, "session", None):
            await self.session.close()
        await super().close()

    # --- forum post -> card -------------------------------------------------

    async def on_ready(self):
        print(f"Logged in as {self.user}")
        if self.caught_up:
            return
        self.caught_up = True
        for guild in self.guilds:
            for thread in await guild.active_threads():
                if thread.parent_id in self.routes:
                    starter = await thread.fetch_message(thread.id)
                    if not has_own_reaction(starter, EYES):
                        await self.handle(thread, starter)

    async def on_message(self, message):
        # A forum post's starter message shares its id with the thread. Handling it
        # here rather than in on_thread_create avoids racing the message's creation.
        thread = message.channel
        if isinstance(thread, discord.Thread) and message.id == thread.id and thread.parent_id in self.routes:
            await self.handle(thread, message)

    async def handle(self, thread, starter):
        route = self.routes[thread.parent_id]
        card = build_card(thread.name, starter.content, str(starter.author), thread.jump_url,
                          [a.url for a in starter.attachments])
        made = await self.trello("POST", "/cards", idList=route["list"],
                                 idLabels=self.labels[route["label"][0]], **card)
        await starter.add_reaction(EYES)
        print(f"card {made['shortUrl']} <- {thread.parent} / {thread.name}")

    # --- card in Done -> tick in thread --------------------------------------

    async def watch_done(self):
        await self.wait_until_ready()
        seen = set()  # thread ids already ticked (or gone); refilled from reactions after a restart
        while not self.is_closed():
            try:
                for card in await self.trello("GET", f"/lists/{LIST_DONE}/cards", fields="desc"):
                    thread_id = thread_id_of(card["desc"])
                    if thread_id and thread_id not in seen:
                        await self.announce_done(thread_id)
                        seen.add(thread_id)
            except Exception as exc:  # keep polling; the next round retries
                print("watch_done:", repr(exc))
            await asyncio.sleep(DONE_POLL_SECONDS)

    async def announce_done(self, thread_id):
        try:
            thread = self.get_channel(thread_id) or await self.fetch_channel(thread_id)
            starter = await thread.fetch_message(thread_id)
        except discord.NotFound:
            return  # post deleted; nothing to tick
        if has_own_reaction(starter, TICK):
            return
        forum = thread.parent
        route = self.routes[forum.id]
        await starter.add_reaction(TICK)
        await thread.send(route["done_message"])
        tag = (discord.utils.get(forum.available_tags, name=route["done_tag"])
               or await forum.create_tag(name=route["done_tag"]))
        if tag not in thread.applied_tags:
            await thread.edit(applied_tags=[*thread.applied_tags, tag])
        print(f"fixed -> {forum} / {thread.name}")


def main():
    load_dotenv()
    routes = {
        int(env("BUGS_CHANNEL_ID", "1545382711987015690")): dict(
            list=LIST_TODO, label=("Bug", "red"), done_tag="Fixed",
            done_message=f"{TICK} Fixed. Thanks for the report!"),
        int(env("FEEDBACK_CHANNEL_ID", "1545382744945594510")): dict(
            list=LIST_IDEAS, label=("Feedback", "blue"), done_tag="Added",
            done_message=f"{TICK} Added. Thanks for the idea!"),
    }
    Bot(routes, env("TRELLO_KEY"), env("TRELLO_TOKEN")).run(env("DISCORD_TOKEN"))


if __name__ == "__main__":
    main()
