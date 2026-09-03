--[[
LEVEL 2 POOL FOAM - INSTALLATION, RIG REPLACEMENT, AND TUNING
==============================================================

This is documentation only. It has no runtime side effects.

1. WHAT IS INSTALLED
--------------------

The encounter creates one server-owned Primary clone in every generated Kids
Area room (five with the current layout configuration). Each clone has a unique
runtime ID but shares the final Primary art and animation slot. An unseen clone
walks slowly toward the nearest eligible player. When any player sees it while
it is moving, it continues for 0.50 seconds, then pauses the active AnimationTrack
at its exact TimePosition and freezes in that pose. Looking away resumes the same
track without restarting it. If an active clone reaches an unobstructed valid
target within Movement.KillDistance (currently 5.5 studs), the server immediately
sets that player's Humanoid health to zero; there is no damage wind-up. Base
Stalk and Hunt movement are both 4.5 studs/second (50% above the previous 3.0),
before phase multipliers. The server owns movement, observation, lethal contact,
targeting, and cleanup.

Put the client LocalScript at:
  StarterPlayer.StarterPlayerScripts.Level 2 Pool Foam Client

The server creates this exact remote path (clients never create it):
  ReplicatedStorage
    Level 2 Pool Foam Remotes (Folder; Generation attribute is the live round)
      ClientReport (RemoteEvent, client -> server)
      ClientEvent  (RemoteEvent, server -> one client)

2. CAMERA REPORT CONTRACT
-------------------------

At most 8 times a second, only while the player is alive, participating in a
live Level 2 round, not escaped, and not spectating, the client sends exactly:

  {
    Protocol = 1,
    Generation = remotesFolder:GetAttribute("Generation"),
    Sequence = increasing integer,
    CameraCFrame = workspace.CurrentCamera.CFrame,
    FieldOfView = workspace.CurrentCamera.FieldOfView,
    ViewportSize = workspace.CurrentCamera.ViewportSize,
  }

The client enumerates CollectionService tag "Level2PoolFoamEntity" as Level 2
world content changes. Each runtime model carries `PoolFoamSlot=Primary` plus a
unique `PoolFoamEntityId` such as Primary_01. The client does not claim an entity
is hidden. Server observation must still
validate protocol, generation, sequence, report rate, camera/head distance,
field of view, viewport, frustum, and solid-world line of sight. Missing or bad
reports must make movement more conservative, never safer.

3. CLIENT PRESENTATION EVENTS
-----------------------------

ClientEvent:FireClient(player, payload) accepts a small table. Supported Type
(or legacy Kind) values are Cue, Reveal, Attack, Phase, and Decoy. Optional
fields: Protocol=1, Caption (string or false), CaptionDuration, Intensity 0..1,
Volume, PlaybackSpeed, AttackId, and Emphasis for Cue. AttackHit is emitted for
lethal contact. FirstReveal, AttackStart, and AttackCancelled remain harmless
client compatibility aliases for older servers but are not sent by this controller.

Effects are local-only: a short caption, restrained FOV pulse, a subtle color
grade, a tiny optional camera nudge, and optional sounds. It never changes
CameraType, CameraSubject, player CFrame, health, objectives, or round state.
Player attributes ReduceFlashing, ReduceCameraShake, CaptionsEnabled=false, and
DisableCaptions=true are respected. All SOUND_IDS are empty by design; never
send SoundId through ClientEvent.

4. FINAL ART DROP-IN CONTRACT
-----------------------------

The active final rig belongs at this exact path:
  ServerStorage.Level2Assets.PoolFoamPrimaryTemplate

The current encounter clones this model into every Kids room. The optional
PoolFoamSecondaryTemplate name remains reserved for a future visually distinct
variant but is not spawned by the current five-room controller. Do not rename
the Primary slot, controller, or remotes. If the final Primary model is missing,
the proxy factory uses a clearly marked temporary proxy.

Each final template must:
  * Be a Model with PrimaryPart set to Root (a BasePart).
  * Preserve a stable Root at the intended floor/water-plane pivot. The root is
    the server transform and must not be animated away.
  * Place all presentation geometry below the model. Visual art should be
    non-anchored, Massless=true, CanCollide=false, CanTouch=false, and normally
    CanQuery=false. Gameplay hit volumes remain server-owned.
  * Have no scripts, remotes, ProximityPrompts, TouchTransmitters, or damage
    logic inside the imported art.
  * Set PoolFoamTemporaryProxy=false on the final template. Runtime tags and
    attributes are added by the controller; do not depend on them in art.

Recommended hierarchy:
  PoolFoamPrimaryTemplate / PoolFoamSecondaryTemplate
    Root (BasePart, PrimaryPart)
    VisualRig (Model, your skinned mesh / bones / welded art)
      AnimationController
        Animator

The rig can use Humanoid instead of AnimationController only if it is purely
visual. It must not make movement or damage decisions.

5. ANIMATION AND AUDIO SLOTS
----------------------------

Set IDs only in `Level 2 Pool Foam Configuration`:
  AnimationIds.Primary / AnimationIds.Secondary:
    Idle, Walk, Caught, Hunt, Attack, Collapse
  AudioIds.Primary / AudioIds.Secondary:
    Idle, Walk, Caught, Hunt, Attack, Collapse

Primary currently has one reviewed locomotion clip:
  PoolFoamPrimary_WalkAnimation = rbxassetid://75270256720943

Walk uses that ID, and Hunt resolves to the same Walk track when Hunt is blank.
The adapter pauses that track with AdjustSpeed(0), so a watched rig holds the
caught walking pose and resumes at the same TimePosition. Missing optional state
IDs never grant gameplay authority; animation markers are cosmetic only.
At the start of each Level 2 build, the server copies the six known audio slots
per entity into ReplicatedStorage["Level 2 Pool Foam Audio"] as StringValues.
The client accepts only those known replicated slots and never an arbitrary
SoundId supplied in a remote payload.

Suggested state mapping for final animation names:
  Idle     submerged / nearly motionless foam
  Walk     minimal off-camera crawl
  Caught   the small, unmistakable seen-moving step then freeze
  Hunt     readable fast asymmetric flow
  Attack   optional cosmetic contact-death presentation; the server kill is immediate
  Collapse withdraw back to water

6. SAFE ART-SWAP CHECKLIST
--------------------------

1. Keep the final art at the exact Primary template path above.
2. Set Root/PrimaryPart, remove imported scripts and prompts, and configure
   collisions according to the contract.
3. Verify the supplied Walk ID loads before adding any optional state animation.
4. Verify all five Kids rooms receive a unique Primary_01..Primary_05 clone.
5. Confirm watched movement lasts 0.50 seconds, then pose/time remain fixed.
6. Confirm looking away resumes the held track rather than restarting at zero.
7. Confirm watched close contact stays safe, including throughout the 0.50-second
   reveal overrun; turning away inside 5.5 studs then kills immediately, including
   through a ForceField.
8. Manually verify every behaviour above before removing any remaining
   proxy assets -- Pool Foam has no automated test suite yet (CLAUDE.md).

The temporary proxies are intentionally replaceable art, not a second gameplay
implementation. Do not edit controller code merely to swap the final rig.
]]

return {}
