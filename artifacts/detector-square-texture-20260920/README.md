# Square detector texture and shop captions — 2026-09-20

Published v1949 at 17:47:02 UTC, verified from Studio publishType=1 / PublishSuccessful / v1949 log entries.

The game-pass icon uploaded earlier was circular and unsuitable for box faces. Uploaded the existing original square artwork assets/shop/box-entity-detector.png through Studio MCP upload_image, producing standalone image 90757067349588. Lobby texture mapping and in-game catalogue IconId now use that square image; the permanent pass ID and sale price are unchanged.

Shop billboard width is 4.4 studs (previously 7), with 1.1-stud height and wrapped text. Detector caption is explicitly two lines, ENTITY / DETECTOR, to avoid the cropped long name and overlapping neighbours.

Validation: both changed sources compile. Native Play confirmed all six decals reference 90757067349588; caption wraps and width is 4.4 within floating-point tolerance. Visual inspection from a diagonal angle showed two complete square faces with no transparent corners and the two-line caption. Initial exact equality against floating-point 4.4 was corrected in the probe, not in production code. All 154 Source/editor buffers match repository bytes/hashes. No gameplay or physical-device tests were needed for this visual-only change; no live servers restarted. Existing full v1947 native backup retains unchanged non-script Edit content; final script sources are mirrored separately.
