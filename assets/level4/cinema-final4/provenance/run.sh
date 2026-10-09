#!/bin/bash
set -ex
F=G:/Roblox/_local/l4facelift/v5/final4
p=G:/Roblox/_local/l4facelift/v3/P7b
t=G:/Roblox/MongoTV/tools/level4_blender
run=G:/Roblox/_local/l4facelift/v3/blrun.py
cp $F/build.blend $F/final_input.blend
cp $t/l4_layout.json $F/layout.json
mkdir -p $F/build_src && cp $t/*.py $t/*.json $t/*.luau $t/*.lua $F/build_src/ 2>/dev/null
python $run "$F/final_input.blend" "$t/cull_hidden.py" "$F/final.blend" --report "$F/report.json" --work-dir "$F/work" --layout "$F/layout.json" --build-dir "$F/build_src" --python-path 'G:/Roblox/_local/l4facelift/v3/P7/pylib' --views "G:/Roblox/_local/l4facelift/v5/assets/proof_views.json" --visibility-views "$p/proof_tools/views_p2.json" --keep "G:/Roblox/_local/l4facelift/v5/assets/keep_delivery.json" || { echo CULL_FAILED; exit 1; }
python $run "$F/final_input.blend" "$p/proof_tools/proof_hidden.py" --after "$F/final.blend" --views "G:/Roblox/_local/l4facelift/v5/assets/proof_views.json" --samples "$F/work/camera_samples.npy" --out-dir "$F/proof" --count 150 --random-count 150 --no-defaults --canonical-geometry
python "$p/proof_tools/proof_summary.py" "$F/proof" --cull-report "$F/report.json"; echo "SUMMARY_EXIT $?"
python "$p/proof_tools/audit_informative.py" "$F/proof" --views "G:/Roblox/_local/l4facelift/v5/assets/proof_views.json"; echo "INFORMATIVE_EXIT $?"
python $run "$F/final_input.blend" "$p/sampling/audit_saved.py" --report "$F/report.json" --out "$F/audit_saved.json"; echo "AUDIT_EXIT $?"
export L4_EXPORT_OUT="$F/export" L4_EXPORT_LAYOUT="$F/layout.json" L4_EXPORT_BUILD_DIR="$F/build_src"
python $run "$F/final.blend" "$t/export_l4.py"; echo "EXPORT_EXIT $?"
python "$t/make_place.py" "$F/export"; echo "MAKEPLACE_EXIT $?"
echo ALL_DONE
