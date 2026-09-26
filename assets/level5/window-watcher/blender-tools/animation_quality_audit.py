from pathlib import Path
import sys, math
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
from watcher_common import *
OUT=Path(__file__).resolve().parents[1]
import_asset(OUT/"model.blend")
rig=get_rig()
results={"clips":[],"issues":[]}
reference=None
for name,(start,end) in CLIPS.items():
 activate_action(rig,bpy.data.actions[name])
 samples=[]
 for frame in range(start,end+1):
  bpy.context.scene.frame_set(frame)
  samples.append({b.name:b.matrix.copy() for b in rig.pose.bones})
 first,last=samples[0],samples[-1]
 if reference is None:reference=first
 def angle(a,b):
  degrees=math.degrees(a.to_quaternion().rotation_difference(b.to_quaternion()).angle)
  return min(degrees,abs(360-degrees))
 row={"name":name,"frames":len(samples),"duration_seconds":(end-start)/FPS,
      "loop_translation_error":max((first[n].translation-last[n].translation).length for n in first),
      "loop_rotation_error_degrees":max(angle(first[n],last[n]) for n in first),
      "base_pose_translation_error":max((first[n].translation-reference[n].translation).length for n in first),
      "base_pose_rotation_error_degrees":max(angle(first[n],reference[n]) for n in first),
      "max_step_translation":max((samples[f][n].translation-samples[f-1][n].translation).length for f in range(1,len(samples)) for n in first),
      "max_step_rotation_degrees":max(angle(samples[f][n],samples[f-1][n]) for f in range(1,len(samples)) for n in first),
      "feet_max_drift":max((s[n].translation-first[n].translation).length for s in samples for n in ("LeftFoot","RightFoot","LeftToeBase","RightToeBase")),
      "root_max_drift":max((s["Root"].translation-first["Root"].translation).length for s in samples)}
 if row["loop_translation_error"]>1e-4 or row["loop_rotation_error_degrees"]>.1:results["issues"].append(name+": loop mismatch")
 if row["base_pose_translation_error"]>1e-4 or row["base_pose_rotation_error_degrees"]>.1:results["issues"].append(name+": shared initial pose mismatch")
 if row["feet_max_drift"]>1e-4 or row["root_max_drift"]>1e-4:results["issues"].append(name+": planted feet/root moved")
 if row["max_step_rotation_degrees"]>15:results["issues"].append(name+": abrupt frame step")
 results["clips"].append(row)
results["pass"]=not results["issues"]
write_json(OUT/"animation-quality-audit.json",results)
print(results)
if not results["pass"]:raise SystemExit(2)
