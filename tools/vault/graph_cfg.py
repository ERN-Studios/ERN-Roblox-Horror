# -*- coding: utf-8 -*-
"""Skriv Obsidian-grafkonfigurationen for Backrooms Stay Quiet.

Farven baerer information: de tre niveauer er spillets faktiske struktur, saa
grafen viser dem som tre adskilte omraader i stedet for én udifferentieret
kodeblob (03 Kode alene er 122 af 224 noter).

Raekkefoelgen er betydende -- Obsidian bruger den FOERSTE gruppe der matcher.
Arkivet staar derfor foerst: dets noter hedder ogsaa "Level 2 ...", og uden det
ville pensioneret kode laane den levende kodes farve.
"""
import io
import json


def rgb(h):
    return int(h.lstrip("#"), 16)


GROUPS = [
    # hub
    ('file:"Start her"', "#FFFFFF"),

    # pensioneret kode foerst, saa den ikke laaner en niveaufarve
    ('path:"04 Arkiv" OR path:"CodexBackup" OR path:"Project Mirror"', "#3A3F4A"),

    # de tre niveauer. Level 1's klientscripts mangler praefiks (PuzzleUI,
    # EntityShakeController, JumpscareUI), saa de navngives eksplicit.
    ('path:"Level 1 Systems" OR file:"Level 1" OR file:"PuzzleUI" '
     'OR file:"EntityShakeController" OR file:"JumpscareUI"', "#E0A03C"),
    ('path:"Level 2 Systems" OR path:"Level 2 Pool Foam Remotes" '
     'OR file:"Level 2" OR file:"Level2"', "#3FB3C7"),
    ('path:"Level 3 Systems" OR path:"Level 3 Remotes" '
     'OR file:"Level 3" OR file:"Level3"', "#C264A8"),

    # det der binder niveauerne sammen
    ('file:"GameManager" OR file:"TunnelLobbyBuilder" OR file:"RoundUI" '
     'OR file:"Round Completion" OR file:"NoiseRegistry" OR file:"Zyntra" '
     'OR file:"MasterConfiguration" OR file:"MasterTuning" OR file:"Crouch"', "#7FA86B"),

    # resten af vaulten, daempet
    ('path:"02 Systemer"', "#8FB8D8"),
    ('path:"01 Projekt"', "#8E93A8"),
    ('path:"05 Værktøjer"', "#B07A4A"),
    ('path:"06 Assets"', "#6E7BC8"),
    ('path:"99 Meta"', "#4E545F"),
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
    # negativ = navne bliver laengere synlige naar man zoomer ud
    "textFadeMultiplier": -0.8,
    "nodeSizeMultiplier": 1.25,
    "lineSizeMultiplier": 0.55,
    "collapse-forces": True,
    "centerStrength": 0.34,
    "repelStrength": 11.5,
    "linkStrength": 0.62,
    "linkDistance": 190,
    # var 0.163 -- Obsidian havde gemt en helt udzoomet visning, hvilket er
    # praecis hvorfor grafen laeste som en prikssky.
    "scale": 0.62,
    "close": False,
}

p = r"G:\Roblox\MongoTV\Backrooms Stay Quiet\.obsidian\graph.json"
io.open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
print("skrevet:", p)
print("farvegrupper:", len(GROUPS))
