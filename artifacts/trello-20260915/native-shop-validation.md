# Native shop QA — 21:21 UTC

- All six physical plates/crates created from actual catalogue, twelve uploaded
  textures wired. Native wall/sign review corrected sign glow depth to X31.78.
- Fresh first opening: Supporter card BUY/CLOSE y547..585 in 899x675 viewport;
  no old one-topbar overflow. OWNED is disabled for actual owner; no payment made.
- Synthetic390x844 touch layout: 300x200 card, 44px buttons, description fits.
- Synthetic568x320 touch layout after free-lane correction: card (245,8),
  size300x147; BUY (255,101),188x44; description239x22 inside242x28.
  Uses UIDevice.ModalArea to clear both thumbstick and right-hand controls.
- Forced active dispatch + open card: ZyntraShopDetailOpen=true and caption
  Visible=false. The card publishes a presentation flag, not a movement-suppression
  modal. Actual CLOSE click: card disabled, open flagfalse, dispatch visibletrue.
- 307 offline checks pass on real server/client source including non-purchase
  inspect, owned state, explicit existing purchase bridge, close/step-off,
  motion/reduced flashing, three size tiers and compact free-lane containment.

Synthetic viewport measurements are layout fixtures, not real phone hardware.
