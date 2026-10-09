# -*- coding: utf-8 -*-
"""Genopbygger alle mappe-oversigter, ogsaa for mellemliggende mapper uden
scripts direkte i sig (StarterPlayer, Workspace, ServerStorage). Rydder
forældede oversigtsnoter op bagefter."""
import json
import sys
import urllib.request
from collections import Counter, defaultdict

import build_vault as b

APPLY = "--apply" in sys.argv

def prune_empty_dirs():
    """Fjern mapper der ikke rummer en fil i nogen dybde.

    Sletning af en note gennem MCP efterlader dens mappe, saa pensionering af en
    encounter efterlod et skelet: da Pool Slide-noterne gik, blev fire af dens
    backupmapper staaende som tomme skaller, og aeldre genereringer havde
    efterladt et helt dublet-trae under "04 Arkiv/ServerStorage/" plus et
    "03 Kode/ServerStorage/Archive/" som classify() ikke laengere fylder.
    Obsidian viser hver eneste af dem i filtraeet.

    Filsystem-niveau med vilje: MCP-fladen sletter noter, ikke mapper.
    Nedefra og op, saa en foraelder der toemmes af sine boern ryger i samme pas.
    """
    import os
    root = str(b.VAULT)
    removed = []
    for cur, _subdirs, _files in os.walk(root, topdown=False):
        rel = os.path.relpath(cur, root).replace(os.sep, "/")
        if rel == "." or rel.startswith(".obsidian"):
            continue
        try:
            if not any(True for _ in os.scandir(cur)):
                os.rmdir(cur)
                removed.append(rel)
        except OSError:
            pass
    return sorted(removed)



def dirs_for(kind):
    out = set()
    for it in b.items:
        if it["_kind"] != kind:
            continue
        parts = it["_dir"].split("/")
        for i in range(2, len(parts) + 1):
            out.add("/".join(parts[:i]))
    return sorted(out)


def label_for(d, kind):
    parts = d.split("/")
    leaf = parts[-1]
    if kind == "arkiv" and len(parts) > 3 and parts[2] != leaf:
        return "%s — %s" % (leaf, parts[2])
    return leaf


def build(kind):
    dirs = dirs_for(kind)
    labels = {d: label_for(d, kind) for d in dirs}
    seen = Counter(labels.values())
    for d in dirs:
        if seen[labels[d]] > 1:
            labels[d] = "%s (%s)" % (labels[d], d.split("/")[-2])
    direct = defaultdict(list)
    for it in b.items:
        if it["_kind"] == kind:
            direct[it["_dir"]].append(it)

    def subtree(d):
        return [i for i in b.items
                if i["_kind"] == kind and (i["_dir"] == d or i["_dir"].startswith(d + "/"))]

    made = {}
    for d in dirs:
        children = sorted(direct.get(d, []), key=lambda x: (x["className"], x["_leaf"]))
        subs = sorted(o for o in dirs if o.startswith(d + "/") and "/" not in o[len(d) + 1:])
        under = subtree(d)
        studio_path = d.split("/", 1)[1].replace("/", ".")
        fm = ["---", "type: oversigt", "omfatter: %s" % b.q(studio_path),
              "tags:", "  - oversigt", "  - service/" + b.slug(d.split("/")[1]),
              ("  - arkiv" if kind == "arkiv" else "  - zone/kerne"), "---", ""]
        body = ["# %s" % labels[d], "",
                "> [!info] Mappe-oversigt",
                "> Spejler `%s` i Roblox Studio." % studio_path,
                "> %d element%s i alt herunder · %s linjer kode." % (
                    len(under), "" if len(under) == 1 else "er", b.dk(sum(u["_lines"] for u in under))),
                ""]
        if subs:
            body += ["## Undermapper", "", "| Mappe | Elementer | Linjer |", "| --- | ---: | ---: |"]
            for s in subs:
                u = subtree(s)
                body.append("| [[%s]] | %d | %s |" % (
                    labels[s] + " (oversigt)", len(u), b.dk(sum(x["_lines"] for x in u))))
            body.append("")
        if children:
            body += ["## Indhold", "", "| Note | Klasse | Linjer |", "| --- | --- | ---: |"]
            body += ["| [[%s]] | %s | %s |" % (c["_note"], c["className"], b.dk(c["_lines"]))
                     for c in children]
            body.append("")
        if not subs and not children:
            body += ["_Tom mappe._", ""]
        made["%s/%s (oversigt).md" % (d, labels[d])] = "\n".join(fm + body)
    return dirs, labels, made, subtree


def root(kind, root_dir, title, blurb):
    dirs, labels, made, subtree = build(kind)
    tops = sorted(d for d in dirs if d.count("/") == 1)
    allitems = [i for i in b.items if i["_kind"] == kind]
    body = ["---", "type: oversigt", "tags:", "  - oversigt", "---", "",
            "# %s" % title, "", blurb, "", "## Services", "",
            "| Service | Elementer | Linjer |", "| --- | ---: | ---: |"]
    for d in tops:
        u = subtree(d)
        body.append("| [[%s]] | %d | %s |" % (
            labels[d] + " (oversigt)", len(u), b.dk(sum(x["_lines"] for x in u))))
    body += ["", "**I alt:** %d elementer · %s linjer." % (
        len(allitems), b.dk(sum(i["_lines"] for i in allitems))), ""]
    made["%s/%s.md" % (root_dir, title)] = "\n".join(body)
    return made


notes = {}
notes.update(root("live", b.P_CODE, "Kode (oversigt)",
                  "Et 1:1-spejl af de scripts der ligger i Roblox Studio lige nu. Hver note har\n"
                  "scriptets Studio-sti, klasse, linjetal, sha256 fra `studio-sync-manifest.json`,\n"
                  "de moduler og remotes den refererer, og den fulde kildekode nederst.\n\n"
                  "> [!warning] Studio er kilden til sandhed\n"
                  "> Koden her er en **læsekopi**. Redigér i Studio (eller i repoet og push derfra),\n"
                  "> aldrig i vaulten — se [[CLAUDE — arbejdsregler for repoet]]."))
notes.update(root("arkiv", b.P_ARCH, "Arkiv (oversigt)",
                  "`ServerStorage`-backupmapperne. Ifølge `CLAUDE.md` er de **bevidste arkiver** —\n"
                  "de må ikke ryddes op eller auditeres. De ligger her adskilt fra [[Kode (oversigt)]]\n"
                  "så de ikke forurener søgning og graf, men er stadig søgbare."))

if __name__ == "__main__":
    existing = json.loads(b.mcp("list_vault_files", {"limit": 1000}))["files"]
    stale = [f for f in existing
             if f.endswith(" (oversigt).md")
             and (f.startswith(b.P_CODE + "/") or f.startswith(b.P_ARCH + "/"))
             and f not in notes]
    print("nye/opdaterede oversigter: %d" % len(notes))
    print("forældede der slettes:     %d" % len(stale))
    for s in stale:
        print("   -", s)
    if not APPLY:
        sys.exit(0)
    for path, content in sorted(notes.items()):
        b.mcp("create_vault_file", {"path": path, "content": content})
    for s in stale:
        b.mcp("delete_vault_file", {"path": s})
    print("\nskrevet %d, slettet %d" % (len(notes), len(stale)))
    pruned = prune_empty_dirs()
    print("tomme mapper fjernet:      %d" % len(pruned))
    for d in pruned[:15]:
        print("   -", d)
    if len(pruned) > 15:
        print("   ... og %d mere" % (len(pruned) - 15))
