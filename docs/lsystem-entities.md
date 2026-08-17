# Entity authoring rules ('entity.txt')

Conventions for building a voxel creature. Derived from `segmentTransform` (matrix.d),
the turtle (`turtlegfx.d` / `lsystem.d`), and the clip selector (`skeleton.d:80`).
Placement is deterministic math — follow these and parts connect, feet land, and
faces don't z-fight. Proportions still want one visual pass in engine.

## Frame & the brush box
- `+Z` = front (nose/head), `+Y` = up, ground plane at `Y=0`. Always set `[FACING:180.0]`.
- `[BRUSH:sym:Cube:radius:length:advance:color=NAME:offX=..:offY=..:offZ=..:depth=..]`
  - `radius` = X width, `length` = Y (up) extent, `depth` = Z (front-back); `depth` defaults to `radius`.
  - **Base-anchored:** the box spans `Y∈[offY, offY+length]`, `X∈offX±radius/2`, `Z∈offZ±depth/2`. It grows UP from `offY`.
  - `advance:false` for all offset-placed parts (normal case). `advance:true` only for turtle-stacked rigs (see Dwarf).
  - `color=NAME` from `colors.txt` (unknown name silently → white). `tint` = per-pawn colour.

## Legs — the rule that bites first
- Legs are drawn with `&&`: `(&&o)(&&p)(&&q)(&&r)`. `&&` pitches 180°, so the leg hangs straight down.
- **The foot sits on the ground iff `offY = -length`.** No exceptions. (`foot_y = -offY - length = 0`.)
- Under `&&`, a leg's world position is `(offX, -offY, -offZ)` — note `offZ` flips sign.
- Quad layout: four legs, `offX ±`, `offZ ±`, equal `radius`/`length`. Leg top must sit *inside* the body
  (`-offY` above the body's base), not flush with it — flush = z-fight.

## Connectivity — the two failure modes
- **Detached** (part floats): neighbours must overlap by **≥ 0.02** on the shared axis. Any gap and it floats.
- **Z-fighting** (shimmer): two visible faces must never be coplanar. Keep each part inset or proud of its
  neighbour by **≥ 0.02**. Equal face planes fight.

## Symbol reference (axiom / rule / clip strings)

Every character in an `[AXIOM]`, `[RULE]` production, or `[CLIP]` string is one of these.
Case-sensitive. A letter with neither a `[BRUSH]` nor a `[RULE]` (and not listed below) is a
compile-time validation error.

| Symbol | Kind | Meaning |
|--------|------|---------|
| `(` | branch | push the turtle state (position + orientation + angle-scale) |
| `)` | branch | pop — restore to the matching `(`; parts drawn inside don't move the outer cursor |
| `f` | move | step one `LSYSTEM_GAP` along the heading, no draw. In a clip: advance one time step |
| `+` `-` | turn | yaw ∓ about local **Z** (`LSYSTEM_YAW`) — steers heading left/right |
| `&` `^` | turn | pitch about local **X** (`LSYSTEM_PITCH`). `&` → +Y turns toward +Z (fwd); `^` → toward −Z (back) |
| `<` `>` | turn | roll ± about local **Y** = the heading (`LSYSTEM_ROLL`) — twists in place, does **not** steer the cursor |
| `%` | modifier | halve the turn-angle scale for the rest of this branch; composes (`%%` = ¼), restored on `)` |
| `\|` | modifier | draw the **next** brush world-up, ignoring the heading; `advance` still follows the heading |
| `X` | nonterminal | reserved growth seed — needs no `[BRUSH]`; conventional axiom for recursive rules |
| space / tab / newline | — | ignored; use freely for readability |
| any other letter | content | place its `[BRUSH]`, or expand its `[RULE]` |

Notes:
- **Heading vs. steering.** The fwd/back/down labels assume the default start heading `+Y`; after
  turns the heading changes. `&`/`^`/`+`/`-` change the heading (steer the march); `<`/`>` only spin
  around it. To march a grid over a surface, step with `f` after a `&`/`^`/`+`/`-`, never `<`/`>`.
- **Two common idioms.** `(&&o)` = leg (pitch 180° → straight down). `(^tail)` = point a part backward.
- **Turn magnitude** = the axis angle (`LSYSTEM_YAW`/`PITCH`/`ROLL`, or all three via `LSYSTEM_ANGLE`)
  × the current `%` scale. In clips all three equal the clip's `turn`.
- **`|` is what makes surface coats work:** roll the turtle flat so `f` marches across a surface, and
  drop `(|s)` at each node so every spike stands up regardless of the march direction.

## Grammar & clip tokens

| Token | Meaning |
|-------|---------|
| `[BRUSH:s:Mesh:radius:length:advance:kv…]` | Define a drawable part. `kv` = `color=NAME` / `tint` / `offX/offY/offZ` / `depth` / `render=false`. `advance` moves the cursor after drawing (segments); `false` for offset-placed details |
| `[RULE:X:prod:weight]` | Weighted rewrite of nonterminal `X`, rolled per-uid. Weights are relative |
| `[RULE:X:prod:weight:genMin:genMax]` | …with a generation window. `@` in a bound = the budget (`LSYSTEM_ITER`) → the rule recurses up to the budget (trees, dense coats) |
| `[AXIOM:…]` | Start string |
| `[LSYSTEM_ANGLE:d]` | Set yaw = pitch = roll = `d`° |
| `[LSYSTEM_YAW/PITCH/ROLL:d]` | Set one axis' turn magnitude |
| `[LSYSTEM_GAP:g]` | `f` step distance |
| `[LSYSTEM_ITER:n]` | Rewrite budget: caps `@`-windowed recursion; drives per-uid density |
| `[CLIP:name:axiom:trigger:fps:turn]` | Animation. `trigger=moving` = walk, else idle. Only the **first** clip of each kind ever plays |
| `[CRULE:X:prod:weight]` | Like `RULE`, scoped to the enclosing clip (per-uid idle variety) |
| `[POSE:clipSym:targetBrush:orient:axis]` | Map a clip symbol to a bone. `orient=side` mirrors L/R by the bone's X sign; `axis` ∈ `X`/`Y`/`Z` (empty = cursor swing) |

**Mesh primitives** (`makePrimitive`): `Cube`, `Cylinder`, `Cone`, `Sphere`, `Capsule`, `Torus`,
`Icosahedron`. Any other name loads a model asset of that name.

## Axiom structure
- `[AXIOM:C(part)(part)(&&leg)...]` — body `C` at the **root**; put every other part in its own `()` branch
  so it parents to the body and animating one part never drags its siblings.
- Chain without `()` only when you want a real parent→child bone chain (head→snout→nose).
- Boilerplate for offset-placed animals: `[LSYSTEM_YAW:90][LSYSTEM_PITCH:90][LSYSTEM_GAP:0.15]`.

## Per-individual variation (rules)
- `[RULE:X:production:weight]`. Put nonterminal `X` in the axiom (usually `(X)`); give 2–4 weighted productions
  of brush symbols. Rolled once per pawn `uid` → each individual differs (antlers, crest, beard, hair, tail size).
- Weights are **relative** (need not total 100). An empty production = feature absent.
- Productions may contain `()` and turn symbols. Every symbol a rule can produce must have a `[BRUSH]`.

## Animation
- **Clip selection is first-match** (`skeleton.d:80`): exactly one `moving` clip (walk) and one non-moving clip
  (idle) will ever play. Extra clips are dead weight. Put idle *variety* in `[CRULE]` variants of the single idle
  clip — the variant is rolled per `uid`, giving each pawn a signature idle.
- `[CLIP:name:axiom:trigger:fps:turn]`; trigger `moving` marks the walk clip.
- **Bind pose = the static axiom.** Clips rotate bones *relative to bind*; a bone not posed by the active clip
  stays at bind. → build the walk/rest shape into bind, animate only the difference.
- `[POSE:clipSym:targetBrush:orient:axis]`: `axis` `X`/`Y`/`Z` swings about that body axis; `side` mirrors L/R by
  the bone's X sign; empty axis = cursor swing. A pose targets a *symbol*, so it drives every bone of that symbol.
- **Match the turn axis to the pose axis** or the angle is unpredictable: `&`/`^`→X, `<`/`>`→Y, `+`/`-`→Z.
  Resulting angle = (turn-symbol count) × clip `turn`.
- Standard quadruped gait — copy verbatim, only change the trailing fps:
  `[CLIP:walk:oqpr f &&o&&r^^p^^q f ^^o^^r&&p&&q f ^^o^^r&&p&&q f &&o&&r^^p^^q:moving:8:10]`
  with `[POSE:o:o:side]` … `[POSE:r:r:side]`.
- Standard one-part idle sway: `[CLIP:idle:X f +X f -X f -X f +X::4:2.0]` + `[POSE:X:target:]`.

## Rotated appendages (tail fans, wings that lift)
- To swing an appendage about a hinge, give it a hidden **pivot bone** and parent the appendage to it:
  `(Pivot (^feather)(^feather) …)`. Then a single pose on the pivot lifts the whole thing; per-feather poses fan it.
- **Pivot rule:** the pivot bone and the appendage's bases must share the same world position, or the appendage
  detaches the moment it rotates. (In a `^` frame, a feather's `offZ` is world-height and `offY` is world
  back-distance — so set pivot `offY` = feather `offZ`, pivot `offZ` = feather `offY`.)
- A part of length `L` swung up about a pivot dips to `pivot - L` mid-swing. Keep `L` short enough, or the pivot
  high enough, that it clears the body and floor.

## Required metadata (per entity)
`[MOVE_SPEED:x][DIET:y]`, `[SCALE:s][SCALE_VARIANCE:v][OFFSET_Y:0.0][FACING:180.0]`,
`[SPAWN_ON:Terrain]…`, `[NOISE_THRESHOLD:n]`, `[HASH_SEED1:..][HASH_SEED2:..][HASH_MOD:..][HASH_REM:..]`.
`HASH_*` seed spawn placement only — the skeleton/variation is seeded by pawn `uid` (`hash = uid*2654435761`).

## Checklist
1. Body `C` at the root; every other part in its own `()`.
2. Legs with `&&` and `offY = -length`; leg tops sunk into the body.
3. Walk the parts: each overlaps its neighbour ≥0.02, no coplanar faces.
4. Reuse the standard walk gait; pick one part to sway for idle.
5. Optional: nonterminal + `[RULE]`s for per-individual variety; `[CRULE]` variants for idle variety.
6. Build in engine and eyeball proportions/animation.

## Minimal template
```
[ENTITY:Newbeast]
  [MOVE_SPEED:1.5][DIET:Berry]
  [SCALE:0.7][SCALE_VARIANCE:0.1][OFFSET_Y:0.0][FACING:180.0]
  [SPAWN_ON:Grass01][SPAWN_ON:Grass02]
  [NOISE_THRESHOLD:0.80]
  [HASH_SEED1:2654435761][HASH_SEED2:40503][HASH_MOD:50][HASH_REM:7]
  [LSYSTEM_YAW:90][LSYSTEM_PITCH:90][LSYSTEM_GAP:0.15]
  [AXIOM:C(H)(t)(&&o)(&&p)(&&q)(&&r)]

  [CLIP:walk:oqpr f &&o&&r^^p^^q f ^^o^^r&&p&&q f ^^o^^r&&p&&q f &&o&&r^^p^^q:moving:8:10]
    [POSE:o:o:side]
    [POSE:p:p:side]
    [POSE:q:q:side]
    [POSE:r:r:side]
  [CLIP:idle:h f +h f -h f -h f +h::4:2.0]
    [POSE:h:H:]

  [BRUSH:C:Cube:0.34:0.30:false:color=tan:offY=0.20:offZ=0.00:depth=0.50]
  [BRUSH:H:Cube:0.22:0.22:false:color=tan:offY=0.22:offZ=0.34:depth=0.24]
  [BRUSH:t:Cube:0.06:0.10:false:color=tan:offY=0.26:offZ=-0.30:depth=0.10]
  [BRUSH:o:Cube:0.10:0.24:false:color=tan:offX=-0.16:offY=-0.24:offZ=-0.18:depth=0.11]
  [BRUSH:p:Cube:0.10:0.24:false:color=tan:offX=0.16:offY=-0.24:offZ=-0.18:depth=0.11]
  [BRUSH:q:Cube:0.10:0.24:false:color=tan:offX=-0.16:offY=-0.24:offZ=0.18:depth=0.11]
  [BRUSH:r:Cube:0.10:0.24:false:color=tan:offX=0.16:offY=-0.24:offZ=0.18:depth=0.11]
```
Feet at 0 (`offY=-length=-0.24`); head/tail overlap the body ≥0.02; head sways in idle.
