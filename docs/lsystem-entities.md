# L-system entities (`entity.txt`, `features.txt`)

Voxel creatures/plants from an L-system. Placement is deterministic (`segmentTransform` in
`matrix.d`, turtle in `turtlegfx.d`/`lsystem.d`). Animals are **walked HLU skeletons**: posed
parts are *bones* walked to their joint; everything else is a *cloud* offset from its nearest bone.

## Frame
- `+Z` front, `+Y` up, ground `Y=0`. Model space = world space (heading `atan2(-d[0], d[2])`); no `[FACING]`.
- Brush = unit cube via `segmentTransform(pos,R,radius,length,depth)` = `translate(pos)·R·translate([0,length/2,0])·scale([radius,length,depth])`.
- Local axes: X=`radius` (width), **Y=`length`=heading, base-anchored 0→length**, Z=`depth`. `R` cols: X→`R[0..2]`, heading Y→`R[4..6]`, Z→`R[8..10]`. `~`/`move` steps the heading column.

## Glyphs (`RESERVED="()~%|+-&^<>"`)
| glyph | meaning |
|---|---|
| `(` `)` | push/pop turtle state |
| `~` | step heading, no draw. `~` = `gap` (default 1); `~{d}` = step `d` |
| `+`/`-` | yaw ∓ about local Z (default 90° or `+{φ}`) |
| `&`/`^` | pitch about local X (default 90° or `&{θ}`); `&`→+Z, `^`→−Z |
| `<`/`>` | roll ± about heading (spins, doesn't steer) |
| `%` | halve turn-scale for rest of branch, restored on `)` |
| `\|` | reset orientation to world-up (position unchanged) |

Names: runs of non-reserved/non-`{` chars, case-sensitive; each needs a `[BRUSH]`, `[RULE]`, or `[BONE]`.

## Heading law (solve a walk)
Turns post-multiply local; after `&{θ}+{φ}`, step `d` lands at `d·(−sinφ, cosφcosθ, cosφsinθ)`.
Inverse — to reach `(x,y,z)`: `θ=atan2(z,y)`, `φ=atan2(−x,hypot(y,z))`, `d=hypot(x,y,z)` → `&{θ}+{φ}~{d}`.
Pure up = `~{d}`; pure lateral = `+{±90}~{d}`.

## Brushes & bones
`[BRUSH:name:Mesh:radius:length:kv…]` — Mesh ∈ Cube/Cylinder/Cone/Sphere/Capsule/Torus/Icosahedron/Pyramid (else asset).
kv: `color=` · `tint` · `substance=`/`texture=` · `offX/offY/offZ` · `depth=` · `render=false` · `taper=f` · `jitterA=f`/`jitterL=f`. No `advance` field — `~` is the only mover; a brush draws at `cursor+offset`, never moves it.
`[BONE:name]` — meshless poseable joint (hip sockets, tail/wing pivots).

## Connectivity
Overlap neighbours ≥ 0.02 (else detached); never coplanar visible faces (inset/proud ≥ 0.02).

## Walked skeleton
Body = root bone at **origin** (no `offY`/`offZ`). Bones walked; clouds offset.
- **Leg**: `(walk | HipXX && LegXX)`. Walk to hip `(offX,−offY,−offZ)`; `\|` **before** the hip (resets the tilted arrival frame, else gait swings sideways); `HipXX` is `[BONE]`; `&&` drops the leg.
- **Chain** (Thigh→Shank→Foot): `(walkT | && Thigh | walkS | && Shank | walkF | && Foot)` — each walk is the child−parent delta; `\|` before each segment.
- **Drop rule** (body → origin): body-relative parts `offY −= drop`; `&&`-frame parts `offY += drop` (world-Y = −offY there); legs reaching the ground **don't** drop (`footY` seats the pawn); never shift `depth`.

## Bones vs clouds (inferred)
Bone iff its symbol is a `[POSE]` target or ancestor of one; root always bone. Everything else = cloud cube riding its nearest bone ancestor at a baked offset (no palette slot, no per-frame cost). Cloud offset = relative to that bone (in the bone's frame if `&&`/`^`).

## Rotated appendages
Walk a pivot bone to the appendage base: `(walkPivot | Pivot Feather Feather …)`. Anchoring the pivot at the base fixes the bind position (un-posed clips render at bind, else it jumps between clips). Pose the pivot to swing all; per-feather poses fan.

## Clips
`[CLIP:name:axiom:trigger:steps:fps]` — `trigger=moving` = walk clip, else idle; first-match, one of each plays. Idle variety via `[CRULE:pred:prod:weight]`.
`[POSE:clipSym:target]` — drives that bone; `stepLocal` composes all its tracks as cursor-swing in the bone's frame, so the clip turn glyph is the swing axis (`&`/`^` pitch, `<`/`>` roll, `+`/`-` yaw), angle = glyph-count × clip turn. Bind = static axiom; animate only the difference.
Standard gait: `[CLIP:walk:LegBL LegFL LegBR LegFR ~ &&LegBL&&LegFR^^LegBR^^LegFL ~ …:moving:8:10]` + `[POSE:LegBL:LegBL]` per leg.

## Growth `{n}` (plants/recursive)
Name carries int `n`; rules gate on `n` window and rewrite it.
`[RULE:pred:prod:weight]` / `:weight:nMin` `[nMin,∞)` / `:weight:nMin:nMax` `[nMin,nMax)`. Axiom seeds `n` (feature `HEIGHT_MIN/MAX`, entities default 1). Window keys on distance-to-tip.
```
[RULE:Trunk:Wood{n} Trunk{n-1}:80:1]                 # grow n>=1
[RULE:Trunk:Wood{n}<(+Trunk{n-1})(-Trunk{n-1}):6:1]  # fork
[RULE:Trunk:Wood{n} Bud:100:0:1]                     # cap n==0
```

## Variation
Nonterminal + weighted `[RULE]`s, rolled once per uid (empty production = absent). Every producible symbol needs a `[BRUSH]`.

## Flat panels
Flat face ⟂ thin axis (min of radius/length/depth). Draw with `\|` and size directly: flat-up thin length `0.16:0.03:0.16`; flank thin radius `0.03:0.16:0.16`; front thin depth `0.16:0.16:0.03`. Without `\|` the thin axis rotates with prior turns.

## Metadata
`[MOVE_SPEED][DIET]`, `[SCALE][SCALE_VARIANCE][OFFSET_Y:0.0]`, `[SPAWN_ON]…`, `[NOISE_THRESHOLD]`, `[HASH_SEED1/2][HASH_MOD][HASH_REM]` (spawn only; skeleton seeded by uid). Features use `[HEIGHT_MIN/MAX]`. No `[FACING]`/`[LSYSTEM_*]`.

## Template
```
[ENTITY:Newbeast]
  [MOVE_SPEED:1.5][DIET:Berry]
  [SCALE:0.7][SCALE_VARIANCE:0.1][OFFSET_Y:0.0]
  [SPAWN_ON:Grass01][SPAWN_ON:Grass02]
  [NOISE_THRESHOLD:0.80]
  [HASH_SEED1:2654435761][HASH_SEED2:40503][HASH_MOD:50][HASH_REM:7]
  [AXIOM:Body(Tail)(&{71}+{29}~{0.30} | HipBL && LegBL)(&{71}+{-29}~{0.30} | HipBR && LegBR)(&{-71}+{29}~{0.30} | HipFL && LegFL)(&{-71}+{-29}~{0.30} | HipFR && LegFR)(&{40}~{0.42} | Head(Snout)(EyeL)(EyeR))]
  [BONE:HipBL][BONE:HipBR][BONE:HipFL][BONE:HipFR]
  [CLIP:walk:LegBL LegFL LegBR LegFR ~ &&LegBL&&LegFR^^LegBR^^LegFL ~ ^^LegBL^^LegFR&&LegBR&&LegFL ~ ^^LegBL^^LegFR&&LegBR&&LegFL ~ &&LegBL&&LegFR^^LegBR^^LegFL:moving:8:10]
    [POSE:LegBL:LegBL][POSE:LegBR:LegBR][POSE:LegFL:LegFL][POSE:LegFR:LegFR]
  [CLIP:idle:headSway ~ +headSway ~ -headSway ~ -headSway ~ +headSway::4:2.0]
    [POSE:headSway:Head]
  [BRUSH:Body:Cube:0.34:0.30:color=tan:depth=0.50]
  [BRUSH:Head:Cube:0.22:0.22:color=tan:depth=0.24]
  [BRUSH:Snout:Cube:0.12:0.10:color=seashell:offY=0.02:offZ=0.18:depth=0.14]
  [BRUSH:EyeL:Cube:0.05:0.05:color=black:offX=-0.10:offY=0.06:offZ=0.10:depth=0.05]
  [BRUSH:EyeR:Cube:0.05:0.05:color=black:offX=0.10:offY=0.06:offZ=0.10:depth=0.05]
  [BRUSH:Tail:Cube:0.06:0.10:color=tan:offY=0.06:offZ=-0.30:depth=0.10]
  [BRUSH:LegBL:Cube:0.10:0.24:color=tan:depth=0.11]
  [BRUSH:LegBR:Cube:0.10:0.24:color=tan:depth=0.11]
  [BRUSH:LegFL:Cube:0.10:0.24:color=tan:depth=0.11]
  [BRUSH:LegFR:Cube:0.10:0.24:color=tan:depth=0.11]
```
Legs+Head posed → bones (walked); Snout/Eyes → clouds off Head; Tail → cloud off Body.