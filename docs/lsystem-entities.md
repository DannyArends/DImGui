# L-System Entities & Features — Authoring Reference

Raw format for **features** (`data/raws/features.txt`) and **entities** (`data/raws/entity.txt`).
Both share one parser (`rawHandler`) and one struct (`RawT`); they differ only in which
metadata tokens apply (features never use `MOVE_SPEED`, entities never use `HEIGHT_MIN`).
Tables build at compile time (CTFE). Every construct maps to a case in `src/game/raws.d`
or a glyph handler in `src/base/lsystem.d` / `src/engine/turtlegfx.d`.

## 1. Structure

Flat sequence of `[TOKEN:field:field:...]` brackets. `[FEATURE:Name]` / `[ENTITY:Name]`
open a block; following tokens accumulate into it until the next block tag. Fields are
`:`-separated; a field is a bare value (`Cube`) or `key=value` (`substance=Wood`).
`#` lines are comments. A block = **metadata** (§5) + **grammar** (§2) + **palette**
(brushes/bones, §3) + optional **clips** (§4).

## 2. Grammar

```
[AXIOM:<string>]                                             # start string, default "B"
[RULE:<pred>:<production>:<weight>[:<nMin>[:<nMax>]]]        # rewrite pred -> production
```

`<weight>` = relative probability among rules sharing a predecessor. `<nMin>`/`<nMax>`
gate the rule to modules whose growth param `n` is in `[nMin,nMax)` (defaults
`int.min`/`int.max`).

**Growth `{n}`:** a module carries an integer, e.g. `Trunk{n}`. `{expr}` in a production
is evaluated with the current `n` (`Trunk{n-1}`). Drives bounded recursion until a
terminating rule (empty production, or `nMax:0`) fires.

**Termination law:** a rule's predecessor must not reappear in its own production without
a `{n}` decrement toward termination. A non-decrementing self-reference (`[RULE:Neck:Neck Head]`)
spins to the safety cap and explodes geometry. `Trunk{n} -> ... Trunk{n-1}` is safe.

Feature axiom `n` seeds from `[HEIGHT_MIN/MAX]`; entities are usually fixed (no `{n}`).

## 3. Glyphs & palette

Expanded string lexes into glyphs (reserved chars) and modules (non-reserved runs,
optional `{n}`). `RESERVED="()~%|+-&^<>@"`, `PARAMETRIC="+-&^<>~"` (take a numeric `{arg}`).

| Glyph | Meaning |
|-------|---------|
| `(` `)` | push / pop turtle state (branch) + turn-scale |
| `~{d}` | step `d` along heading (+Y of frame); bare = `cfg.gap` |
| `&{θ}`/`^{θ}` | pitch about +X / −X (deg) |
| `+{φ}`/`-{φ}` | yaw about +Z / −Z (deg) |
| `<{ψ}`/`>{ψ}` | roll about +Y / −Y (deg) |
| `%` | halve turn-scale until `)` |
| `\|` | reset orientation to world-up (position kept) |
| `@{x;y;z}` | walk-to-point sugar → `&{θ}+{φ}~{d}` (§ below) |
| `Name`/`Name{n}` | place brush/bone if defined, else a grammar symbol |

**Heading law:** steps go along the +Y column of `rotate(orient)`. From world-up,
`&{θ}+{φ}` then step `d` lands at `(x,y,z)=d·(−sinφ, cosφcosθ, cosφsinθ)`. Turns
post-multiply (written order). `&`=+X `^`=−X `+`=+Z `-`=−Z `<`=+Y `>`=−Y.

**`@{x;y;z}`** rewrites (at expand time) to `&{θ}+{φ}~{d}` with
`θ=deg(atan2(z,y))`, `φ=deg(atan2(-x,sqrt(y²+z²)))`, `d=sqrt(x²+y²+z²)` — walks to
`(x,y,z)` in the current frame, identical to the three glyphs. `@{-0.14;0.04;0.16}` ==
`&{75.96}+{40.33}~{0.2163}`. Use for legible symmetry (`@{±0.14;0.04;±0.16}`); add `|`
after to reset heading.

**`[BONE:<symbol>]`** — meshless poseable joint; placed at the cursor, draws nothing,
targeted by poses.

**`[BRUSH:<Name>:<Mesh>:<sizeX;sizeY;sizeZ>[:key=value ...]]`** — `Mesh` is a primitive
(`Cube`,`Cylinder`,`Icosahedron`) or model (`watermelon`); size = local half-extents
(Cylinder: X=radius, Y=length, Z=depth). Keys:

| key | meaning |
|-----|---------|
| `substance=<Substance>` | material drawn; feature harvest keys on it |
| `textures={role=name;...}` | role→texture bindings (§6) |
| `color=<Colors>` | flat tint (named), used when no texture |
| `tint` | bare flag: use entity's per-instance colour |
| `off=<x;y;z>` | local draw offset [right,up,fwd] |
| `taper=<f>` | radius growth per unit `{n}` (0=uniform) |
| `food=<f>` | edibility (0=inedible) |
| `render=<bool>` | false = harvest-only drop, not shown growing |

```
[BRUSH:Wood:Cylinder:0.35;1.0;0.35:substance=Wood:textures={3D=Wood_02_base;2D=log}:taper=0.10]
[BRUSH:Nose:Cube:0.06;0.06;0.06:color=black:off=0;-0.02;0.20]
```

## 4. Clips (entities)

Secondary L-systems walked in **time**: advance a tick counter and write rotation
keyframes onto bones.

```
[CLIP:<name>[:<axiom>[:moving][:<tps>][:<duration>]]]   # moving=play while moving; tps=8; dur=25
  [CRULE:<pred>:<prod>:<weight>]                        # optional clip rewrite rules
  [POSE:<symbol>:<targetBone>]                          # bind a clip symbol to a bone
```

In the clip walk (`AnimSink`): `~` advances tick `t`; turn glyphs accumulate a *pending*
rotation; a pose symbol composes pending onto its cursor, appends `PoseKey(t, rot)` to
the target bone, clears pending.

```
[CLIP:walk:LegBL LegFL LegBR LegFR ~ &&LegBL&&LegFR^^LegBR^^LegFL ~ ^^LegBL^^LegFR&&LegBR&&LegFL:moving:8:10]
  [POSE:LegBL:LegBL][POSE:LegBR:LegBR][POSE:LegFL:LegFL][POSE:LegFR:LegFR]
```

## 5. Metadata (all optional; default in parens)

**Shared:** `[SPAWN_ON:<ResourceType>]` (repeatable), `[NOISE_THRESHOLD:<f>]` (0.92,
higher=rarer), `[HASH_SEED1/2:<u>]`, `[HASH_MOD/REM:<u>]` (0=unused), `[PROGRESS_RATE:<f>]`
(0.25), `[INTERACTION:<verb>]`, `[SOUND:<id>]`.

**Feature-only:** `[HEIGHT_MIN/MAX:<u>]` (1/1, seeds axiom `n`), `[TILE_PENALTY:<f>]` (0).

**Entity-only:** `[MOVE_SPEED:<f>]` (1), `[DIET:<name>]`, `[HUNGER_DECAY/THIRST_DECAY:<f>]`
(0), `[SCALE:<f>]` (1), `[SCALE_VARIANCE:<f>]` (0), `[OFFSET_Y:<f>]` (0), `[HOP:<f>]` (0).

## 6. Textures

`textures={role=name;role=name;...}` — open-ended roles read via `texOf(role)`. Common:
`3D` (world/model), `2D` (inventory icon), `skin` (item mesh), `filled` (container-full).
Bare names resolve against texture dirs (`log`→`log.png`, incl. subfolders). Only `color=`
+ no `textures` = legitimately textureless. Give an explicit `2D=` where the inventory
icon must differ from the 3D atlas (a model atlas is unusable as a flat 2D icon).

## 7. Examples

```
[FEATURE:Oak]
  [SPAWN_ON:Grass01][SPAWN_ON:Forest01][NOISE_THRESHOLD:0.65]
  [HASH_SEED1:2654435761][HASH_SEED2:2246822519][HASH_MOD:20][HASH_REM:0]
  [HEIGHT_MIN:5][HEIGHT_MAX:14][TILE_PENALTY:5000.0][PROGRESS_RATE:0.25]
  [INTERACTION:Fell][SOUND:DM-CGS-22]
  [AXIOM:Trunk{n}]
  [RULE:Trunk:Wood{n} ~{0.95} Trunk{n-1}:80:1]
  [RULE:Trunk:Wood{n} ~{0.95} <{25}(+{25}Trunk{n-1})(-{25}Trunk{n-1}):6:1]
  [RULE:Trunk:Wood{n} ~{0.95} Bud:8:1]
  [RULE:Trunk:Wood{n} ~{0.95} Bud:100:0:1]
  [RULE:Bud:Leaf:90][RULE:Bud:LeafCube:2][RULE:Bud::8]
  [BRUSH:Wood:Cylinder:0.35;1.0;0.35:substance=Wood:textures={3D=Wood_02_base;2D=log}:taper=0.10]
  [BRUSH:Leaf:Icosahedron:1.2;0.6;1.2:substance=Leaf:textures={3D=Hedge_01_base;2D=leaf}]
```
Trunk stacks tapering `Wood` with occasional forks, terminating in a `Bud` → leaf/nothing.

```
[ENTITY:Deer]
  [MOVE_SPEED:1.5][DIET:Berry][SCALE:0.7][SCALE_VARIANCE:0.12][OFFSET_Y:0.0]
  [SPAWN_ON:Grass01][NOISE_THRESHOLD:0.80]
  [HASH_SEED1:2654435761][HASH_SEED2:2246822519][HASH_MOD:35][HASH_REM:3]
  [AXIOM:Body(@{0;0.22;0.22} | Neck(@{0;0.18;0.12} | Head(Snout Nose)(EarL)(EarR)))(@{-0.14;0.04;0.16} | HipBL && LegBL)(@{0.14;0.04;0.16} | HipBR && LegBR)(@{-0.14;0.04;-0.16} | HipFL && LegFL)(@{0.14;0.04;-0.16} | HipFR && LegFR)(Tail)]
  [CLIP:walk:LegBL LegFL LegBR LegFR ~ &&LegBL&&LegFR^^LegBR^^LegFL ~ ^^LegBL^^LegFR&&LegBR&&LegFL:moving:8:10]
    [POSE:LegBL:LegBL][POSE:LegBR:LegBR][POSE:LegFL:LegFL][POSE:LegFR:LegFR]
  [CLIP:idle:headSway ~ +headSway ~ -headSway:4:2.0]
    [POSE:headSway:Head]
  [BONE:HipBL][BONE:HipBR][BONE:HipFL][BONE:HipFR]
  [BRUSH:Body:Cube:0.42;0.36;0.42:color=sienna]
  [BRUSH:Neck:Cube:0.20;0.26;0.20:color=sienna]
  [BRUSH:Snout:Cube:0.14;0.12;0.14:color=seashell:off=0;-0.04;0.12]
```
Body → walk up/forward (`@` then `|`) to Neck/Head with facial sub-branches `(...)`;
four legs branch at symmetric `@{±0.14;0.04;±0.16}`, each a Hip bone + Leg brush; `walk`
clip poses the leg bones.

## 8. Checklist

1. Open block; add metadata (spawn/hash, then `HEIGHT_*` or `MOVE_SPEED`/`SCALE`/`OFFSET_Y`).
2. `[AXIOM]`; growing rules must decrement `{n}` toward termination.
3. Define every placed module as `[BRUSH]` or `[BONE]` (unresolved = grammar-only).
4. Brush: `size` triple + `textures={3D=...}` or `color=`; add `2D=` for an icon.
5. Entities: bones for posed parts, then `[CLIP]` + `[POSE:sym:bone]`.
6. `@{x;y;z}` for joints; `|` after a walk to reset heading.