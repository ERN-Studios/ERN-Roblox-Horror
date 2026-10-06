# The Reach: the easter egg behind the lobby's fence

Owner, 2026-10-06: at the DJ end of the lobby you can get over the fence; as soon as you are over there, big
glowing eyes come on in the dark and long, clammy arms "made in Blender" creep slowly toward you (or whoever is
nearest); if you do not jump back it takes hold of you and pulls you fast into the dark, where you die and respawn
in the lobby. Marker in the code: `TUNNEL_REACH_20261006`.

## What a player meets

- **The way over.** Two road cases on the back corner of the stage (stage deck -> low case -> tall stack). A jump
  from the tall stack clears the fence. Nothing else in the lobby is high enough and close enough.
- **Behind the fence.** The road and both pavements carry on for 64 studs behind the end wall. About a second
  after anyone is over, two eyes open far down the tunnel and the first hand sets out; the other three follow.
  They head for whoever is nearest to them, slowly at first and a little quicker for every second somebody has
  been over there, so nobody can dance round them for ever. Standing by the fence it takes about 19 seconds to be
  reached; standing 46 studs in, about 10 to 16.
- **The way back.** Three crates behind the fence, on the other side of the road from where you land (one, two and
  three high). Over the fence again and the hands stop, wait a moment and draw back; the eyes close.
- **Taken.** A hand that gets within 15 studs rears up (0.6 s, the last moment to be gone), comes down over the
  body, closes, lifts it and drags it into the dark; at 150 studs behind the wall the body dies. GameManager's own
  lobby respawn stands the player up at the spawn three seconds later. On the victim's screen the picture closes
  in during the pull, goes black, shows the eyes once from below, and comes back in the lobby.

## Where the code is

| What | Where |
|---|---|
| The place: fence height, the old unseen barriers switched off, ground behind the wall, cases, crates | `ServerScriptService.LobbyReimaginedPreview.Builder`, block `TUNNEL_REACH_20261006` |
| Who is over, where each hand is, who is taken, the kill; bakes the meshes | `ServerScriptService."Lobby Tunnel Reach"` |
| Eyes, arms, hands, the victim's screen | `StarterPlayerScripts."Lobby Tunnel Reach Client"` |
| State the server publishes | attributes on `ReplicatedStorage.LobbyTunnelReach` |
| Mesh templates (baked per server) | `ReplicatedStorage.LobbyTunnelReach.Meshes` |
| The meshes' numbers | `ServerStorage.LobbyTunnelReachSource` |

Every position is in the tunnel's own frame (`Frame` on the folder): x across, y up from the road, z = studs
behind the end wall. The fence is at z = -7.6, the ground ends at 64, the sheets of dark are at 70, 100, 128, 152
and 170, the shoulders are at 187.

Three things were in the way of "over the fence" and all three had to go: the fence's own collision was a sheet 30
studs high (it is 14.9 now, the height you see), the retired furniture pile's blockers still stood in the fence's
plane right up to the arch, and the end wall kept its cap. The Builder switches the last two off at this end only
(`OpenedForTunnelReach` on each part).

## The meshes

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/lobby_reach/build_reach.py
    python3 tools/lobby_reach/install_reach.py            # tries a real mesh asset first
    python3 tools/lobby_reach/install_reach.py --source   # or keep the numbers for the server to bake
    python3 tools/lobby_reach/push_scripts.py             # the two scripts and the Builder

`build_reach.py` makes nine pieces (three arm bones, an elbow knob, a palm, a finger joint, a thumb joint, a claw,
an iris) and writes `artifacts/lobby-reach-20261006/`: `blend/Lobby_Reach.blend` (the kit and one arm posed the way
the game poses it), `export/reach_meshes.json`, `preview/*.png`. Skin, veins, bruises, raw joints and nails are
vertex colours; there are no textures. Each piece looks down its own -Z and is centred on its box.

An arm is not one mesh. The client folds eight bones between a shoulder nobody sees and the wrist (the spare
length pushes the elbows off the straight line, alternately to either side), puts a knob on every elbow and poses a
palm with six digits of three joints. So there is no rig, no skinning and no animation asset.

`AssetService:CreateAssetAsync` answered "not available yet" on the day, so the meshes are not assets: the server
bakes them once per server from the numbers (about a second). If `install_reach.py` succeeds one day, it places
asset templates and removes the numbers, and the server finds nothing left to bake.

## Things learned

- **A cap wound the wrong way is a hole in the game.** Blender draws both sides of a face, Roblox does not: the
  first build's knuckles were open. `Mesh.fan` winds each cap against the body it closes and `finish` asserts
  that every edge is used once in each direction.
- **Vertex colours come out stronger in the game than in the render.** The second palette (green, violet and red
  in equal parts) looked like camouflage; the skin is one dead grey now with the rest as accents.
- **Vertex colours work on a Neon MeshPart**: the iris is one mesh, painted from the pupil outward.
- **The eyes cannot be further in than the fourth sheet of dark** (152): behind it 8% of them gets through.
  `EyesFar` 148, `EyesNear` 96.
- **A lobby avatar jumps 7.3 studs** (JumpPower 50; measured), not the 6.4 that v squared over 2g gives.
- **Screenshots of something fast**: an `execute_luau` call that is in flight when a LocalScript switches the
  camera to Scriptable resets the camera when it returns. Schedule the test with `task.spawn` in a call that
  returns at once, then take captures. `workspace.DevTunnelReachStare = <seconds>` (Studio) holds the victim's
  last picture; the client publishes its phase as the player attribute `TunnelReachPhase`.
- **Posing one hand for a look**: on the Client, set `Awake`, `S<n>`, `T<n>`, `At<n>` (and `V<n>` to a UserId for
  the grip) on `ReplicatedStorage.LobbyTunnelReach`. The server only rewrites an arm's attributes when that arm
  moves, so a resting arm keeps what you gave it.

## Not done

- **No sound.** The owner did not ask for any, uploading audio needs their hands (Asset Manager), and no other
  level's sounds may be borrowed.
- Not tested: more than one player at once (hands choosing between bodies, one player watching another taken),
  phones, the frame rate on real hardware.
