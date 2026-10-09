"""Compare real R4 ports; retain the isolated .blend hash as explicit metadata.

Two unchanged factory-startup builds produce distinct .blend hashes. Only the
manifest's sourceBlendSha256 may differ; meshes, textures, placements, colliders,
all other manifest fields and every other actual port record must be identical.
"""
from pathlib import Path
import copy
import hashlib
import json


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def verify(before_dir, after_dir):
    directories = (Path(before_dir), Path(after_dir))
    receipts, manifests, blend_hashes = [], [], []
    for directory in directories:
        receipt = json.loads((directory / 'receipt.json').read_bytes())
        assert receipt['pass'] is True
        raw = (directory / 'r4/manifest.json').read_bytes()
        manifest = json.loads(raw)
        assert receipt['freshR4Payload']['/manifest'] == {'bytes': len(raw), 'sha256': sha(raw)}
        blend_hash = sha((directory / 'r4/LobbyReimaginedPreview.blend').read_bytes())
        assert manifest['sourceBlendSha256'] == blend_hash, 'Generated blend receipt does not match actual file'
        blend_hashes.append(blend_hash)
        del manifest['sourceBlendSha256']
        manifests.append(manifest)
        normalized = copy.deepcopy(receipt)
        del normalized['freshR4Payload']['/manifest']
        receipts.append(normalized)
    assert manifests[0] == manifests[1], 'R4 semantic manifest changed beyond the generated blend hash'
    assert receipts[0] == receipts[1], 'Active actual R4 geometry/textures/QA/installer/gates changed'
    encoded = json.dumps(manifests[0], sort_keys=True, separators=(',', ':')).encode()
    return {'pass': True, 'sameActiveAuthoringSemantics': True,
            'sameOtherFreshPayloadEndpoints': len(receipts[0]['freshR4Payload']),
            'semanticManifestSHA256': sha(encoded), 'isolatedBlendSHA256': blend_hashes,
            'excludedFromEquality': ['freshR4Payload./manifest hash only after full parsed manifest equality except sourceBlendSha256'],
            'scope': 'Generated private Blender output metadata only. No production/source/asset/receipt normalization.'}
