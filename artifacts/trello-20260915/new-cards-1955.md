# New Trello cards — owner notified Codex 2026-09-15

Read at 19:55 UTC. These task requirements remain subordinate to OWNER-BRIEF.md and owner-answers.md.

## https://trello.com/c/UwFJOWZH/98-unify-in-game-ui-using-objectives-and-mission-brief-as-the-style-reference

Unify in-game UI using Objectives and Mission Brief as the style reference

Review all in-game UI and fix visual inconsistencies so everything feels cohesive, sleek, and polished.

Use the existing Objectives and Mission Brief UI as the visual reference; the owner likes their current design. Apply that style consistently to buttons and other UI elements throughout the levels and the rest of the game, including typography, colors, spacing, borders, and panel styling.

## https://trello.com/c/FXH0ddhN/99-codex-create-a-table-hiding-animation-in-blender-via-mcp

Codex: Create a table-hiding animation in Blender via MCP

Codex should open Blender and use the MCP connection to create an animation for hiding under a table.

Keep the entry simple: teleport ("TP") the player into position, then visibly show the character hiding under the table.

## Work coordination

- #98: authorized visual consistency audit and implementation using existing Objectives/Mission Brief styling, including existing game buttons/panels. No gameplay redesign, incentives, sale, controller scope, or #74 behavior change. Delegate Opus 5 and partition files with #81/#82/#88; capture before/after desktop/touch.
- #99: Codex will inspect Blender/MCP capability and author table-hiding animation. Keep entry simple: TP to position then visible hiding pose/animation. A80 owns live hiding/camera/restoration fix; ask A80 to coordinate rig type, existing joints/pose, clearance, loop timing and expected animation import seam. No duplicate animation creation or concurrent Studio editing.
- Texture requests received. Codex generating requested shop assets offline. Preserve SHOP_TEXTURES table for final imported ids; do not publish procedural fallbacks as final completion before asset coordination.
