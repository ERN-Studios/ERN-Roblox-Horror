"""S08 proposals only: archive exact tools, retire legacy entry/defaults privately.

Never installs the proposal or contacts Blender/Studio/network on preparation.
Run level1_retirement_contracts.py separately for the before/after offline port.
"""
from pathlib import Path
import argparse
import ast
import hashlib
import json

ROOT=Path(__file__).resolve().parents[2]
TARGETS=(
 'tools/level1_blender/build.py','tools/level1_blender/import_assets.py',
 'tools/level1_blender/check_assets.py','tools/level1_blender/verify_native.py',
 'tools/level1_blender/publish_textures.py','tools/export_level1_facelift_verified.py',
 'tools/level1_blender/README.md',
)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def once(text,old,new):
    assert text.count(old)==1,repr(old)
    return text.replace(old,new,1)

def propose(path,raw):
    text=raw.decode('utf8')
    nl='\r\n' if '\r\n' in text else '\n'
    if path.endswith('/build.py'):
        tree=ast.parse(text)
        main=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='main')
        assert len([n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='main'])==1
        lines=text.splitlines(keepends=True)
        assert all(isinstance(n,ast.If) for n in tree.body if n.lineno>main.end_lineno)
        text=''.join(lines[:main.lineno-1])+f'if __name__ == "__main__":{nl}    raise SystemExit("Legacy Level1BlenderKit build retired; use build_v2.py or elevator_inset.py")'+nl
        first=ast.parse(text).body[0]
        lines=text.splitlines(keepends=True)
        text='"""Shared Level 1 Blender helpers for V2 and elevator authoring.'+nl+nl+'The standalone legacy Level1BlenderKit build workflow is retired.'+nl+'"""'+nl+''.join(lines[first.end_lineno:])
        before={n.name:ast.dump(n,include_attributes=False) for n in tree.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name!='main'}
        after={n.name:ast.dump(n,include_attributes=False) for n in ast.parse(text).body if isinstance(n,(ast.FunctionDef,ast.ClassDef))}
        assert before==after,'Shared Blender helper body changed'
    elif path.endswith('/import_assets.py'):
        text=once(text,'ASSETS = ROOT / "assets/level1/blender"','ASSETS = ROOT / "assets/level1/blender-v2"')
        text=once(text,'def write_installer(data, kit_name="Level1BlenderKit"):',
                  'def write_installer(data, kit_name="Level1BlenderKitV2"):'+nl+'    assert kit_name == "Level1BlenderKitV2", "Legacy Level1BlenderKit target retired"')
        text=once(text,'p.add_argument("--kit-name", default="Level1BlenderKit")',
                  'p.add_argument("--kit-name", default="Level1BlenderKitV2", choices=("Level1BlenderKitV2",))')
        text=once(text,'assert args.kit_name in ("Level1BlenderKit", "Level1BlenderKitV2"), "Explicit Level 1 kit name required"',
                  'assert not ASSETS.is_relative_to(ROOT / "assets/level1/blender"), "Legacy Level1BlenderKit asset workflow retired"')
        # Payload reuse and the elevator template are deliberately byte/AST unchanged.
        text=once(text,'Texture upload results belong in assets/level1/blender/textures/roblox-assets.json,',
                  'Texture upload results belong in assets/level1/blender-v2/textures/roblox-assets.json,')
        old_tree,new_tree=ast.parse(raw.decode()),ast.parse(text)
        for name in ('payload','upload'):
            old=next(n for n in old_tree.body if isinstance(n,ast.FunctionDef) and n.name==name)
            new=next(n for n in new_tree.body if isinstance(n,ast.FunctionDef) and n.name==name)
            assert ast.dump(old,include_attributes=False)==ast.dump(new,include_attributes=False)
        def template(tree):
            return next(n.value.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='INSTALL' for t in n.targets))
        assert template(old_tree)==template(new_tree),'Shared INSTALL template changed'
    elif path.endswith('/check_assets.py') or path.endswith('/verify_native.py'):
        text=once(text,'/ "assets/level1/blender"','/ "assets/level1/blender-v2"')
        if path.endswith('/check_assets.py'):
            line='    ROOT = parser.parse_args().assets.resolve()'
            text=once(text,line,line+nl+'    assert not ROOT.is_relative_to(Path(__file__).resolve().parents[2] / "assets/level1/blender"), "Legacy Level1BlenderKit QA retired"')
        else:
            line='ROOT = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []).assets.resolve()'
            text=once(text,line,line+nl+'assert not ROOT.is_relative_to(Path(__file__).resolve().parents[2] / "assets/level1/blender"), "Legacy Level1BlenderKit QA retired"')
            text=once(text,'-b assets/level1/blender/Level1_ModularKit.blend','-b assets/level1/blender-v2/Level1_ModularKit.blend')
    elif path.endswith('/publish_textures.py'):
        text=once(text,'SOURCE = ROOT / "assets/level1/blender/textures"','SOURCE = ROOT / "assets/level1/blender-v2/textures"')
        line='    assert source.is_relative_to(ROOT / "assets/level1"), "Only Level 1 texture directories are supported"'
        text=once(text,line,line+nl+'    assert not source.is_relative_to(ROOT / "assets/level1/blender"), "Legacy Level1BlenderKit publication retired"')
    elif path=='tools/export_level1_facelift_verified.py':
        text=once(text,'Read-only final five-script/editor','Read-only final V2 seven-script/editor')
        tree=ast.parse(text)
        main=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='main')
        conditional=next(n for n in main.body if isinstance(n,ast.If) and isinstance(n.test,ast.Attribute) and n.test.attr=='revision_v2')
        lines=text.splitlines(keepends=True)
        text=''.join(lines[:conditional.lineno-1]+lines[conditional.end_lineno:])
        text=once(text,'parser.add_argument("--revision-v2", action="store_true")',
                  'parser.add_argument("--revision-v2", action="store_true", help="Compatibility alias; V2 is the active target")')
        tree=ast.parse(text)
        scripts=next(n for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='SCRIPTS' for t in n.targets))
        lines=text.splitlines(keepends=True)
        extra='    (["ServerScriptService", "Level 1 Systems", "PuzzleManager"], "Script"),'+nl+'    (["ServerScriptService", "Level 1 Systems", "EntityAnimation"], "Script"),'+nl
        text=''.join(lines[:scripts.end_lineno-1])+extra+''.join(lines[scripts.end_lineno-1:])
        assert text.count('Level1BlenderKit')==5
        text=text.replace('Level1BlenderKit','Level1BlenderKitV2')
        text=once(text,'kit_file = ("Level1BlenderKitV2V2" if args.revision_v2 else "Level1BlenderKitV2") + ".instances.json"',
                  'kit_file = "Level1BlenderKitV2.instances.json"')
    elif path.endswith('/README.md'):
        text=LEVEL1_README
    else:
        raise AssertionError(path)
    if path.endswith('.py'):
        ast.parse(text,filename=path)
    return text.encode('utf8')

LEVEL1_README='''# Level 1 Blender authoring

The active room kit is `Level1BlenderKitV2`, authored by `build_v2.py` in an
independent headless Blender. The separate elevator workflow uses
`elevator_inset.py` and `import_elevator_inset.py` to produce
`Level1ElevatorInsetKit`. `build.py` retains their shared mesh, material, room,
UV, export and render helpers; its standalone legacy build entry is retired.

```powershell
python tools/level1_blender/prepare_v2_textures.py
& D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level1_blender/build_v2.py
python tools/level1_blender/check_assets.py
& D:/Blender/blender.exe -b assets/level1/blender-v2/Level1_ModularKit.blend --python-exit-code 1 -P tools/level1_blender/verify_native.py
python tools/level1_blender/import_assets.py
```

Check, native QA, texture publication and room import default to
`assets/level1/blender-v2`. Explicit old `assets/level1/blender` public workflow
targets and `Level1BlenderKit` installation are retired. Keep that historical
asset tree: V2 still reuses carpet/ceiling pixels and matching old mesh/texture
receipts. No receipt IDs or uploaded assets are retired by this tool change.

The V2 kit contains 42 weighted room variants and 41 shared components. It
preserves the exact original wallpaper asset `87947439437597`, five-channel
grille fixtures, rare columns, short dividers and mechanical props. Room cells
remain 24 studs, wall height 14, full wall thickness 2; cardinal socket masks
and collision authority stay with the original gameplay Parts. Decorative
columns remain outside the central clear square and navigation lanes.

`import_assets.py` prepares a reviewable V2 installer without connecting to
Studio. Upload/install require an explicit action flag and exact `--studio-id`.
Installers refuse an existing target kit and stage their components off-tree.
Existing meshes are reused only when their binary wire hash matches; PBR
receipts in `textures/published.json` are checked against actual file hashes.
The shared INSTALL template's old kit token remains an elevator substitution
placeholder, not a public legacy install target.

```powershell
& D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level1_blender/elevator_inset.py
python tools/level1_blender/import_elevator_inset.py
python tools/level1_blender/publish_textures.py --assets assets/level1/elevator-inset-20261004
```

Elevator fixed-size prefabs, UVs, assembly pivots and existing physical door/
collision proxies remain independent of the room kit. Both publication
workflows retain resumable texture receipts. Running a texture publisher can
upload missing maps; run it only when that external action is authorized.

`tools/export_level1_facelift_verified.py` exports the V2 kit and its seven
script/editor records. `--revision-v2` remains a compatibility alias. Use a new
`--output` directory for evidence and `--run` only for an authorized fresh
Studio Edit read. `install_sources.py` is an active gameplay source tool and
is outside this retirement.

These authoring checks do not establish gameplay, navigation, multiplayer,
streaming, performance or publication. Historical V2 Studio checks and their
limits remain in `artifacts/level1-quality-20261002/current-qa-summary.md`.
'''

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dest',type=Path,required=True)
    args=parser.parse_args()
    dest=args.dest.resolve()
    assert dest.is_relative_to(ROOT) and not dest.exists(),'New proposal directory required inside workspace'
    before={path:(ROOT/path).read_bytes() for path in TARGETS}
    after={path:propose(path,raw) for path,raw in before.items()}
    assert all((ROOT/path).read_bytes()==raw for path,raw in before.items()),'Concurrent scoped source change; no proposal written'
    dest.mkdir(parents=True)
    rows=[]
    for path in TARGETS:
        row={'path':path,'beforeSHA256':sha(before[path]),'candidateSHA256':sha(after[path]),
             'beforeBytes':len(before[path]),'candidateBytes':len(after[path])}
        for kind,values in (('before',before),('candidate',after)):
            proof=dest/kind/(path+'.bin')
            proof.parent.mkdir(parents=True,exist_ok=True)
            proof.write_bytes(values[path])
            row[kind+'Path']=proof.relative_to(ROOT).as_posix()
        rows.append(row)
    manifest={'schema':'level1-legacy-workflow-retirement-proposal-v1','status':'afventer before/after authoring testport and parent review',
              'productionFilesModified':False,'nativeCalls':0,'sourceFiles':rows,'retainedAssets':'All assets/level1 trees and receipt IDs',
              'scope':'Legacy standalone build entry/default public targets only; shared INSTALL/helper bodies and active V2/elevator source tools retained'}
    (dest/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
    assert all((ROOT/path).read_bytes()==raw for path,raw in before.items()),'Concurrent scoped source change after preparation; do not install'
    print(json.dumps({'files':len(rows),'productionFilesModified':False,'dest':str(dest)}))

if __name__=='__main__':
    main()
