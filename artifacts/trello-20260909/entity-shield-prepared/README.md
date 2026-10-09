# Entity Shield — prepared proposal, qFCuCf3w

User-selected name: **Entity Shield**. Purchase moves from Shop to the third card in Upgrades. This is an artifact only; production files and Studio were not changed.

Four narrow source changes:

- Config: item name, description and the two token-pack descriptions. `TokenCost = 5`, `DurationSeconds = 5`, product IDs and internal `EntityProtection` key remain identical.
- Store: use the existing scrollable Upgrades card at order 3, with a `5s` readout, exact `OWNED` count and the existing five-token purchase/retry state. The same shared `BuyProtection` request and `Retry()` own transaction correlation. Buying does not activate the shield. Intro copy distinguishes permanent upgrades from this consumable. The old generic TokenItem branch is left untouched but has no card caller.
- HUD: the desktop caption becomes `Entity Shield`; the small touch slot uses `SHIELD`. SAFE/countdown, bindings, enabled predicates, capture cancellation and all lifecycle/input code are unchanged. A pending purchase is no longer labelled SHOP.
- Monetization: only response text changes, including the no-charge direction to Upgrades. The complete transaction, receipt and persistence logic is byte-identical outside these string replacements.

The new card is at `ZyntraTerminal/.../Upgrades/UpgradeCards/Entity`, with the existing `Spend` button. It reuses the grid's one/two-column scrolling layout and minimum 48px button. It is not enrolled in the Shop card measurements or Robux purchase path.

Validation: `python artifacts/trello-20260909/entity-shield-prepared/test_proposal.py` passes 18 actual card-state/action checks, the existing 92 full-source HUD checks and 2 caption checks. Four whole proposed files plus the ESP/icons/Shield Store merge preview compile. All four production SHA values remain equal to their immutable before snapshots. The Store baseline already includes the corrected section icons/Contextual UIStroke behavior.

`prepare.py` writes artifacts only and refuses production baseline drift. It applies the same narrow Store transform to the existing reviewed ESP+icons merge preview, without editing that input. The preview must not be used to overwrite later unrelated Store changes. Config may acquire product-icon fields in another task; apply the small copy-only diff to a fresh checkpoint when needed, preserving those IDs.

Root native acceptance still needed: Upgrades shows all three cards and scrolls to Entity Shield, Shop no longer shows it, actual purchase/Retry uses the same shared state, and desktop/touch captions and descriptions fit. Existing native protection behavior can be reused because this proposal changes neither activation nor economics. No physical phone, native rendering or live DataStore result is claimed here. Independent review is pending; the author has not assigned a score.
