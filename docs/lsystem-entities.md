# Entity & feature authoring (`entity.txt`, `features.txt`)

How to build a voxel creature or plant from an L-system. Placement is deterministic
math (`segmentTransform` in `matrix.d`, the turtle in `turtlegfx.d`/`lsystem.d`), so
following these rules makes parts connect, feet land, and faces not z-fight. Proportions
and animation still want one visual pass in-engine.

## Frame & the brush box
- `+Z` = front, `+Y` = up, ground at `Y=0`. Set `[FACING:180.0]`.
- Every brush is a unit cube put through `segmentTransform(pos, R, radius, length, depth)`:
  `translate(pos) · R · translate([0, length/2, 0]) · scale([radius, length, depth])`.
- Local axes: **X** = `radius` (width, `±radius/2`), **Y** = `length` (the **heading/growth**
  axis, **base-anchored** `0→length`), **Z** = `depth` (front/back, `±depth/2`; defaults to
  `radius`). The box grows up from its base at the cursor, then `R` (the turtle orientation)
  rotates it about that base.
- `R`'s columns are where each local axis points in the world: X→`R[0..2]`,
  **Y (heading)→`R[4..6]`**, Z→`R[8..10]`.

## Names & symbols
Tokens in `[AXIOM]`/`[RULE]`/`[CLIP]` strings are whitespace-optional. A run of non-reserved,
non-`{` characters is one **name** — multi-character and case-sensitive (`Leg`, `AntlerBeamL`,
`Trunk`). A name needs either a `[BRUSH]` or a `[RULE]`, else it's a validation error.

Reserved glyphs — `RESERVED = "()~%|+-&^<>"`:

| glyph | kind | meaning |
|-------|------|---------|
| `(` `)` | branch | push / pop turtle state; parts inside don't move the outer cursor |
| `~` | move | step one `LSYSTEM_GAP` along the heading, no draw (in a clip: advance one time step) |
| `+` `-` | turn | yaw ∓ about local Z (`LSYSTEM_YAW`) — steers the heading left/right |
| `&` `^` | turn | pitch about local X (`LSYSTEM_PITCH`); `&`→toward +Z, `^`→toward −Z |
| `<` `>` | turn | roll ± about the heading (`LSYSTEM_ROLL`) — spins in place, does **not** steer |
| `%` | modifier | halve the turn-angle scale for the rest of this branch (`%%` = ¼), restored on `)` |
| `\|` | modifier | draw the next brush world-up (ignore the heading); advance still follows the heading |

Only pitch/yaw change the heading; roll only spins around it. Idioms: `(&&Leg)` = leg
(pitch 180° → straight down), `(^Tail)` = point backward, `(\|Spike)` = stand a part up
regardless of the march direction.

## Parametric growth `{n}` (plants, recursive limbs)
A name may carry an integer parameter: `Trunk{n}`, `Wood{5}`. Rules gate on the matched
module's **own** `n` via a `[nMin:nMax)` window, and productions rewrite `n` with `{n-1}`,
`{n+1}`, or a literal.

- `[RULE:pred:production:weight]` — weighted rewrite, rolled per-uid. Weights are relative.
- `[RULE:pred:production:weight:nMin]` — window `[nMin, ∞)`.
- `[RULE:pred:production:weight:nMin:nMax]` — window `[nMin, nMax)`.

The axiom seeds `n` (feature `HEIGHT_MIN/MAX`; entities default to `1`). Because the window is
on the module's remaining count, morphology can key off *distance to the tip* — leaves low,
flowers only in the final tiers — independent of total size.

```
[AXIOM:Trunk{n}]
[RULE:Trunk:Wood{n} Trunk{n-1}:80:1]                   # grow while n >= 1
[RULE:Trunk:Wood{n}<(+Trunk{n-1})(-Trunk{n-1}):6:1]    # occasional fork
[RULE:Trunk:Wood{n} Bud:100:0:1]                       # cap at n == 0
```

## Brushes
`[BRUSH:name:Mesh:radius:length:advance:kv…]`

- `Mesh` (`makePrimitive`): `Cube`, `Cylinder`, `Cone`, `Sphere`, `Capsule`, `Torus`,
  `Icosahedron`; any other name loads a model asset.
- `advance`: `true` moves the cursor after drawing (turtle-stacked segments); `false` for
  offset-placed details (the normal case for animals).
- `kv` keys: `color=NAME` (from `colors.txt`, unknown → white) · `tint` (per-pawn colour) ·
  `substance=` / `texture=` · `offX/offY/offZ` (local draw offset) · `depth=` (Z half-extent) ·
  `render=false` (transform-only, no draw) · `taper=f` (radius grows `f` per unit of `{n}`) ·
  `jitterA=f` / `jitterL=f` (± per-individual jitter on following turns / on segment length,
  seeded by uid; latched from the last placed brush).

## Connectivity (two failure modes)
- **Detached**: neighbours must overlap ≥ **0.02** on the shared axis, or the part floats.
- **Z-fighting**: two visible faces must never be coplanar — inset or proud by ≥ **0.02**.

## Legs (the rule that bites first)
- Draw with `&&`: `(&&LegBL)(&&LegBR)(&&LegFL)(&&LegFR)`. `&&` pitches 180° → straight down.
- **Foot sits on the ground iff `offY = -length`.** Under `&&`, world position is
  `(offX, -offY, -offZ)` (note `offZ` flips). Sink the leg top *inside* the body, not flush.
- Quad layout: `offX ±`, `offZ ±` (back = `-offZ`, front = `+offZ`), equal radius/length.

## Axiom structure
- Body at the root; put every other part in its own `()` so it parents to the body and
  animating one part never drags its siblings.
- Chain without `()` only for a real parent→child bone chain (head→snout→nose).
- Offset-animal boilerplate: `[LSYSTEM_YAW:90][LSYSTEM_PITCH:90][LSYSTEM_GAP:0.15]`.

## Per-individual variation
A nonterminal + weighted `[RULE]`s, rolled once per pawn `uid`, gives each individual a
signature (antler style, beard length, crest). Put the nonterminal in the axiom (often
`(Style)`); an empty production = feature absent. Every symbol a rule can produce needs a
`[BRUSH]`.

## Animation & clips
- `[CLIP:name:axiom:trigger:fps:turn]` — `trigger=moving` marks the walk clip, else idle.
  **First-match selection**: exactly one walk and one idle clip ever play; extra clips are dead
  weight. Put idle *variety* in `[CRULE:pred:production:weight]` variants of the single idle clip.
- `[POSE:clipSym:targetBrush:orient:axis]` — a clip symbol drives every bone of `targetBrush`.
  `orient=side` mirrors L/R by the bone's X sign; `axis` ∈ `X`/`Y`/`Z` (empty = cursor swing).
  **Match the turn axis to the pose axis** or the angle is unpredictable: `&`/`^`→X, `<`/`>`→Y,
  `+`/`-`→Z; resulting angle = (turn-symbol count) × clip `turn`.
- **Bind pose = the static axiom.** Clips rotate bones relative to bind; an un-posed bone stays
  at bind. Build the rest shape into bind, animate only the difference.
- Standard quadruped gait (change only the trailing fps):
  `[CLIP:walk:LegBL LegFL LegBR LegFR ~ &&LegBL&&LegFR^^LegBR^^LegFL ~ …:moving:8:10]`
  with `[POSE:LegBL:LegBL:side]` … per leg.

## Bones vs. cloud cubes (automatic)
Bone-ness is **inferred**, never authored (`inferBones`, `skeleton.d`): a node is an animated
**bone** iff its symbol is a `[POSE]` target in some clip, or it's an ancestor of one; the root is
always a bone. Every other node — eyes, nose, antler tines, studs, fur — is a static **cloud cube**
that rides its nearest bone ancestor at a baked offset, costing **no** bone-palette slot and no
per-frame transform. This decouples cube count from bone count (hundreds of cubes over ~10 bones);
the fps window shows `bones` vs `static`. Cloud cubes keep their own size and colour but inherit the
bone's animation. Author normally — anything you don't pose becomes a cloud for free.

## Rotated appendages (tail fans, lifting wings)
Give the appendage a hidden **pivot bone** and parent it: `(Pivot (^Feather)(^Feather) …)`. A pose
on the pivot lifts the whole thing; per-feather poses fan it. The pivot and the appendage bases must
share a world position or it detaches when rotated (in a `^` frame, feather `offZ` is world-height,
`offY` is world back-distance → set pivot `offY` = feather `offZ`, pivot `offZ` = feather `offY`).

## Required metadata
`[MOVE_SPEED:x][DIET:y]`, `[SCALE:s][SCALE_VARIANCE:v][OFFSET_Y:0.0][FACING:180.0]`,
`[SPAWN_ON:Terrain]…`, `[NOISE_THRESHOLD:n]`, `[HASH_SEED1][HASH_SEED2][HASH_MOD][HASH_REM]`.
`HASH_*` seed spawn placement only; the skeleton/variation is seeded by pawn `uid`
(`hash = uid*2654435761`). Features use `[HEIGHT_MIN][HEIGHT_MAX]` instead of `MOVE_SPEED/DIET`.

## Flat panels (wings, fins, plates)
A panel's flat face is perpendicular to its **thin axis** (smallest of radius/length/depth), and
faces wherever that axis's `R` column points. Easiest: draw with `\|` (worldUp, `R = identity`,
local axes = world axes) and size directly — flat-up → thin `length` (`0.16:0.03:0.16`); flat on a
flank → thin `radius` (`0.03:0.16:0.16`); facing front → thin `depth` (`0.16:0.16:0.03`). Without
`\|`, the thin axis is rotated by preceding turns — compute where it lands (trace corners through
`R`), don't eyeball. A centerline trace verifies *reach* (legs, tails, spars) but nothing about a *face*.

## Checklist
1. Body at the root; every other part in its own `()`.
2. Legs with `&&` and `offY = -length`; leg tops sunk into the body.
3. Each part overlaps its neighbour ≥ 0.02; no coplanar faces.
4. Reuse the standard walk gait; pick one part to sway for idle.
5. Optional: nonterminal + `[RULE]`s for variety; `[CRULE]` for idle variety; `{n}` for growth.
6. Build in-engine and eyeball proportions/animation.

## Minimal template
```
[ENTITY:Newbeast]
  [MOVE_SPEED:1.5][DIET:Berry]
  [SCALE:0.7][SCALE_VARIANCE:0.1][OFFSET_Y:0.0][FACING:180.0]
  [SPAWN_ON:Grass01][SPAWN_ON:Grass02]
  [NOISE_THRESHOLD:0.80]
  [HASH_SEED1:2654435761][HASH_SEED2:40503][HASH_MOD:50][HASH_REM:7]
  [LSYSTEM_YAW:90][LSYSTEM_PITCH:90][LSYSTEM_GAP:0.15]
  [AXIOM:Body(Head)(Tail)(&&LegBL)(&&LegBR)(&&LegFL)(&&LegFR)]

  [CLIP:walk:LegBL LegFL LegBR LegFR ~ &&LegBL&&LegFR^^LegBR^^LegFL ~ ^^LegBL^^LegFR&&LegBR&&LegFL ~ ^^LegBL^^LegFR&&LegBR&&LegFL ~ &&LegBL&&LegFR^^LegBR^^LegFL:moving:8:10]
    [POSE:LegBL:LegBL:side]
    [POSE:LegBR:LegBR:side]
    [POSE:LegFL:LegFL:side]
    [POSE:LegFR:LegFR:side]
  [CLIP:idle:Head ~ +Head ~ -Head ~ -Head ~ +Head::4:2.0]
    [POSE:Head:Head:]

  [BRUSH:Body:Cube:0.34:0.30:false:color=tan:offY=0.20:offZ=0.00:depth=0.50]
  [BRUSH:Head:Cube:0.22:0.22:false:color=tan:offY=0.22:offZ=0.34:depth=0.24]
  [BRUSH:Tail:Cube:0.06:0.10:false:color=tan:offY=0.26:offZ=-0.30:depth=0.10]
  [BRUSH:LegBL:Cube:0.10:0.24:false:color=tan:offX=-0.16:offY=-0.24:offZ=-0.18:depth=0.11]
  [BRUSH:LegBR:Cube:0.10:0.24:false:color=tan:offX=0.16:offY=-0.24:offZ=-0.18:depth=0.11]
  [BRUSH:LegFL:Cube:0.10:0.24:false:color=tan:offX=-0.16:offY=-0.24:offZ=0.18:depth=0.11]
  [BRUSH:LegFR:Cube:0.10:0.24:false:color=tan:offX=0.16:offY=-0.24:offZ=0.18:depth=0.11]
```
Legs are posed → bones; `Head`/`Tail` and any detail are inferred cloud cubes. Feet at 0
(`offY = -length`); head/tail overlap the body ≥ 0.02; head sways in idle.
