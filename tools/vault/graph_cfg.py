# -*- coding: utf-8 -*-
"""Skriv Obsidian-grafkonfigurationen for Backrooms Stay Quiet.

Farven baerer information. De tre niveauer er spillets faktiske struktur, saa
grafen viser dem som tre adskilte omraader i stedet for én udifferentieret
kodeblob -- "03 Kode" alene er 122 af 224 noter.

Raekkefoelgen er betydende: Obsidian bruger den FOERSTE gruppe der matcher.
"""
import io
import json


def rgb(h):
    return int(h.lstrip("#"), 16)


GROUPS = [
    # 1. hub
    ('file:"Start her"', "#FFFFFF"),

    # 2. Pensioneret kode foerst. Arkivnoterne hedder ogsaa "Level 2 ...", og
    #    uden denne raekkefoelge ville de laane den levende kodes niveaufarve.
    ('path:"04 Arkiv" OR path:"CodexBackup" OR path:"Project Mirror"', "#3A3F4A"),

    # 3. Alt uden for koden, saa et dokument OM Zyntra ikke laeses som Zyntra-kode.
    ('path:"02 Systemer"', "#8FB8D8"),
    ('path:"01 Projekt"', "#8E93A8"),
    ('path:"05 Værktøjer"', "#B07A4A"),
    ('path:"06 Assets"', "#6E7BC8"),
    ('path:"99 Meta"', "#4E545F"),

    # 4. De tre niveauer. Level 1's klientscripts mangler praefiks
    #    (PuzzleUI, EntityShakeController, JumpscareUI), saa de navngives.
    ('path:"Level 1 Systems" OR file:"Level 1" OR file:"PuzzleUI" '
     'OR file:"EntityShakeController" OR file:"JumpscareUI"', "#E0A03C"),
    ('path:"Level 2 Systems" OR path:"Level 2 Pool Foam Remotes" '
     'OR file:"Level 2" OR file:"Level2"', "#3FB3C7"),
    ('path:"Level 3 Systems" OR path:"Level 3 Remotes" '
     'OR file:"Level 3" OR file:"Level3"', "#C264A8"),

    # 5. Resten af koden ER det delte lag: RemoteEvents, UIDevice, FlashlightSync,
    #    DevCheats, lyd, spectate, GameManager, lobbyen. 38 noter faldt tidligere
    #    uden for hver gruppe og blev tegnet i Obsidians standardgraa.
    ('path:"03 Kode"', "#7FA86B"),
]

cfg = {
    "collapse-filter": True,
    "search": "",
    "showTags": False,
    "showAttachments": False,
    "hideUnresolved": True,
    "showOrphans": False,
    "collapse-color-groups": False,
    "colorGroups": [{"query": q, "color": {"a": 1, "rgb": rgb(c)}} for q, c in GROUPS],
    "collapse-display": True,
    "showArrow": True,
    # Negativ vaerdi = navnene bliver laengere synlige naar man zoomer ud.
    "textFadeMultiplier": -0.8,
    "nodeSizeMultiplier": 1.25,
    "lineSizeMultiplier": 0.55,
    "collapse-forces": True,
    "centerStrength": 0.34,
    "repelStrength": 11.5,
    "linkStrength": 0.62,
    "linkDistance": 190,
    # Obsidian havde gemt 0.163 -- helt udzoomet, hvilket er stoerstedelen af
    # grunden til at grafen laeste som stoej.
    "scale": 0.62,
    "close": False,
}

path = r"G:\Roblox\MongoTV\Backrooms Stay Quiet\.obsidian\graph.json"
io.open(path, "w", encoding="utf-8", newline="\n").write(
    json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
print("skrevet:", path)
print("farvegrupper:", len(GROUPS))
