# Vault-generatoren

Bygger den Obsidian-vault der ligger i `Backrooms Stay Quiet/` ud fra dette repo.

Vaulten er **git-ignoreret med vilje** — den er en genereret læsekopi og kan
slettes og bygges igen. Generatoren er ikke, og det er hele pointen med denne
mappe: indtil 2026-09-03 lå den inde i vaulten under `99 Meta/generator/`, hvor
den var ignoreret sammen med resten. 74 KB kode med præcis én kopi, som ville
være forsvundet hvis nogen havde slettet vaulten.

## Kørsel

Obsidian skal køre med MCP-serveren aktiv på port 27200.

```bash
python tools/vault/build_vault.py     # noter + assets
python tools/vault/fix_folders.py --apply   # mappeoversigter + fjern tomme mapper
python tools/vault/graph_cfg.py       # grafvisningens farver og fysik
```

`fix_folders.py` uden `--apply` er en tørkørsel: den viser hvad den ville gøre
og skriver intet. Det er let at overse — kør den med flaget.

Rækkefølgen betyder noget. `build_vault.py` skriver noterne og sletter dem hvis
kilde er væk; `fix_folders.py` bygger mappeoversigterne oven på resultatet og
rydder de mapper op som sletningen efterlod tomme.

## Hvad de gør

| Script | Ansvar |
| --- | --- |
| `build_vault.py` | Én note pr. script fra manifestet, plus dokumenter, værktøjer og assets. Ejer `sweep_stale()`. |
| `build_systems.py` | De håndskrevne systemnoter i `02 Systemer`. |
| `fix_folders.py` | Mappeoversigter for hver mappe, også de mellemliggende. Ejer `prune_empty_dirs()`. |
| `graph_cfg.py` | `.obsidian/graph.json` — farvegrupper efter niveau, og grafens fysik. |

## Kæden er én vej

Studio → repo → vault. Rediger aldrig kode i vaulten: den overskrives ved næste
kørsel, og ændringen når aldrig frem til spillet.
