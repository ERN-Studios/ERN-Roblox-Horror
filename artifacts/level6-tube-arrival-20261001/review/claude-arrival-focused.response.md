No stated fact blocks walk-out or return (facts only; no images, nothing tested). Four gaps could:

1. **Join radius.** Spawn is 6 studs inside the tube; PreviewExit's distance from the mouth is unstated. Beyond about 11.6 studs on-axis, the ≤18 check fails.
2. **Floor ray.** It must start inside the bore and hit an owned runout collider; from above, the tube crown or roof also passes normalY>.7.
3. **Copied colliders.** Attributes are covered; Level3 tags, collision groups, and slide friction aren't.
4. **Spawn height.** Two references are given; derive it from the ray hit, with PreviewExit+3.5 as a sanity bound.

**Play checks**
- Enter: upright, grounded, facing +X, no drift for 3s without input.
- Forward only: reaches the Arrival floor without jumping or snagging, including along each wall.
- Join accepted, one ACK, E returns; repeat entry ×3, once after reset.
- Looking back: tube and sign render, other legacy stays hidden, no gaps at raised walls.
