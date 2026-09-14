# Purchase alert relay

Roblox game server -> this relay -> private Discord webhook.

`ServerScriptService.PurchaseAlerts` posts one JSON alert here after
`MarketplaceService.ProcessReceipt` has verified and committed a purchase. This
process holds the Discord webhook URL and forwards an embed to
`#dev-purchase-alerts`.

**Why a relay at all:** a Roblox game server cannot POST to discord.com. Discord
answers 403 to Roblox's `HttpService` user agent, and Roblox does not allow the
user agent to be overridden. The relay is the smallest thing that bridges that.

Standard library only — no `requirements.txt`, nothing to install.

## Contract

`POST /` with `Authorization: Bearer <RELAY_TOKEN>` and a JSON body:

```json
{"purchaseId":"...","productId":3707755089,"productKey":"Tokens4",
 "productName":"4 Research Tokens","kind":"Utility","robux":49,
 "playerName":"SomePlayer","userId":123,"placeId":1,"jobId":"...",
 "timestamp":"2026-09-14T10:11:12Z","test":false}
```

| Response | Meaning |
|---|---|
| `200` | forwarded to Discord |
| `202` | `purchaseId` already seen — not forwarded again |
| `400` | unreadable body, or no `purchaseId` |
| `401` | wrong or missing bearer token |
| `502` | Discord refused twice — the id is **not** remembered, so a retry works |

`GET /healthz` -> `200 ok`.

## Environment

| Name | Required | Meaning |
|---|---|---|
| `RELAY_TOKEN` | yes | shared secret; must equal the Roblox `ZYNTRA_PURCHASE_ALERT_TOKEN` secret |
| `DISCORD_WEBHOOK_URL` | yes | the `#dev-purchase-alerts` webhook |
| `PORT` | no | default `8787` (Render sets this itself) |
| `DEDUPE_FILE` | no | JSON file of forwarded PurchaseIds; without it dedupe lasts only as long as the process |

Neither secret is ever printed. The logs carry method, path and status only.

## Run locally

```sh
cd tools/purchase_alert_relay
RELAY_TOKEN=dev-token DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/... python relay.py
curl -s localhost:8787/healthz
```

On Windows PowerShell: `$env:RELAY_TOKEN="dev-token"` etc., then `python relay.py`.

For a Studio test, put the same two values on a `Configuration` (or `Folder`)
named **PurchaseAlertConfig** in `ServerStorage`, with string attributes
`Endpoint` (`http://localhost:8787/`) and `Token`. ServerStorage is server-only,
so no client can read either. Studio also needs Allow HTTP Requests on, and
Studio cannot reach `localhost` unless the relay runs on the same machine.

## Deploy on Render

*New -> Web Service* -> this GitHub repo.

| Setting | Value |
|---|---|
| Root Directory | `tools/purchase_alert_relay` |
| Build Command | *(leave empty)* |
| Start Command | `python relay.py` |
| Health Check Path | `/healthz` |
| Plan | Starter (a free instance sleeps and would drop the first alert) |

Environment variables: `RELAY_TOKEN` (generate a long random string),
`DISCORD_WEBHOOK_URL`. Add `DEDUPE_FILE` only with a persistent disk attached —
on an ephemeral filesystem it buys nothing, and the game server already
de-duplicates.

The public URL Render gives you is what goes into the Roblox secret
`ZYNTRA_PURCHASE_ALERT_URL`. Root Directory means only changes in this folder
trigger a redeploy.

## OPERATIONAL PREREQUISITES — owner only

**None of the steps below were performed.** They need Discord server ownership,
a Render account, the Creator Dashboard and a real purchase. Until all six are
done, `PurchaseAlerts` stays disabled and warns once per server; receipts and
grants are unaffected.

1. **Create `#dev-purchase-alerts`** in the Discord server as a *private*
   channel: deny `@everyone` View Channel, allow only the developer/admin role.
   The alerts name a player and the Robux they paid — do not make it public.
2. **Create the channel webhook**: channel settings -> Integrations -> Webhooks
   -> New Webhook -> Copy Webhook URL. Anyone with that URL can post to the
   channel; it goes into Render's environment and nowhere else.
3. **Deploy the relay** on Render as above and set `RELAY_TOKEN` and
   `DISCORD_WEBHOOK_URL`. Confirm `https://<service>.onrender.com/healthz`
   returns `ok`.
4. **Add the two Roblox secrets**: Creator Dashboard -> the experience ->
   Configure Experience -> Security -> Secrets:
   - `ZYNTRA_PURCHASE_ALERT_URL` = the Render URL, ending in `/`
   - `ZYNTRA_PURCHASE_ALERT_TOKEN` = the same value as `RELAY_TOKEN`
   Set the domain restriction to the Render host. Secrets are readable only by
   the server, never by Studio's edit mode and never by a client.
5. **Enable HTTP requests**: Studio -> Game Settings -> Security -> Allow HTTP
   Requests. It is currently OFF for this place, and with it off the module
   disables itself after the first attempt.
6. **One real purchase in production**, cheapest product, then confirm exactly
   one message in `#dev-purchase-alerts` with the right product, price, player
   and PurchaseId — and that Roblox's receipt retry (if any) does not produce a
   second one.

## Tests

```sh
python tools/tests/test_purchase_alert_relay.py   # this relay, over real HTTP
python tools/tests/test_purchase_alerts.py        # the Roblox module, under luau
```

The first starts `relay.py` on a free port against an in-process fake Discord;
no network, no real webhook. The second runs the real module source against a
fake Roblox host (`LUAU_BIN`, or `luau` on PATH).
