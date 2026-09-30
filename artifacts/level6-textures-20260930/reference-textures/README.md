# Original Level 3 image reference

All 15 Level 3 configuration image slots and the extra Mall Manager ColorMap are materialized here as the original source images. `reference-manifest.json` records Roblox IDs, pixel dimensions, image modes, source checksums and provenance. `level3-textures-contact-sheet.jpg` is a compact visual catalogue.

Official Roblox Asset Delivery rejected anonymous retrieval with HTTP 401/403. No authentication files or credentials were accessed. Images were recovered from the existing verified repository source pack `assets/source-packs/live-assets-2026-08-26`, whose reconstructed SHA-256 matched `4b083e73ec4606822299e245e2651f82dab48939a51f636aa5e9c6761405302e`. Every extracted image also matched its original archive `SHA256SUMS` entry. The historical image-to-asset-ID mapping is recorded by `assets/live-asset-manifest.json`.

Fresh Studio inspection remains necessary to verify that live `ReplicatedStorage.Level 3 Assets` StringValues still use these IDs and that furniture templates have not changed. This reference package does not prove current live parity.

The historical folding-table texture ID `112282995723556` is catalogued as unavailable: it was not present in the verified local source archive and could not be downloaded anonymously.

Repeat generation with the existing Pillow environment:

```sh
/tmp/level6-build-venv/bin/python artifacts/level6-textures-20260930/reference-textures/catalogue_reference.py
```

No runtime source or Studio instances were modified.
