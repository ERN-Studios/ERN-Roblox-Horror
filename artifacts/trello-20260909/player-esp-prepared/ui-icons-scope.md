# New section icons and existing product artwork

[WJLErpHx — Create icons for Upgrades, Gear, and Shop](https://trello.com/c/WJLErpHx) says exactly: "Create an icon for each of the three sections: Upgrades, Gear, and Shop." The card and dedicated checklist endpoint returned no checklists. No further style, asset IDs or placement is specified.

This is **three navigation/section symbols**, distinct from the twelve prepared offer images under `product-icons-prepared/`: three passes, three utility products and six donation tiers. Those images correspond to purchase entries and six existing `Config.*.IconId` destinations. None is an approved replacement for the three new section symbols, and no purchase IDs, pricing or grants need to change for this card.

The current ZyntraStore has a combined `ZyntraOpenButton` labeled **UPGRADES & GEAR** (construction line110, normal-state label around2505) and a separate `ZyntraShopButton` labeled **SHOP** (line118). Its page list is Upgrades, Shop, Donate, Colors, Settings plus the authorized Dev page; there is no separate Gear page. A bounded implementation can place the Upgrades and Gear symbols beside their respective wording in the combined opener, and the Shop symbol in the existing Shop opener. It must retain the two existing click destinations, the responsive sizing, the 44-pixel touch floor and current queue/modal/round hiding rules. Creating a new Gear navigation destination would expand the card's unspecified behavior.

Simple coherent line symbols can be produced from existing UI primitives or separately approved icon assets. The existing twelve imagegen masters do not need edits or platform reuploads for this task. Actual small-size rendering, current Store layout and touch spacing still need native review before publish.

No icon artwork, image upload, runtime edit or Studio operation was performed for this scope note. Parent assigned the isolated icon proposal to spawn_diagnosis after this read-only discovery; its edits stay outside the new DEV-row region described in this directory's README.
