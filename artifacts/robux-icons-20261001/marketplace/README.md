# Official Roblox purchase images and pricing evidence

Scope: existing experience `10559217407`, ERN Roblox Studios group `1039373905`.
The authenticated Dashboard account was LaverSneglen. All actions used the
documented Chrome CUA interface, without credentials or private API calls.

`official-icon-update-receipt.json` records 23 saved, reload-verified image
replacements: 11 passes and 12 developer products. They cover 14 utility
purchases and nine donation purchases. Both existing paid outfit images were
preserved. Names, descriptions, IDs, sale settings, grants, and base prices
were not edited as part of image replacement.

`pass-images-rendered-dom.json` and `product-images-rendered-dom.json` record
the image URLs observed in the actual Dashboard table. The final +4 icon
completed moderation; `developer-products-rendered-bottom.jpg` shows both
correct +4 and +20 purchase pictures. `passes-clean-token-icons.jpg` shows the
distinct source-to-destination upgrade pictures under Roblox's circle mask.

`pricing-ui-baseline.json` and `managed-pricing-before.json` record the initial
25 eligible purchase IDs: 13 passes and 12 developer products, with 12 already
enabled and 13 disabled. Enrollment changes are gated on the parent agent's
verified successful publish of dynamic-price compatibility. Checkbox selection
alone is never evidence of enrollment. A final pricing receipt must record
persisted status after reload, coverage, and all 25 unchanged configured prices.

JPEG screenshots are original captured browser viewport bytes. The site's
inner scrolling container requires separate top/bottom captures; `fullPage`
does not show every row at once. Pending-moderation fields in the initial save
receipt describe the moment of save, not the final approved thumbnail status.
