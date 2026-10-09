# Discord -> Trello bot

Et nyt opslag i **bugs**-forummet bliver et kort i *To Do* med label **Bug**; et opslag
i **feedback**-forummet bliver et kort i *Ideas* med label **Feedback**, på boardet
[BACKROOMS: STAY QUIET – Development](https://trello.com/b/6FHYrsMR). Svar i tråden
bliver ikke til kort.

Botten reagerer med 👀 på opslaget når kortet er oprettet. Når kortet flyttes til
*Done* på Trello (tjekkes hvert minut), reagerer den med ✅, skriver
"✅ Fixed. Thanks for the report!" i tråden og sætter forum-tagget *Fixed* på opslaget
(tagget oprettes hvis det mangler). Teksten er `DONE_MESSAGE` i `bot.py`.

Bottens egne reaktioner er dens hukommelse: et opslag uden 👀 får et kort næste gang
botten starter, og et Done-kort hvis opslag mangler ✅ får sit tick. Ingen database.
Labels oprettes af botten selv første gang, hvis de mangler på boardet.

## Opsætning (én gang)

1. **Discord-server:** opret `#bugs` og `#feedback` som *forum*-kanaler. Slå
   Developer Mode til (User Settings -> Advanced), højreklik på hver kanal -> *Copy
   Channel ID*.
2. **Discord Developer Portal** (https://discord.com/developers/applications):
   *New Application* -> *Bot* -> *Reset Token* og gem det. Slå **Message Content
   Intent** til under *Privileged Gateway Intents*. Under *OAuth2 -> URL Generator*:
   scope `bot`, permission *Administrator* (ejerens valg; det mindste der virker er View
   Channels, Send Messages in Threads, Read Message History, Add Reactions, Manage Channels,
   Manage Threads). Åbn URL'en og invitér botten til serveren.
3. **Trello:** https://trello.com/power-ups/admin -> lav en Power-Up (navnet er
   ligegyldigt) -> *API key*. Klik *Token* ved siden af nøglen og godkend.
4. **Render:** *New -> Background Worker* -> vælg dette GitHub-repo.
   Root Directory `tools/discord_trello_bot`, Build Command
   `pip install -r requirements.txt`, Start Command `python bot.py`, plan *Starter*.
   Environment variables:

   | Navn | Værdi |
   |---|---|
   | `DISCORD_TOKEN` | bot-token fra trin 2 |
   | `TRELLO_KEY` | API key fra trin 3 |
   | `TRELLO_TOKEN` | token fra trin 3 |
   | `BUGS_CHANNEL_ID` | id fra trin 1 |
   | `FEEDBACK_CHANNEL_ID` | id fra trin 1 |

   Root Directory gør at kun ændringer i denne mappe udløser et nyt deploy.

Loggen skal vise `Logged in as <botnavn>`.

## Køre lokalt

Udfyld `tools/discord_trello_bot/.env` (gitignoreret) med de tre tokens:

```
DISCORD_TOKEN=...
TRELLO_KEY=...
TRELLO_TOKEN=...
```

Kanal-id'erne for de to forummer er standardværdier i `bot.py`; sæt
`BUGS_CHANNEL_ID` / `FEEDBACK_CHANNEL_ID` i `.env` kun hvis de ændrer sig. Så:

```
pip install -r tools/discord_trello_bot/requirements.txt
python tools/discord_trello_bot/bot.py
```

Test af kort-mappingen: `python tools/discord_trello_bot/test_bot.py` (ingen output = OK).

## Server-layout

`python tools/discord_trello_bot/setup_server.py` bygger serverens roller (Team,
Supporter, Tester), kategorier og kanaler (INFO, COMMUNITY, DEV, STAFF), og sætter
tags, post-guidelines og "tag påkrævet" på de to forummer. Alt der allerede findes med
samme navn springes over, så scriptet kan køres igen efter en rettelse i `LAYOUT`.
Botten skal have Administrator (eller Manage Roles + Manage Channels).

## Bevidst udeladt

- Ingen sync fra Trello tilbage til Discord. Kræver Trello-webhook + HTTP-endpoint,
  dvs. en web service i stedet for en worker.
- Ingen dublet-detektion mellem opslag; det er triage på boardet.
