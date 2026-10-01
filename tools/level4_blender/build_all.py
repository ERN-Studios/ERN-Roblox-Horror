# Level 4 facelift: the whole Blender build in one run.
#   blender -b <blend> --python-exit-code 1 -P build_all.py -- <out.blend>
#   exec(open(r"G:\Roblox\MongoTV\tools\level4_blender\build_all.py").read(), {"OUT_BLEND": r"<out.blend>"})
# Runs every step whose file exists, in order:
#   build_base (l4_layout.json is precomputed) -> lights_and_camera.build_lights (the original lights, "L4 Lights";
#   the packages delete the ones whose fixture they replace, export_l4 drops LIGHTS_SUPERSEDED) -> slots ->
#   Meshy import (meshy_specs.json + import_meshy.py; only assets whose mesh "L4A_<asset>" is missing, all of them
#   with FORCE_MESHY = True) -> props (it wipes "L4 Props" and makes the MarbleColumns arch_detail replaces) ->
#   arch_detail.build_detailing -> props_lobby -> props_rooms -> ceilings.build_ceilings (its fallen tiles ray-cast
#   down onto the final props) -> props_decay.build_decay (needs the ceilings) -> doors_v2 (else doors), then saves a
#   copy to the output path (none given: nothing is saved).
# Each step is exec'd in a copy of slots.py's namespace (slot(), SLOTS) with __name__ = "l4_build_all"; its build
# function is called unless the file already calls it at top level, so a module that builds on exec and one guarded
# by `if __name__ == "__main__"` both run once. A failing step stops the run before anything is saved, unless
# KEEP_GOING = True (or env L4_BUILD_KEEP_GOING=1): then it is reported and the run goes on without it. SKIP = [files]
# (or env L4_BUILD_SKIP="a.py,b.py") leaves steps out. It never writes the master blend.
import ast, json, os, sys, time, traceback
import bpy

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
MASTER = os.path.normcase(r"G:\Blender\Level4_Cinema\Level4_Cinema.blend")
STEPS = [   # (file, build functions: the first one the module defines is called)
    ("build_base.py", ()),
    ("lights_and_camera.py", ("build_lights",)),
    ("slots.py", ()),
    ("import_meshy.py", ()),                   # special: runs meshy_specs.json
    ("props.py", ()),                          # before arch_detail: it wipes "L4 Props", arch_detail deletes its columns
    ("arch_detail.py", ("build_detailing",)),
    ("props_lobby.py", ("build_props_lobby", "build_lobby_props", "build")),
    ("props_rooms.py", ("build_rooms_props", "build_props_rooms", "build_room_props", "build")),
    ("ceilings.py", ("build_ceilings",)),     # after the props: its fallen tiles ray-cast onto what stands below
    ("props_decay.py", ("build_decay",)),
    ("doors_v2.py", ("build_doors_v2", "build_doors", "build")),
    ("doors.py", ()),                          # only when doors_v2.py does not exist
]
CORE = ("build_base.py", "lights_and_camera.py", "slots.py")   # never skipped past, even with KEEP_GOING


def top_level_calls(src):
    return {n.value.func.id for n in ast.parse(src).body
            if isinstance(n, (ast.Expr, ast.Assign, ast.AnnAssign)) and isinstance(n.value, ast.Call)
            and isinstance(n.value.func, ast.Name)}


def meshy(path):
    specs = json.load(open(os.path.join(HERE, "meshy_specs.json")))
    todo = [s for s in specs if globals().get("FORCE_MESHY") or not bpy.data.meshes.get("L4A_" + s["asset"])]
    if todo:
        exec(compile(open(path, encoding="utf-8").read(), path, "exec"), {"SPEC": todo, "__file__": path})
    return "%d/%d imported" % (len(todo), len(specs))


def step(fn, funcs, base):
    path = os.path.join(HERE, fn)
    t = time.time()
    if fn == "import_meshy.py":
        if not os.path.exists(os.path.join(HERE, "meshy_specs.json")):
            return None
        res = meshy(path)
        print("build_all: %-22s %6.1f s (%s)" % (fn, time.time() - t, res), flush=True)
        return None
    src = open(path, encoding="utf-8").read()
    ns = dict(base, __name__="l4_build_all", __file__=path)
    exec(compile(src, path, "exec"), ns)
    f = next((f for f in funcs if callable(ns.get(f))), None)
    if f and f not in top_level_calls(src):
        ns[f]()
    print("build_all: %-22s %6.1f s%s" % (fn, time.time() - t, " (%s)" % f if f else ""), flush=True)
    return ns


def out_path():
    if globals().get("OUT_BLEND"):
        return globals()["OUT_BLEND"]
    if "--" in sys.argv[:-1]:
        return sys.argv[sys.argv.index("--") + 1]
    return None


def build_all(out=None):
    assert os.path.exists(os.path.join(HERE, "l4_layout.json")), "l4_layout.json missing: run layout_edits.py"
    if out and os.path.normcase(os.path.abspath(out)) == MASTER and not globals().get("ALLOW_MASTER"):
        raise RuntimeError("build_all will not overwrite the master blend (set ALLOW_MASTER = True to mean it)")
    base, t0, failed = {}, time.time(), []
    for fn, funcs in STEPS:
        if not os.path.exists(os.path.join(HERE, fn)):
            continue
        if fn == "doors.py" and os.path.exists(os.path.join(HERE, "doors_v2.py")):
            continue
        if fn in (globals().get("SKIP") or os.environ.get("L4_BUILD_SKIP", "").split(",")):
            print("build_all: %-22s skipped" % fn, flush=True)
            continue
        try:
            ns = step(fn, funcs, base)
        except Exception:
            if not (globals().get("KEEP_GOING") or os.environ.get("L4_BUILD_KEEP_GOING")) or fn in CORE:
                raise
            traceback.print_exc()
            failed.append(fn)
            print("build_all: %-22s FAILED, continuing (KEEP_GOING)" % fn, flush=True)
            continue
        if fn == "slots.py":
            base = {k: v for k, v in ns.items() if k not in ("__name__", "__file__")}
    if out:
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(out), copy=True)
        print("build_all: saved", out, flush=True)
    else:
        print("build_all: no output path given, not saved", flush=True)
    print("build_all: done in %.1f s%s" % (time.time() - t0, "; FAILED: " + ", ".join(failed) if failed else ""),
          flush=True)


build_all(out_path())
