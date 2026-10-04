# Hiding animation and cleanup — 21:50 UTC

Published group-owned Blender animation113160394754713,4-second loop, tested
again on a differently oriented generated table (anchor yaw near-92 degrees).
Entered successfully from world-Z+6 and world-Z-6 approaches. Both entries
replicated the correct animation ID; native client track Length4, Weight1,
PriorityAction. Earlier130-frame clearance/root-drift proof is in
native-hide-validation.json.

- E exit: hidingfalse, trackremoved, rootunanchored, Walk16/Jump50/AutoRotate,
  ProximityPromptService.Enabledtrue and hideGUIoff.
- Death while hidden from opposite approach: wasHiddentrue → hiddenfalse,
  animationIDnil, authoredtrackcount0, rootunanchored, Walk16/Jump50,
  workspaceLevel3HiddenPlayers0. NativePASS.
- Two simultaneously connected real clients were not exercised. Server track
  replication to the real local client is verified.

UI final check PASS after fixing safe-area alias: UIDevice.SafeBottom is the
legacy HUD band bottom, whereas layout.Safe.Bottom is the true safe screen
bottom. Radio captions while hiding now use the latter; desktop hidden status
and exit use UIDevice.LocalPosition to account for the58px GUI origin shift.

Native rectangles (x,y,width,height), all three visible simultaneously:

| View | Hidden/warning status | Leave hiding | Radio caption |
|---|---|---|---|
| Desktop899×675 |269,8,360,42|284,58,330,58|108,459,683,96|
| Touch568×320 |104,8,360,22|119,36,330,44|235,150,320,70|
| Touch390×844 |15,8,360,42|30,56,330,52|12,654,330,90|

No overlap between these controls. On touch the bottom radio area is used only
while the character is anchored in hiding; normal play retains its existing
movement-safe top placement. Studio overrides cleared afterward.

Fallback: stopped the authored animation track on the real client while still
hidden. The existing procedural writer resumed: Root transform(0,-.92,.12),
rotation-8deg, hip/knee transforms match the authored CROUCH_POSE. Hiding stayed
active and root anchored. This simulates unavailable/not-playing content.

Attempted native FlushAnchor through commandbar require returned0 while one
player was hidden: commandbar module state is separate from the running game
module. This attempt is not counted as a gameplay flush test. The actual
release routine is verified by E exit/death and source integration.
