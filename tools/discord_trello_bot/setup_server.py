"""One-off Discord server layout. Idempotent: anything that already exists by name is
left alone, so it can be re-run after editing LAYOUT.

Run: python tools/discord_trello_bot/setup_server.py   (uses the same .env as bot.py;
the bot needs Administrator, or at least Manage Roles + Manage Channels).
"""
import sys

import discord
from discord import PermissionOverwrite as PO

from bot import env, load_dotenv

sys.stdout.reconfigure(encoding="utf-8")  # emoji in channel names, also when piped
load_dotenv()
BUGS = int(env("BUGS_CHANNEL_ID", "1545382711987015690"))
FEEDBACK = int(env("FEEDBACK_CHANNEL_ID", "1545382744945594510"))

# name -> (colour, hoist in member list, permissions beyond @everyone); top of the
# hierarchy first. STAFF_ROLES can see the STAFF category and write in INFO.
MODERATION = discord.Permissions(manage_messages=True, manage_threads=True, moderate_members=True, kick_members=True)
ROLES = {
    "Admin": (discord.Colour.dark_red(), True, discord.Permissions(administrator=True)),
    "Developer": (discord.Colour.purple(), True, MODERATION),
    "Team": (discord.Colour.red(), True, MODERATION),
    "Bot": (discord.Colour.blurple(), True, discord.Permissions.none()),
    "Supporter": (discord.Colour.gold(), True, discord.Permissions.none()),
    "Tester": (discord.Colour.green(), False, discord.Permissions.none()),
}
STAFF_ROLES = ["Admin", "Developer", "Team"]
OWNER_ROLES = ["Admin", "Developer", "Team"]  # given to the server owner
BOT_ROLES = ["Bot"]

# category -> [(name, kind)]; kind: text | voice | forum:<existing channel id>
# "team-only" and "staff" are permission presets applied by overwrites_for().
LAYOUT = [
    ("INFO", [("📢-announcements", "team-only"), ("📋-patch-notes", "team-only"), ("📖-rules", "team-only")]),
    ("COMMUNITY", [("💬-general", "text"), ("🎮-find-a-team", "text"), ("📸-clips", "text"),
                   ("🔊 Lobby", "voice"), ("🔊 Squad 1", "voice"), ("🔊 Squad 2", "voice")]),
    ("DEV", [("🐛-bugs", f"forum:{BUGS}"), ("💡-feedback", f"forum:{FEEDBACK}")]),
    ("STAFF", [("🔒-team", "staff")]),
]

FORUMS = {
    BUGS: dict(
        topic="Title: what happens. Text: how to make it happen, which level, and a screenshot "
              "or video if you have one. One bug per post.",
        tags=["Lobby", "Level 1", "Level 2", "Level 3", "UI", "Audio", "Performance"], done="Fixed"),
    FEEDBACK: dict(
        topic="One idea per post, so it can get its own card.",
        tags=["Idea", "Balance", "Levels", "UI"], done="Added"),
}


def overwrites_for(guild, staff, kind):
    everyone = guild.default_role
    if kind == "team-only":
        return {everyone: PO(send_messages=False, create_public_threads=False, create_private_threads=False),
                **{role: PO(send_messages=True) for role in staff}}
    if kind == "staff":
        return {everyone: PO(view_channel=False), **{role: PO(view_channel=True) for role in staff}}
    return {}


def same_name(a, b):
    return a.lower().replace(" ", "-") == b.lower().replace(" ", "-")


class Setup(discord.Client):
    def __init__(self):
        super().__init__(intents=discord.Intents.default())

    async def on_ready(self):
        try:
            for guild in self.guilds:
                print(f"== {guild.name}")
                await self.setup(guild)
        finally:
            await self.close()

    async def setup(self, guild):
        roles = {}
        for name, (colour, hoist, perms) in ROLES.items():
            role = discord.utils.get(guild.roles, name=name)
            if role is None:
                role = await guild.create_role(name=name, colour=colour, hoist=hoist, permissions=perms)
                print(f"  + role {name}")
            roles[name] = role
        # Hierarchy in ROLES order, directly under the bot's own managed role (it cannot
        # move anything above itself, and must sit above every role it hands out).
        top = guild.me.top_role.position
        await guild.edit_role_positions({roles[n]: top - 1 - i for i, n in enumerate(ROLES)})
        team = [roles[n] for n in STAFF_ROLES]

        owner = await guild.fetch_member(guild.owner_id)
        for member, names in ((owner, OWNER_ROLES), (guild.me, BOT_ROLES)):
            missing = [roles[n] for n in names if roles[n] not in member.roles]
            if missing:
                await member.add_roles(*missing)
                print(f"  + {member.name}: {', '.join(r.name for r in missing)}")

        for cat_name, channels in LAYOUT:
            category = next((c for c in guild.categories if same_name(c.name, cat_name)), None)
            if category is None:
                category = await guild.create_category(cat_name)
                print(f"  + category {cat_name}")
            for name, kind in channels:
                overwrites = overwrites_for(guild, team, kind)
                if kind.startswith("forum:"):
                    forum = guild.get_channel(int(kind.split(":")[1]))
                    await forum.edit(name=name, category=category)
                    await self.setup_forum(forum, FORUMS[forum.id])
                    continue
                existing = next((c for c in guild.channels if same_name(c.name, name)), None)
                if existing:
                    if overwrites:  # keep permissions in step with STAFF_ROLES
                        await existing.edit(overwrites=overwrites)
                    continue
                if kind == "voice":
                    await category.create_voice_channel(name)
                else:
                    await category.create_text_channel(name, overwrites=overwrites)
                print(f"  + {kind} {name}")
            if cat_name == "STAFF":
                await category.edit(overwrites=overwrites_for(guild, team, "staff"))

    async def setup_forum(self, forum, spec):
        tick = discord.PartialEmoji(name="\N{WHITE HEAVY CHECK MARK}")
        wanted = [(t, None) for t in spec["tags"]] + [(spec["done"], tick)]
        tags = list(forum.available_tags)
        for name, emoji in wanted:
            if not discord.utils.get(tags, name=name):
                tags.append(discord.ForumTag(name=name, emoji=emoji))
        # Two calls: Discord validates require_tag against the tags that exist before the edit.
        forum = await forum.edit(available_tags=tags, topic=spec["topic"])
        await forum.edit(require_tag=True)
        print(f"  ~ forum {forum.name}: {len(tags)} tags, guidelines, tag required")


if __name__ == "__main__":
    Setup().run(env("DISCORD_TOKEN"))
