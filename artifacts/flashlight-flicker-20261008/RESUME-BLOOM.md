# Genoptag Bloom-opgaven

**Stage B er nu gennemført 2026-10-09 kl.00:29 UTC. Bloom er installeret, Studio står i Edit, og låsen er frigivet. Se QA-REPORT.md og B-release-receipt.json.** Resten af dette dokument er den historiske genoptagelsesplan fra offline-forberedelsen; den skal ikke køres igen. Den faktisk installerede plan bruger den live Level6Playground-owner og ligger i `bloom-stageB-reviewed/`. De midlertidige filer fra afsluttet Stage B er fjernet og arkiveret i `B-temporary-source-archive.json/md`.

Hjælper: `_local/flashlight-flicker/apply_bloom.py`; afhænger af `qa.py` og `capture_frames.py`. De 40 midlertidige filer er arkiveret i `temporary-source-archive.md` og byte-præcist i `temporary-source-archive.json`. `_local/flashlight-flicker/` er fjernet. Genopret dem offline med følgende kommando fra projektroden, og kontrollér source-SHA i validation-receipts før brug:

```powershell
@'
from pathlib import Path
import base64, hashlib, json
root=Path('G:/Roblox/MongoTV').resolve()
scope=(root/'_local/flashlight-flicker').resolve()
archive=json.loads((root/'artifacts/flashlight-flicker-20261008/temporary-source-archive.json').read_text(encoding='utf-8'))
ready=[]
for entry in archive['files']:
    target=(root/entry['path']).resolve()
    assert target.is_relative_to(scope) and not target.exists()
    data=base64.b64decode(entry['base64'],validate=True)
    assert len(data)==entry['bytes'] and hashlib.sha256(data).hexdigest()==entry['sha256']
    ready.append((target,data))
assert len({p for p,d in ready})==len(ready)
for target,data in ready:
    target.parent.mkdir(parents=True,exist_ok=True)
    with target.open('xb') as f: f.write(data)
print('Restored',len(ready),'verified temporary files; no Studio access')
'@ | python -B -
```

Behold Monos køorden, som ejeren udtrykkeligt valgte. Først ved faktisk tildeling og holder=null må `take_lock.py` tage slotten. Hjælperen sætter 25 minutters ETA. Ingen tildeling må antages ud fra, hvor længe Studio har været ledigt.

Efter faktisk bevilling og ejerskab af Studio-låsen: kør først roots friske inventory. Native targets/værdier er endnu ukendte. Et eventuelt `bloom-native-reviewed.json` skal være en array af eksakte `segments`, `studioPath`, `className: "BloomEffect"`, alle fire faktisk observerede `before`-properties (`Enabled`, `Intensity`, `Size`, `Threshold`) og den aftalte `after.Intensity`. Der gættes ingen defaults; også disabled eksisterende effekter kan kræve vurdering som tween-startværdier.

Prepare uden native writes-plan:

```powershell
python -B _local/flashlight-flicker/apply_bloom.py prepare --patch artifacts/flashlight-flicker-20261008/bloom-scoped-patch.json --label bloom-stageB-reviewed
```

Eller prepare med den særskilt gennemgåede native plan:

```powershell
python -B _local/flashlight-flicker/apply_bloom.py prepare --patch artifacts/flashlight-flicker-20261008/bloom-scoped-patch.json --native-plan artifacts/flashlight-flicker-20261008/bloom-native-reviewed.json --label bloom-stageB-reviewed
```

Disse er alternativer: label-folderen må ikke eksistere. Prepare gemmer stabile rå Source/editor-baselines, repo-bytes, native observationer, candidates og diffs i artifacts; kompilerer Studio- og repo-candidates med `-O0`; skriver intet til Studio eller runtime-mirror. Gennemgå `bloom-stageB-reviewed/plan.json`, diffs, parity/WIP og native before/after før næste trin:

```powershell
python -B _local/flashlight-flicker/apply_bloom.py apply --plan artifacts/flashlight-flicker-20261008/bloom-stageB-reviewed/plan.json
```

Apply kræver uændret repo og scoped manifest siden prepare, frisk identisk Studio-baseline og Source/editor/class/Enabled/rawhash-CAS inde i callback. Alle native before-properties preflightes før writes og igen efter eventuelt yieldende source-updates. Native efter-intensitet accepterer højst absolut `1e-6` afvigelse for engine-landing; faktisk Wanted/Observed gemmes i receipt. Øvrige native properties er exact.

Installeret Source verificeres igen fra Studio. Repo kopieres kun fra canonical installed Source, når repoBefore-bytefilen var identisk med StudioBefore. Ellers anvendes præcis egne hunks på repoBefore, så øvrig WIP og CRLF bevares. Manifest er `synced` alene ved fuld LF-canonical parity; ellers `studio-push-conflict` med begge hashes. Slutmerge kræver præcis ét scoped manifest-item pr. fil, bevarer andres seneste items og gør en rå-byte-check i `r+b` før write.

Flere Studio-writes/repo-filer er ikke én transaktion. Delvis fejl er synlig i `apply-receipt.json`; ingen automatisk rollback, bred pull eller blind canonical overwrite. En forsøgt plan genbruges ikke. Ved fejl: læs receipt og snapshots, lav frisk plan efter review. Ingen publicering eller commit.

Før fulde high-quality frame-captures skal transport-smoken fra `transport-note.md` bestå under bevillingen. Både transportens Success/CleanupVerified og selve ProbeComplete skal være sande. Efter arbejdet fjernes midlertidige probe-attributter/callbacks, Studio stoppes i Edit, device resettes, helper/probekilder arkiveres og midlertidige filer fjernes af root; derefter frigives låsen.

Offline evidence: `installer-offline-validation.json` har 17 Python-checks og 9 Luau-CAS-cases, inklusive class/Enabled/Source/editor/current-drift, native samlet preflight, float32-lignende landing, repo-WIP/anker-konflikter, manglende/duplikerede scoped manifest-items og rå-byte-CAS uden overwrite. `-O0` bestod. Dette er ikke Studio-/Play-bevis. Første cirka `.48s` L3/L6 tween er fortsat et åbent auditpunkt; deres faktiske initværdier er ukendte.
