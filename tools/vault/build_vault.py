# -*- coding: utf-8 -*-
"""Bygger Obsidian-vaulten 'Backrooms Stay Quiet' ud fra MongoTV-repoet.

Alle noter skrives gennem MCP-forbindelsen (create_vault_file) til
Obsidian-pluginnet paa 127.0.0.1:27200. Binaere medier kopieres direkte
ind i vaulten (base64 over JSON-RPC er forkert vaerktoej til 100 MB).

    python build_vault.py --dry     kun rapport
    python build_vault.py           byg og push
"""
import base64
import json
import os
import re
import shutil
import sys
import time
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(r"G:\Roblox\MongoTV")
VAULT = REPO / "Backrooms Stay Quiet"
MCP_URL = "http://127.0.0.1:27200/mcp"
TOKEN = "eUGfeGxbX5CV8Hzrlm0DVT44hmzIlprwmjWOMCy7qT8"
TODAY = "2026-09-03"

P_DOCS = "01 Projekt"
P_SYS = "02 Systemer"
P_CODE = "03 Kode"
P_ARCH = "04 Arkiv"
P_TOOLS = "05 Værktøjer"
P_ASSETS = "06 Assets"
P_META = "99 Meta"

_rpc = [100]


def mcp(name, args, retries=3):
    last = None
    for attempt in range(retries):
        _rpc[0] += 1
        body = json.dumps({"jsonrpc": "2.0", "id": _rpc[0], "method": "tools/call",
                           "params": {"name": name, "arguments": args}}).encode("utf-8")
        req = urllib.request.Request(
            MCP_URL, data=body, method="POST",
            headers={"Authorization": "Bearer " + TOKEN,
                     "Content-Type": "application/json",
                     "Accept": "application/json, text/event-stream"})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                payload = json.loads(r.read().decode("utf-8"))
            if "error" in payload:
                raise RuntimeError("MCP error: %s" % payload["error"])
            res = payload["result"]
            if res.get("isError"):
                raise RuntimeError("tool error: %s" % res["content"][0]["text"])
            return res["content"][0]["text"]
        except Exception as e:                      # noqa: BLE001
            last = e
            time.sleep(1 + attempt)
    raise last


# ------------------------------------------------------------------ helpers

def read_text(p):
    for enc in ("utf-8", "utf-8-sig", "latin-1"):
        try:
            return p.read_text(encoding=enc)
        except UnicodeDecodeError:
            continue
    return p.read_bytes().decode("utf-8", "replace")


def fence(src, lang):
    longest = max([len(m) for m in re.findall(r"`+", src)] or [0])
    bar = "`" * max(3, longest + 1)
    return "%s%s\n%s\n%s" % (bar, lang, src.rstrip("\n"), bar)


def q(s):
    return '"%s"' % str(s).replace('"', "'")


def dk(n):
    return format(int(n), ",").replace(",", ".")


def human(nbytes):
    for unit in ("B", "KB", "MB", "GB"):
        if nbytes < 1024 or unit == "GB":
            return ("%.0f %s" % (nbytes, unit)) if unit == "B" else ("%.1f %s" % (nbytes, unit))
        nbytes /= 1024.0


def header_comment(src, marker="--"):
    lines = src.split("\n")
    if lines and lines[0].lstrip().startswith("--[["):
        buf = []
        for line in lines:
            buf.append(line)
            if "]]" in line:
                break
        text = "\n".join(buf)
        text = text[text.find("--[[") + 4:]
        text = text[: text.find("]]")]
        return [l.strip() for l in text.strip().split("\n")]
    out, i = [], 0
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith(marker):
            out.append(s[len(marker):].strip().lstrip("-").strip())
            i += 1
        elif s == "" and not out:
            i += 1
        else:
            break
    while out and out[-1] == "":
        out.pop()
    return out


def py_header(src):
    m = re.match(r'\s*(?:#[^\n]*\n|\s*\n)*(?:"""|\'\'\')(.*?)(?:"""|\'\'\')', src, re.S)
    if m and m.group(1).strip():
        return [l.strip() for l in m.group(1).strip().split("\n")]
    return header_comment(src, "#")


def callout(lines, kind="abstract", title="Hvad den gør"):
    if not lines:
        return "> [!%s] %s\n> _Kilden har ingen beskrivende header-kommentar._" % (kind, title)
    return "> [!%s] %s\n%s" % (kind, title, "\n".join("> " + l if l else ">" for l in lines))


def slug(s):
    s = s.lower().replace("æ", "ae").replace("ø", "oe").replace("å", "aa")
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


SAFE = re.compile(r'[<>:"/\\|?*]')


def safe(s):
    return SAFE.sub("-", str(s)).strip().rstrip(".")


notes = {}          # vault-sti -> markdown
media = []          # (kilde-Path, vault-relativ-sti)


# ------------------------------------------------------- 1. Studio-spejlet

manifest = json.loads((REPO / "studio-sync-manifest.json").read_text(encoding="utf-8"))
items = manifest["items"]
ARCHIVE_RE = re.compile(r"Backup|Retired|Mirror", re.I)

# Håndskrevne resuméer til de scripts der ikke selv har en header-kommentar.
SUMMARIES = {
    "ServerScriptService.EntityAnimation": [
        "Kobler Level 1-entitetens Blender-eksporterede animationer til dens tilstand:",
        "Watch, Walk, Run, Howl, YellFromRun, Lunge, LungeFromRun og Kill.",
        "Afspilningshastigheden skaleres efter entitetens faktiske fart, og tomme",
        "asset-id-felter falder tilbage på et kompatibelt klip i stedet for at fejle.",
    ],
    "ServerStorage.Level2RetiredSlidemouth_20260831.Level 2 Slidemouth Controller": [
        "**Pensioneret 2026-08-31.** Serversiden af Level 2's Slidemouth-entitet:",
        "sessionsstyring (start, pause, genoptag, stop) og jagt/navigation via",
        "`Level 2 Pool Foam Navigator`.",
        "",
        "Den blev aldrig koblet op i en runde. I stedet er den erstattet af",
        "[[Level 2 Pool Slide Controller]], som Round Adapteren faktisk starter.",
    ],
    "ServerStorage.Level2RetiredSlidemouth_20260831.Level 2 Slidemouth Client": [
        "**Pensioneret 2026-08-31.** Klientdelen af Slidemouth: afspillede de fjerne",
        "rørlyde fra Level 2's lydbibliotek og gå-keyframes fra `Level 2 Assets`.",
    ],
    "ServerStorage.Level2RetiredSlidemouth_20260831.Level 2 Slidemouth Test Suite": [
        "**Pensioneret 2026-08-31.** Testsuiten for Slidemouth — 391 checks mod en",
        "rigtig genereret verden.",
        "",
        "Den fulgte med da Slidemouth blev pensioneret, og [[Level 2 Pool Slide Controller]]",
        "har **ingen tilsvarende suite**. Det er et reelt testhul.",
    ],
    "ServerScriptService.LobbyPartyModeController": [
        "Party-mode i lobbyen. Tweener loftslamperne gennem en neonpalet",
        "(Zyntra-cyan, elektrisk blå, violet, magenta, orange, syregrøn) i 10",
        "sekunder når den udløses, og sætter belysningen tilbage bagefter.",
    ],
    "Workspace.StarterCharacter.AnimateScript": [
        "Roblox' eget `Animate`-standardscript, der følger med spiller-rig'en.",
        "Styrer idle-, gang-, løbe-, hop- og faldeanimationer. Ikke projektkode.",
    ],
    "Workspace.Dummy.Animate": [
        "Roblox' eget `Animate`-standardscript på test-dummyen i Workspace.",
        "Ikke projektkode.",
    ],
    "StarterPlayer.StarterCharacter.Animate": [
        "Roblox' eget `Animate`-standardscript på spillerens StarterCharacter.",
        "Ikke projektkode.",
    ],
}


def classify(it):
    """Archive is now a place, not a naming convention.

    Until 2026-09-02 the backups were loose in the ServerStorage root and were
    recognised by a Backup|Retired|Mirror pattern in the folder name. They were
    then gathered under ServerStorage.Archive, and that pattern stopped matching
    them -- which silently reclassified 29 archive scripts as live, collided
    their leaf names with the real live ones (two GameManagers, two ZyntraStores)
    and renamed the live notes out from under every link pointing at them.
    One prefix, checked once.
    """
    segs = it["studioPath"].split(".")
    if segs[:2] == ["ServerStorage", "Archive"]:
        return "arkiv", segs[2] if len(segs) > 2 else "Archive"
    return "live", None


for it in items:
    kind, arch = classify(it)
    it["_kind"], it["_archive"] = kind, arch
    it["_segs"] = it["studioPath"].split(".")
    it["_leaf"] = it["_segs"][-1]
    it["_service"] = it["_segs"][0]
    p = REPO / it["file"]
    if it["className"] == "RemoteEvent":
        it["_src"], it["_lines"] = None, 0
    else:
        it["_src"] = read_text(p) if p.exists() else ""
        it["_lines"] = it["_src"].count("\n") + (1 if it["_src"] and not it["_src"].endswith("\n") else 0)

live_leaf = Counter(i["_leaf"] for i in items if i["_kind"] == "live")
used = set()
for it in items:
    if it["_kind"] == "live":
        base = it["_leaf"] if live_leaf[it["_leaf"]] == 1 else "%s (%s)" % (it["_leaf"], it["_segs"][-2])
    else:
        base = "%s — %s" % (it["_leaf"], it["_archive"])
    base, cand, n = safe(base), safe(base), 2
    while cand in used:
        cand = "%s (%d)" % (base, n)
        n += 1
    used.add(cand)
    it["_note"] = cand
    # Archive notes drop the redundant leading "ServerStorage/Archive" -- the
    # 04 Arkiv folder already says that.
    parents = it["_segs"][2:-1] if it["_kind"] == "arkiv" else it["_segs"][:-1]
    root = P_ARCH if it["_kind"] == "arkiv" else P_CODE
    it["_dir"] = "/".join([root] + [safe(x) for x in parents])
    it["_path"] = "%s/%s.md" % (it["_dir"], it["_note"])

LEAVES = sorted({i["_leaf"] for i in items}, key=len, reverse=True)
BY_LEAF = defaultdict(list)
for i in items:
    BY_LEAF[i["_leaf"]].append(i)

SERVICE_RE = re.compile(r'GetService\(\s*["\']([^"\']+)["\']\s*\)')
ATTR_RE = re.compile(r'[GS]etAttribute\(\s*["\']([^"\']+)["\']')


def relations(it):
    src = it["_src"] or ""
    refs = defaultdict(set)
    for leaf in LEAVES:
        if leaf == it["_leaf"]:
            continue
        if ('"%s"' % leaf) in src or ("'%s'" % leaf) in src:
            for tgt in BY_LEAF[leaf]:
                if tgt["_kind"] == it["_kind"]:
                    refs[tgt["className"]].add(tgt["_note"])
    return refs, sorted(set(SERVICE_RE.findall(src))), sorted(set(ATTR_RE.findall(src)))


def zone_of(it):
    p = it["studioPath"]
    if "Level 3" in p or "Level3" in p:
        return "Level 3"
    if "Level 2" in p or "Level2" in p:
        return "Level 2"
    if "Lobby" in p or "Tunnel" in p:
        return "Lobby"
    return "Kerne"


def script_note(it):
    refs, services, attrs = relations(it)
    zone = zone_of(it)
    tags = ["kode", "kode/" + slug(it["className"]), "service/" + slug(it["_service"]), "zone/" + slug(zone)]
    if it["_kind"] == "arkiv":
        tags.append("arkiv")
    fm = ["---",
          "type: %s" % ("remote" if it["className"] == "RemoteEvent" else "script"),
          "klasse: %s" % it["className"],
          "studio_sti: %s" % q(it["studioPath"]),
          "repo_fil: %s" % q(it["file"]),
          "service: %s" % q(it["_service"]),
          "zone: %s" % q(zone),
          "linjer: %d" % it["_lines"],
          "bytes: %d" % it["bytes"],
          "sha256: %s" % it["sha256"],
          "sync_status: %s" % it["status"],
          "vault_status: %s" % ("arkiv" if it["_kind"] == "arkiv" else "live"),
          "spejlet: %s" % TODAY,
          "tags:"] + ["  - %s" % t for t in tags] + ["---", ""]
    b = ["# %s" % it["_leaf"], ""]

    if it["className"] == "RemoteEvent":
        b += [callout(["RemoteEvent — en netværkskanal mellem server og klient, ikke kode.",
                       "Ligger i Studio på `%s`." % it["studioPath"]], "info", "Hvad den er"), "",
              "## Hvem bruger den", ""]
        users = sorted([o for o in items if o["_src"] and ('"%s"' % it["_leaf"]) in o["_src"]],
                       key=lambda x: x["studioPath"])
        b += (["- [[%s]] — `%s` (%s)" % (u["_note"], u["studioPath"], u["className"]) for u in users]
              or ["_Ingen scripts i spejlet nævner navnet direkte._"])
        b += ["", "## Placering", "", "- **Studio:** `%s`" % it["studioPath"],
              "- **Repo:** `%s`" % it["file"], ""]
        notes[it["_path"]] = "\n".join(fm + b)
        return

    hdr = SUMMARIES.get(it["studioPath"]) or header_comment(it["_src"])
    b += [callout(hdr), ""]
    b += ["## Placering", "",
          "- **Studio:** `%s`" % it["studioPath"],
          "- **Repo:** `%s`" % it["file"],
          "- **Omfang:** %s linjer · %s B · sha256 `%s`" % (dk(it["_lines"]), dk(it["bytes"]), it["sha256"][:16]),
          ""]
    b += ["## Afhængigheder", ""]
    any_rel = False
    for cls, label in (("ModuleScript", "Moduler"), ("RemoteEvent", "Remotes"),
                       ("Script", "Server-scripts"), ("LocalScript", "Klient-scripts")):
        if refs.get(cls):
            any_rel = True
            b += ["**%s:** %s" % (label, ", ".join("[[%s]]" % n for n in sorted(refs[cls]))), ""]
    if services:
        any_rel = True
        b += ["**Services:** %s" % ", ".join("`%s`" % s for s in services), ""]
    if attrs:
        any_rel = True
        b += ["**Attributter:** %s" % ", ".join("`%s`" % a for a in attrs[:40]), ""]
    if not any_rel:
        b += ["_Ingen navngivne referencer fundet i kilden._", ""]
    b += ["> [!tip] Hvem bruger dette script?",
          "> Se **Backlinks** i sidepanelet — Obsidian holder den liste ved lige selv.", "",
          "## Kildekode", "", fence(it["_src"], "lua"), ""]
    notes[it["_path"]] = "\n".join(fm + b)


for it in items:
    script_note(it)


# ------------------------------------------- 2. mappe-oversigter (entydige)

# Folder overviews are NOT built here.
#
# fix_folders.py owns them: it covers the intermediate folders this script
# never sees (StarterPlayer, Workspace, ServerStorage hold no scripts directly),
# names them uniquely, and prunes its own stale ones. Generating a second,
# worse set here only made the two scripts delete and rebuild each other's work
# on every run. Run fix_folders.py --apply after this script.

# ------------------------------------------------------- 3. dokumentimport

DOC_MAP = [
    ("README.md", "README — fuld projektreference", "Den store referencemanual for hele spillet: systemer, tal, testing- vs produktionsværdier."),
    ("CLAUDE.md", "CLAUDE — arbejdsregler for repoet", "Husreglerne. Hvordan repoet spejler Studio, hvordan sync fungerer, hvad der ikke må røres."),
    ("HANDOFF-LEVEL2.md", "HANDOFF Level 2", "Level 2-specifik overlevering: generator-tal, exit-hallen, loading-dækket."),
    ("ROBLOX_GAME_DESCRIPTION.md", "Roblox-spilbeskrivelse", "Teksten der står på spillets Roblox-side."),
    ("HANDOVER-2026-09-03.md", "Overlevering 2026-09-03",
     "Hvor projektet står, de tre åbne Trello-kort med fil og linje, og de faldgruber der allerede har kostet tid."),
    ("docs/AUDIT-2026-09-03.md", "Verificeret audit 2026-09-03",
     "36 fejl der overlevede adversariel gennemgang. Hver bærer sin afstemning: 0/3 modbevist betyder at tre uafhængige anmeldere prøvede at aflive den og ikke kunne."),
    ("docs/LEVEL3_PATHFINDING_CLAUDE_PROMPT.md", "Level 3 pathfinding — prompt", "Opgavebeskrivelsen for Level 3's pathfinding."),
    ("docs/LEVEL3_PATHFINDING_CLAUDE_CORRECTIONS.md", "Level 3 pathfinding — rettelser", "Rettelser og efterspil til pathfinding-arbejdet."),
    ("docs/ZYNTRA_MONETIZATION_SETUP.md", "Zyntra monetisering — opsætning", "Hele opsætningen af Zyntra-butikken og passes."),
]

# Repo-relative links do not resolve inside the vault. They are rewritten HERE,
# at import time -- a fix applied to the generated note afterwards is silently
# undone the next time this script runs.
DOC_LINK_FIXES = [
    ("![Zyntra monetization icon preview](../assets/monetization/zyntra-icon-preview-sheet.png)",
     "![[%s/media/monetization/zyntra-icon-preview-sheet.png|520]]" % P_ASSETS),
    ("[Level 2 Round Adapter.ModuleScript.lua](ServerScriptService/Level%202%20Systems/"
     "Level%202%20Round%20Adapter.ModuleScript.lua)",
     "[[Level 2 Round Adapter]]"),
]

for src_rel, title, blurb in DOC_MAP:
    p = REPO / src_rel
    if not p.exists():
        continue
    raw = read_text(p)
    for broken, fixed in DOC_LINK_FIXES:
        raw = raw.replace(broken, fixed)
    fm = ["---", "type: dokument", "kilde: %s" % q(src_rel),
          "linjer: %d" % (raw.count("\n") + 1), "importeret: %s" % TODAY,
          "tags:", "  - dokument", "---", ""]
    head = ["> [!quote] Importeret fra repoet",
            "> Kilde: `%s` · %s linjer · hentet %s." % (src_rel, dk(raw.count("\n") + 1), TODAY),
            "> %s" % blurb,
            "> **Redigér originalen i repoet** — denne note er en kopi.", ""]
    notes["%s/%s.md" % (P_DOCS, safe(title))] = "\n".join(fm + head) + "\n" + raw

notes["%s/Projekt (oversigt).md" % P_DOCS] = "\n".join(
    ["---", "type: oversigt", "tags:", "  - oversigt", "---", "",
     "# Projektdokumenter", "",
     "Alle markdown-dokumenter fra repoet, importeret ordret %s." % TODAY, "",
     "| Note | Kilde i repoet |", "| --- | --- |"] +
    ["| [[%s]] | `%s` |" % (safe(t), s) for s, t, _ in DOC_MAP if (REPO / s).exists()] + [""])


# ------------------------------------------------------------ 4. værktøjer

TOOL_EXT = {".py": "python", ".luau": "lua", ".sh": "bash", ".cmd": "bat", ".js": "javascript"}
tool_files = sorted([p for p in (REPO / "tools").rglob("*")
                     if p.is_file() and p.suffix in TOOL_EXT and "__pycache__" not in p.parts],
                    key=lambda p: p.as_posix())

for p in tool_files:
    rel = p.relative_to(REPO).as_posix()
    src = read_text(p)
    lang = TOOL_EXT[p.suffix]
    hdr = py_header(src) if p.suffix == ".py" else header_comment(src, "--" if p.suffix == ".luau" else "#")
    lines = src.count("\n") + 1
    sub = "tests" if "tests" in p.parts else ""
    fm = ["---", "type: værktøj", "sprog: %s" % lang, "repo_fil: %s" % q(rel),
          "linjer: %d" % lines, "bytes: %d" % p.stat().st_size, "spejlet: %s" % TODAY,
          "tags:", "  - vaerktoej", "  - vaerktoej/" + slug(lang)] + \
         (["  - vaerktoej/test"] if sub else []) + ["---", ""]
    b = ["# %s" % p.name, "", callout(hdr, "abstract", "Hvad værktøjet gør"), "",
         "## Placering", "", "- **Repo:** `%s`" % rel,
         "- **Omfang:** %s linjer · %s" % (dk(lines), human(p.stat().st_size)), "",
         "## Kildekode", "", fence(src, lang), ""]
    notes["%s/%s%s.md" % (P_TOOLS, (sub + "/") if sub else "", safe(p.name))] = "\n".join(fm + b)

_tool_rows = []
for p in tool_files:
    rel = p.relative_to(REPO).as_posix()
    hdr = py_header(read_text(p)) if p.suffix == ".py" else header_comment(read_text(p), "#")
    one = next((h for h in hdr if h.strip()), "")
    _tool_rows.append("| [[%s]] | `%s` | %s |" % (safe(p.name), rel, one[:110].replace("|", "\\|")))

notes["%s/Værktøjer (oversigt).md" % P_TOOLS] = "\n".join(
    ["---", "type: oversigt", "tags:", "  - oversigt", "  - vaerktoej", "---", "",
     "# Værktøjer", "",
     "Python- og Luau-værktøjerne i `tools/`: sync mellem Studio og repoet, playtests,",
     "asset-publicering og Blender-eksport. Fuld kildekode i hver note.", "",
     "> [!warning] Sync-rækkefølgen betyder noget",
     "> `pull_source_from_studio.py` må **aldrig** køres mens der ligger pending pushes —",
     "> den ville overskrive nyere repo-filer med Studios ældre kilde. Se [[CLAUDE — arbejdsregler for repoet]].",
     "", "| Værktøj | Sti | Hvad det gør |", "| --- | --- | --- |"] + _tool_rows + [""])


# --------------------------------------------------------------- 5. assets

MEDIA_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".mp3", ".wav", ".ogg"}
MEDIA_MAX = 2_600_000
MEDIA_SRC = [("assets/banners", "banners"), ("assets/previews", "previews"),
             ("assets/marketing", "marketing"), ("assets/monetization", "monetization"),
             ("assets/level2", "level2"), ("assets/sounds", "sounds"), ("artifacts", "artifacts")]

media_by_group = defaultdict(list)
for src_dir, group in MEDIA_SRC:
    base = REPO / src_dir
    if not base.exists():
        continue
    for p in sorted(base.rglob("*")):
        if not p.is_file() or p.suffix.lower() not in MEDIA_EXT:
            continue
        if p.stat().st_size > MEDIA_MAX:
            continue
        rel = p.relative_to(base).as_posix()
        dest = "%s/media/%s/%s" % (P_ASSETS, group, rel)
        media.append((p, dest))
        media_by_group[group].append((p, dest, rel))

GROUP_TITLE = {"banners": "Bannere", "previews": "Previews", "marketing": "Marketing",
               "monetization": "Monetisering", "level2": "Level 2-assets",
               "sounds": "Lyd", "artifacts": "Artifacts (playtest-billeder)"}
GROUP_BLURB = {
    "banners": "Bannere til Roblox-siden og kampagner.",
    "previews": "Preview-renders fra Studio og fra playtests.",
    "marketing": "Kampagnemateriale: thumbnails, annoncer og de prompts de blev genereret ud fra.",
    "monetization": "Ikoner og kildebilleder til Zyntra-butikkens passes og produkter.",
    "level2": "Referencebilleder til Level 2's poolrooms.",
    "sounds": "Lydfilerne spillet bruger. Obsidian afspiller dem direkte i noten.",
    "artifacts": "Skærmbilleder fanget under playtests af værktøjerne i `tools/`.",
}

for group, entries in sorted(media_by_group.items()):
    total = sum(p.stat().st_size for p, _, _ in entries)
    fm = ["---", "type: assets", "gruppe: %s" % group, "filer: %d" % len(entries),
          "tags:", "  - assets", "  - assets/" + slug(group), "---", ""]
    b = ["# %s" % GROUP_TITLE[group], "", GROUP_BLURB[group], "",
         "%d filer · %s · kopieret ind fra `%s`." % (
             len(entries), human(total),
             next(s for s, g in MEDIA_SRC if g == group)), ""]
    by_sub = defaultdict(list)
    for p, dest, rel in entries:
        by_sub["/".join(rel.split("/")[:-1])].append((p, dest, rel))
    for sub in sorted(by_sub):
        if sub:
            b += ["## %s" % sub, ""]
            readme = REPO / next(s for s, g in MEDIA_SRC if g == group) / sub / "README.md"
            if readme.exists():
                txt = read_text(readme).strip()
                b += ["> [!quote] `%s/README.md`" % sub,
                      "\n".join("> " + l if l else ">" for l in txt.split("\n")), ""]
        for p, dest, rel in by_sub[sub]:
            if p.suffix.lower() in (".mp3", ".wav", ".ogg"):
                b += ["**%s** · %s" % (p.name, human(p.stat().st_size)), "", "![[%s]]" % dest, ""]
            else:
                b += ["**%s** · %s" % (p.name, human(p.stat().st_size)), "", "![[%s|420]]" % dest, ""]
    notes["%s/%s.md" % (P_ASSETS, safe(GROUP_TITLE[group]))] = "\n".join(fm + b)

# fuld inventarliste over ALT under assets/ — også det der ikke kopieres ind
inv_rows = []
for d in sorted((REPO / "assets").iterdir()):
    if d.is_dir():
        files = [f for f in d.rglob("*") if f.is_file()]
        size = sum(f.stat().st_size for f in files)
        kinds = Counter(f.suffix.lower() for f in files).most_common(4)
        inv_rows.append("| `assets/%s` | %d | %s | %s |" % (
            d.name, len(files), human(size), ", ".join("%s×%d" % (k or "—", v) for k, v in kinds)))

notes["%s/Assets (oversigt).md" % P_ASSETS] = "\n".join(
    ["---", "type: oversigt", "tags:", "  - oversigt", "  - assets", "---", "",
     "# Assets", "",
     "Repoets `assets/` fylder **481 MB**. Billeder og lyd under 2,6 MB er kopieret ind i",
     "vaulten under `%s/media/` så de kan ses og afspilles direkte i Obsidian." % P_ASSETS,
     "Tunge kildefiler — `.blend`, `.fbx`, texture-pakker og source-packs — er **ikke** kopieret;",
     "de bliver liggende i repoet, hvor de hører hjemme.", "",
     "## Kopieret ind i vaulten", "",
     "| Note | Filer |", "| --- | ---: |"] +
    ["| [[%s]] | %d |" % (GROUP_TITLE[g], len(e)) for g, e in sorted(media_by_group.items())] +
    ["", "## Alt i `assets/` (også det der ikke er kopieret)", "",
     "| Mappe | Filer | Størrelse | Typer |", "| --- | ---: | ---: | --- |"] + inv_rows + [""])


# ----------------------------------------------------------------- 6. meta

c = manifest["counts"]
notes["%s/Studio-sync — status.md" % P_META] = "\n".join(
    ["---", "type: meta", "tags:", "  - meta", "---", "",
     "# Studio-sync — status", "",
     "> [!success] Ingen pending pushes",
     "> Alle **%d** poster i `studio-sync-manifest.json` står som `synced`." % len(items),
     "> Repoet og Studio er enige, byte for byte.", "",
     "## Studio-stedet", "",
     "- **Navn:** %s" % manifest["studio"]["name"],
     "- **Place-id:** `%s`" % manifest["studio"]["id"],
     "- **Manifest-version:** %s" % manifest["formatVersion"], "",
     "## Tal", "",
     "| | Antal |", "| --- | ---: |",
     "| Scripts | %d |" % c["scripts"],
     "| RemoteEvents | %d |" % c["remoteEvents"],
     "| I alt | %d |" % c["total"],
     "| Med ekstra afsluttende linjeskift i Studio | %d |" % c.get("studioTrailingNewline", 0),
     "| Linjer Lua i alt | %s |" % dk(sum(i["_lines"] for i in items)), "",
     "## Statusværdier i manifestet", "",
     "- `synced` — repo og Studio er enige.",
     "- `pending-studio-push` — repo-kopien er **nyere** og venter på at blive skubbet til Studio.",
     "- `studio-push-conflict` — et push fandt at Studio var drevet fra hinanden; kræver en beslutning.", "",
     "## Sådan læses en pipeline", "",
     "```", manifest["source"], "```", "",
     "## Kontrakt for afsluttende linjeskift", "",
     "```", manifest["finalNewlineContract"], "```", "",
     "## Spejlede filer der ikke findes i Studio", ""] +
    ["- `%s`" % f for f in manifest["extraMirroredFilesNotInStudio"]] +
    ["", "Se [[Værktøjer (oversigt)]] for kommandoerne der vedligeholder det her.", ""])

notes["%s/Sådan er vaulten bygget.md" % P_META] = "\n".join(
    ["---", "type: meta", "tags:", "  - meta", "---", "",
     "# Sådan er vaulten bygget", "",
     "Vaulten blev genereret %s ud fra repoet i `G:\\Roblox\\MongoTV` og skrevet ind" % TODAY,
     "gennem MCP-forbindelsen til Obsidian (`mcp-tools-istefox` på port 27200).", "",
     "## Struktur", "",
     "| Mappe | Indhold |", "| --- | --- |",
     "| `01 Projekt` | Repoets markdown-dokumenter, importeret ordret. |",
     "| `02 Systemer` | Håndskrevne oversigter der binder spillets systemer sammen. |",
     "| `03 Kode` | 1:1-spejl af Studio-hierarkiet. Én note pr. script, med fuld kildekode. |",
     "| `04 Arkiv` | `ServerStorage`-backupmapperne, holdt adskilt fra den levende kode. |",
     "| `05 Værktøjer` | Python/Luau-værktøjerne fra `tools/`, med fuld kildekode. |",
     "| `06 Assets` | Billeder og lyd under 2,6 MB, kopieret ind så de kan ses i Obsidian. |",
     "| `99 Meta` | Denne note og sync-statussen. Generatoren selv bor i repoet. |", "",
     "## Navngivning", "",
     "Notenavne er scriptets navn i Studio. Hvor to scripts deler navn, får noten et",
     "suffiks: `(mappe)` for to levende scripts, `— <backupmappe>` for arkivkopier.",
     "Det er derfor `[[GameManager]]` altid peger på den levende, og",
     "`[[GameManager — LobbyBackup_20260731]]` på arkivkopien.", "",
     "## Hvad der ikke er med", "",
     "- `.studio-push-backups/` — 85 tidsstemplede pre-push-kopier. Ren støj.",
     "- `_local/` — lokalt lager for downloads, allerede git-ignoreret.",
     "- Tunge assets: `.blend`, `.fbx`, texture-pakker, source-packs (i alt ~375 MB).",
     "- `studio-sync.rbxl` — binært Studio-sted.", "",
     "> [!danger] Vaulten er en læsekopi",
     "> Kildekoden i `03 Kode` er kopieret fra repoet, som selv er et spejl af Studio.",
     "> Redigér **aldrig** kode her — ændringer forsvinder ved næste generering, og de",
     "> når aldrig frem til spillet. Kæden er: Studio → repo → vault, én vej.", "",
     "## Genopbygning", "",
     "Generatoren bor i repoet under `tools/vault/`, ikke i vaulten. Den lå tidligere",
     "her i `99 Meta/generator/`, hvor den var git-ignoreret sammen med resten af",
     "vaulten — 74 KB kode med kun én kopi, som ville forsvinde hvis vaulten blev",
     "slettet. Nu er vaulten rent genereret og kan slettes uden tab.", "",
     "```bash",
     "python tools/vault/build_vault.py    # noter + assets",
     "python tools/vault/fix_folders.py    # mappeoversigter",
     "```", "",
     "Noterne overskrives, og noter hvis kilde er forsvundet fra repoet slettes.",
     "Obsidian skal køre, med MCP-serveren aktiv på port 27200.", ""])


# ------------------------------------------------------------ 7. dashboard

live_items = [i for i in items if i["_kind"] == "live"]
notes["Start her.md"] = "\n".join(
    ["---", "type: forside", "tags:", "  - forside", "---", "",
     "# BACKROOMS: STAY QUIET", "",
     "> [!abstract] Co-op horror på Roblox",
     "> Tre niveauer, en entitet der jager, og en regel: vær stille.",
     "> Denne vault er hele projektet — kode, dokumenter, værktøjer og assets — samlet ét sted.", "",
     "## Start her", "",
     "- [[Projekt (oversigt)]] — repoets dokumenter, importeret ordret",
     "- [[Systemer (oversigt)]] — hvordan spillet hænger sammen",
     "- [[Kode (oversigt)]] — %d levende scripts fra Studio" % len(live_items),
     "- [[Værktøjer (oversigt)]] — sync, playtests og asset-pipeline",
     "- [[Assets (oversigt)]] — billeder, lyd og marketing",
     "- [[Arkiv (oversigt)]] — ServerStorage-backups",
     "- [[Studio-sync — status]] — står repo og Studio ens?", "",
     "## Niveauerne", "",
     "- [[Level 1 — Elevator, labyrint og entiteten]]",
     "- [[Level 2 — Poolrooms]]",
     "- [[Level 3 — Mall]]", "",
     "## Tal", "",
     "| | |", "| --- | ---: |",
     "| Levende scripts i Studio | %d |" % len([i for i in live_items if i["className"] != "RemoteEvent"]),
     "| RemoteEvents | %d |" % len([i for i in live_items if i["className"] == "RemoteEvent"]),
     "| Linjer Lua (levende) | %s |" % dk(sum(i["_lines"] for i in live_items)),
     "| Arkiverede scripts | %d |" % len([i for i in items if i["_kind"] == "arkiv"]),
     "| Værktøjer i `tools/` | %d |" % len(tool_files),
     "| Projektdokumenter | %d |" % len([1 for s, _, _ in DOC_MAP if (REPO / s).exists()]),
     "", "## De store scripts", "",
     "| Script | Linjer |", "| --- | ---: |"] +
    ["| [[%s]] | %s |" % (i["_note"], dk(i["_lines"]))
     for i in sorted(live_items, key=lambda x: -x["_lines"])[:12]] +
    ["", "---", "", "Vaulten er genereret %s — se [[Sådan er vaulten bygget]]." % TODAY, ""])


# ------------------------------------------------------------------ push

def copy_media():
    done = 0
    for src, dest in media:
        target = VAULT / dest
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.stat().st_size != src.stat().st_size:
            shutil.copy2(src, target)
        done += 1
    return done


def sweep_stale():
    """Delete generated notes whose source is gone.

    These four trees are generated in full from the manifest, tools/ and DOC_MAP,
    so anything under them that this run did not produce no longer has a source:
    a script retired out of the live tree, an archive folder moved under
    ServerStorage.Archive, a doc deleted from the repo. Without this the vault
    keeps describing things that stopped existing -- the retired Slidemouth notes
    had to be removed by hand once already. 02 Systemer is hand-written and
    06 Assets holds copied media, so neither is swept.
    """
    roots = (P_DOCS + "/", P_CODE + "/", P_ARCH + "/", P_TOOLS + "/")
    existing = json.loads(mcp("list_vault_files", {"limit": 5000}))["files"]
    # "(oversigt)" notes belong to fix_folders.py, which builds them for every
    # folder including the intermediate ones this script never sees and prunes
    # its own stale ones. Sweeping them here just made the two scripts delete and
    # rebuild each other's work on every run.
    stale = [f for f in existing
             if f.startswith(roots) and f.endswith(".md")
             and not f.endswith(" (oversigt).md") and f not in notes]
    for path in stale:
        mcp("delete_vault_file", {"path": path})
    return stale


def push():
    ok, fail = 0, []
    for i, (path, content) in enumerate(sorted(notes.items()), 1):
        try:
            mcp("create_vault_file", {"path": path, "content": content})
            ok += 1
        except Exception as e:                       # noqa: BLE001
            fail.append((path, str(e)[:200]))
        if i % 25 == 0:
            print("   ... %d/%d" % (i, len(notes)), flush=True)
    return ok, fail


if __name__ == "__main__":
    tot = sum(len(v.encode("utf-8")) for v in notes.values())
    print("noter:        %d  (%s)" % (len(notes), human(tot)))
    print("mediefiler:   %d  (%s)" % (len(media), human(sum(p.stat().st_size for p, _ in media))))
    print("live scripts: %d" % len(live_items))
    print("arkiv:        %d" % len([i for i in items if i["_kind"] == "arkiv"]))
    names = Counter(p.rsplit("/", 1)[-1][:-3] for p in notes)
    dup = {k: v for k, v in names.items() if v > 1}
    print("kollisioner:  %s" % (dup or "ingen"))
    if "--dry" in sys.argv:
        sys.exit(0)
    print("\nkopierer medier ...", flush=True)
    print("   %d filer" % copy_media())
    print("\nskriver noter gennem MCP ...", flush=True)
    ok, fail = push()
    print("\nskrevet: %d/%d" % (ok, len(notes)))
    for p, e in fail:
        print("  FEJL", p, "->", e)
    stale = sweep_stale()
    print("\nforaeldede noter slettet: %d" % len(stale))
    for p in stale:
        print("   -", p)
