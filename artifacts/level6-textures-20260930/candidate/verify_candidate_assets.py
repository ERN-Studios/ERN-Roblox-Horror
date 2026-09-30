"""Verify the generated files and combine the final offline candidate checks."""
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


pixels = json.loads((HERE / "atlas-pixels.json").read_text())
raw = base64.b64decode((HERE / "atlas-rgba.b64").read_bytes(), validate=True)
assert len(raw) == pixels["bytes"] == 1024 * 1024 * 4
assert hashlib.sha256(raw).hexdigest() == pixels["sha256"]
image1024 = np.asarray(Image.open(HERE / "textures/WornParty_Level3Reference_Atlas1024.png").convert("RGBA"))
assert raw == image1024.tobytes()
assert sha(HERE / "textures/WornParty_Level3Reference_Atlas1024.png") == pixels["originalPngSha256"]
assert np.all(image1024[:, :, 3] == 255)
assert (HERE / "textures/atlas-layout.json").read_bytes() == (ROOT / "assets/level6-worn-party/textures/atlas-layout.json").read_bytes()

original2048 = np.asarray(Image.open(ROOT / "assets/level6-worn-party/textures/WornParty_Atlas.png").convert("RGB"))
candidate2048 = np.asarray(Image.open(HERE / "textures/WornParty_Level3Reference_Atlas.png").convert("RGB"))
original1024 = np.asarray(Image.open(ROOT / "assets/level6-worn-party/textures/WornParty_Atlas1024.png").convert("RGBA"))
neutral = [3, 4, 8, 9, 10, 11, 12, 13, 14]
neutral_results = []
for cell in neutral:
    records = {"cell": cell}
    for size, before, after in [(512, original2048, candidate2048), (256, original1024, image1024)]:
        x, y = (cell % 4) * size, (cell // 4) * size
        before_slice, after_slice = before[y:y + size, x:x + size], after[y:y + size, x:x + size]
        assert np.array_equal(before_slice, after_slice)
        records[str(size * 4)] = {"byteEquivalent": True, "sha256": hashlib.sha256(after_slice.tobytes()).hexdigest()}
    neutral_results.append(records)

saved = json.loads((HERE / "saved-blend-parity.json").read_text())
assert saved["savedGeometryUVMaterialKeysMatch"]
assert saved["savedSceneInstanceRoutingChangesMatchScope"]
assert sha(ROOT / "assets/level6-worn-party/Level6_WornParty_v2.blend") == saved["sourceBlendSha256"]
assert sha(HERE / "Level6_WornParty_Level3Reference_candidate.blend") == saved["candidateBlendSha256"]
assert sha(HERE / "textures/WornParty_Level3Reference_Atlas.png") == saved["candidateAtlasSha256"]

files = ["atlas-pixels.json", "atlas-candidate-manifest.json", "blend-candidate-manifest.json",
         "saved-blend-parity.json", "preview-records.json", "claude-palette.json",
         "texture-comparison.jpg", "blender-study-comparison.jpg",
         "textures/atlas-layout.json", "textures/candidate-material-colors.json",
         "textures/WornParty_Level3Reference_Atlas.png", "textures/WornParty_Level3Reference_Atlas1024.png",
         "Level6_WornParty_Level3Reference_candidate.blend", "atlas-rgba.b64"]
result = {"schema": "level6-offline-candidate-final-verification-v1",
          "installedInStudio": False, "liveStudioReferenceVerified": False,
          "assetChecksPassed": True, "savedBlendChecksPassed": True,
          "rawRGBABytes": len(raw), "rawRGBASha256": pixels["sha256"],
          "atlasLayoutByteIdentical": True, "sourceBlendUnchanged": True,
          "candidatePackedAtlasVerified": True, "objectCount": saved["candidate"]["objectCount"],
          "materialCount": saved["candidate"]["materialCount"],
          "geometryUVMaterialKeyInstanceFingerprints": saved["candidate"],
          "scopedAuthoredStudyFloorRoutingChanges": saved["sceneInstanceRoutingChanges"],
          "maintenanceStudyFloorServiceUnchanged": True,
          "neutralCellChecks": neutral_results,
          "files": [{"path": path, "bytes": (HERE / path).stat().st_size, "sha256": sha(HERE / path)} for path in files],
          "limitations": ["Historical source textures; current live Studio reference not yet verified.",
                          "Atlas geometry/UV layout preserved; Blender physical texture repeat does not match native fixed-repeat carpets.",
                          "Red wall wear is a hue-preserving art approximation requiring live native A/B.",
                          "No Studio write, publication or mesh reimport performed.",
                          "No gameplay, multiplayer, Roblox rendering or performance claim follows from these offline checks."]}
(HERE / "final-verification.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"passed": True, "rawRGBASha256": pixels["sha256"], "objects": result["objectCount"], "materials": result["materialCount"], "neutralCells": neutral}))
