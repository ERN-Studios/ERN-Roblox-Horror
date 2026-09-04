"""Run: python tools/discord_trello_bot/test_bot.py  (no output = OK)."""
import pathlib
import sys
from types import SimpleNamespace as NS

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from bot import DESC_LIMIT, EYES, TICK, build_card, has_own_reaction, thread_id_of  # noqa: E402

card = build_card("Falder gennem gulvet", "x" * 9000, "krille", "https://discord.com/channels/1/2",
                  ["https://cdn.discordapp.com/a.png"])
assert card["name"] == "Falder gennem gulvet"
assert card["desc"].startswith("https://discord.com/channels/1/2\n- krille\nhttps://cdn.discordapp.com/a.png\n\nxxx")
assert len(card["desc"]) == DESC_LIMIT and card["desc"].endswith("...")
assert build_card("t", "   ", "a", "u")["desc"] == "u\n- a\n\n(ingen tekst)"

# the Done poller must find the thread the card came from, and only that
assert thread_id_of(card["desc"]) == 2
assert thread_id_of("no link here") is None and thread_id_of(None) is None

msg = NS(reactions=[NS(emoji=EYES, me=True), NS(emoji=TICK, me=False)])
assert has_own_reaction(msg, EYES) and not has_own_reaction(msg, TICK)
