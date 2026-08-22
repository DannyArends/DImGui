/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : paletteOrdinal;
import lsystem : grammar, turnAxis, turnAngle;
import matrix : segmentTransform, position, inverse, translation, multiply;
import quaternion : angleAxis, qMul, rotate, toQuaternion;
import vector : vAdd;

/** One rigid part emitted by the turtle walk: a brush instance plus its place in the rig tree. */
struct RigNode {
  int parent = -1;                                /// index of parent RigNode in the returned array; -1 == root
  DrawInstance inst;                              /// draw instance: world matrix (bind pose) + material + color
  string symbol;                                  /// brush symbol -> shared geometry
  bool isBone = true;                             /// false = static cloud cube, rides its parent bone
  float[4] frame = [0.0f, 0.0f, 0.0f, 1.0f];      /// bone local orientation; H/L/U = rotate(frame) columns
  float[3] base = [0.0f, 0.0f, 0.0f];             /// joint origin (segment base = jointWorld translation)
}

/** One keyframe from the time-walk: the step index and the cursor quaternion recorded for a bone. */
struct PoseKey {
  int step;         /// clip tick this key lands on
  float[4] quat;    /// accumulated cursor orientation at that step
}

struct TurtleState {
  float[3] pos;
  float[4] orient;
}

/** Everything the per-step bake needs for one rig node. */
struct PoseCtx {
  const(string)[] syms;                 /// clip symbols targeting this bone
  const(PoseKey[][string]) tracks;      /// baked key streams, by symbol
  Matrix Rr;                            /// localJ with translation stripped (cursor frame)
}

/** An animation as its own L-system, walked in TIME -> baked into NodeAnimation tracks. */
struct AnimClip {
  string name;                /// "walk", "idle", ...
  string axiom = "";          /// clip L-system start symbols
  Rule[] rules;               /// clip production rules
  Symbol[string] poses;       /// symbol -> which bone it poses
  bool whenMoving = false;    /// select walk vs idle
  float fps = 8.0f;           /// steps per second (drives ticksPerSecond)
  float turn = 25.0f;         /// degrees per turn symbol (swing amplitude)
}

string boneName(string prefix, size_t k) { return format("%s%d", prefix, k); }

/** Rigid joint frame of a rig node: normalized bind rotation, origin at the segment base (the pivot). */
@nogc Matrix jointWorld(ref const RigNode n) nothrow {
  Matrix J = rotate(n.frame);
  return J.position(n.base);
}

/** Rigid joint frame of every rig node, indexed like `rig`. */
Matrix[] jointWorlds(const RigNode[] rig) nothrow {
  auto J = new Matrix[](rig.length);
  foreach(k, ref n; rig) J[k] = jointWorld(n);
  return J;
}

/** Node tree calculateGlobalTransform walks: rigid joint frames, node k named `prefix~k`. */
Node rigToNode(const RigNode[] rig, string prefix) {
  Matrix[] J = jointWorlds(rig);
  Node[] nodes = new Node[](rig.length);
  foreach(k, ref n; rig) {
    if(n.isBone) { nodes[k] = Node(boneName(prefix, k), 0, (n.parent < 0) ? J[k] : J[n.parent].inverse().multiply(J[k])); }
  }
  foreach_reverse(k, ref n; rig) { if(n.isBone && n.parent >= 0) { nodes[n.parent].children ~= nodes[k]; } }
  Node root = Node(prefix ~ "root", 0, Matrix());
  foreach(k, ref n; rig) { if(n.isBone && n.parent < 0) { root.children ~= nodes[k]; } }
  return(root);
}

/** One bone per node; offset = jointWorld^-1 . bindWorld so a UNIT primitive at bone k lands as that segment. */
Bone[string] rigBones(const RigNode[] rig, string prefix) {
  Bone[string] bones;
  foreach(k, ref n; rig) {
    if(n.isBone) { bones[boneName(prefix, k)] = Bone(jointWorld(n).inverse().multiply(n.inst.matrix), cast(uint)k); }
  }
  return(bones);
}

/** Bake a species' authored clips into NodeAnimation tracks (raw order; index 0 = default). */
Animation[] buildClips(const RigNode[] rig, string prefix, immutable AnimClip[] clips, uint seed) {
  Animation[] anims;
  foreach(ref c; clips) { anims ~= clipAnimation(rig, prefix, c, seed); }
  return(anims);
}

/** Sample a symbol's track at time `step`: the last key at or before it (hold-last), else identity. */
float[4] quatAtStep(const PoseKey[] keys, int step) {
  float[4] q = Quaternion.init;
  foreach(ref pk; keys) {
    if(pk.step > step) break;
    q = pk.quat;
  }
  return(q);
}

/** Local rotation for a node at one step: cursor swing in the bone frame, composing all its pose tracks. */
Matrix stepLocal(ref const PoseCtx c, int step) {
  float[4] q = Quaternion.init;
  foreach(sym; c.syms) { q = qMul(q, quatAtStep(c.tracks[sym], step)); }
  return(rotate(q).multiply(c.Rr));
}

/** Bake the keyframe track for one rig node from all clip poses that target its symbol. */
NodeAnimation nodeAnimation(const string[] syms, const PoseKey[][string] tracks, const Matrix localJ) {
  auto c = PoseCtx(syms, tracks, localJ.position([0.0f,0.0f,0.0f]));

  int[] steps;
  foreach(sym; syms) { foreach(ref pk; tracks[sym]) { if(!steps.canFind(pk.step)) { steps ~= pk.step; } } }
  steps.sort();

  NodeAnimation na = {positionKeys: [PositionKey(0.0, localJ.translation())], scalingKeys:  [ScalingKey(0.0, [1.0f, 1.0f, 1.0f])]};
  na.rotationKeys.length = steps.length;
  foreach(i, step; steps) {
    na.rotationKeys[i] = RotationKey(cast(double)step, toQuaternion(stepLocal(c, step)));
  }
  return(na);
}

/** Bake one AnimClip: walk its L-system in time, then map each target symbol's key stream onto every matching rig node. */
Animation clipAnimation(const RigNode[] rig, string prefix, ref immutable AnimClip clip, uint seed) {
  int steps;
  TurtleConfig cfg = { yaw: clip.turn, pitch: clip.turn, roll: clip.turn };
  auto tracks = interpretAnim(grammar(seed, 1, clip.axiom, clip.rules), clip.poses, cfg, steps);

  Animation a = { name: clip.name, duration: cast(double)steps, ticksPerSecond: clip.fps };
  auto J = jointWorlds(rig);
  foreach(k, ref n; rig) {
    string[] syms;
    foreach(sym, ref b; clip.poses) { if(b.target == n.symbol && sym in tracks) { syms ~= sym; } }
    if(syms.length == 0) continue;
    const Matrix localJ = (n.parent < 0) ? J[k] : J[n.parent].inverse().multiply(J[k]);
    a.nodeAnimations[boneName(prefix, k)] = nodeAnimation(syms, tracks, localJ);
  }
  return(a);
}

/** The single turtle traversal. Structural glyphs are built-in; content symbols dispatch to the sink.
    '%' halves the turn-angle scale (compose for finer turns); scale is per-branch, saved on '(' , restored on ')'. */
void walk(Sink)(const(LSym)[] tokens, const Symbol[string] alpha, const TurtleConfig cfg, ref Sink sink) {
  float scale = 1.0f;      /// live turn-angle multiplier (1 = cfg angle)
  float[] scales;          /// scale stack, pushed alongside each branch
  foreach(t; tokens) {
    if(t.name.length == 1 && !t.hasN) {
      const char c = t.name[0];
      if(c == '('){ scales ~= scale; sink.push(); continue; }
      if(c == ')'){ sink.pop(); if(scales.length){ scale = scales[$-1]; scales = scales[0 .. $-1]; } continue; }
      if(c == '~'){ sink.move(t.hasArg ? t.arg : cfg.gap); continue; }
      if(c == '%'){ scale *= 0.5f; continue; }
      if(c == '|'){ sink.reset(); continue; }
      const ax = turnAxis(c);
      if(ax != NO_AXIS){ sink.turn(ax, (t.hasArg ? t.arg : turnAngle(c, cfg)) * scale); continue; }
    }
    if(auto s = t.name in alpha){ sink.place(t.name, *s, t.hasN ? t.n : 0); }
  }
}

/** Space sink: emits one RigNode per placed brush, retaining branch parentage. */
struct RigSink {
  RigNode[] nodes;            /// emitted parts (result)
  TurtleState st;             /// live cursor
  TurtleState[] stack;        /// saved cursors
  int current = -1;           /// parent for the next placed node
  int[] parents;              /// saved parents

  void push(){ stack ~= st; parents ~= current; }
  void pop(){ if(stack.length){ st = stack[$-1]; stack = stack[0 .. $-1]; current = parents[$-1]; parents = parents[0 .. $-1]; } }
  void turn(const float[3] ax, float ang) { st.orient = qMul(st.orient, angleAxis(ang, ax)); }
  void reset(){ st.orient = [0.0f, 0.0f, 0.0f, 1.0f]; }
  void move(float d) { st.pos = st.pos.vAdd(rotate(st.orient).multiply([0.0f, d, 0.0f])); }
  void place(string c, ref const Symbol s, int n = 0) {
    if(s.effect != Effect.brush && s.effect != Effect.bone) return;
    const float grow = 1.0f + s.taper * n;
    const float[3] size = [s.size[0] * grow, s.size[1], s.size[2] * grow];
    const Matrix R = rotate(st.orient);   // draw frame: world-up when '|', else heading
    const float[3] dp = st.pos.vAdd(R.multiply(s.offset));
    auto color = cast(int)paletteOrdinal(s.color);
    nodes ~= RigNode(current, DrawInstance(segmentTransform(dp, R, size), s.material, color), c, true, st.orient, dp);
    current = cast(int)nodes.length - 1;
  }
}

/** Time sink: turns accumulate into `pending` (applied to the next pose only); '~' advances a step; a pose
    symbol records the accumulated cursor onto its own track. Branches are ignored (as the old time walk was). */
struct AnimSink {
  PoseKey[][string] tracks;
  float[4][string] cursor;
  float[4] pending = [0.0f, 0.0f, 0.0f, 1.0f];
  int t = 0;
  void push(){} void pop(){}
  void turn(const float[3] ax, float ang){ pending = qMul(pending, angleAxis(ang, ax)); }
  void reset(){}
  void move(float d){ t++; }
  void place(string c, ref const Symbol s, int n = 0) {
    if(s.effect != Effect.pose) return;
    if(c !in cursor) cursor[c] = Quaternion.init;
    cursor[c] = qMul(cursor[c], pending);
    tracks[c] ~= PoseKey(t, cursor[c]);
    pending = Quaternion.init;
  }
}

/** Structure walk: retains branch hierarchy; each placed brush becomes a re-poseable RigNode. */
RigNode[] interpretRig(const(LSym)[] symbols, const TurtleConfig cfg, float[3] origin, float[4] orient0) {
  auto sink = RigSink([], TurtleState(origin, orient0));
  walk(symbols, cfg.alpha, cfg, sink);
  return sink.nodes;
}

/** Flattened structure walk: per brush symbol, world-space DrawInstances (hierarchy discarded). */
DrawInstance[][string] interpret(const(LSym)[] symbols, const TurtleConfig cfg, float[3] origin, float[4] orient0) {
  DrawInstance[][string] instances;
  foreach(ref n; interpretRig(symbols, cfg, origin, orient0)) instances[n.symbol] ~= n.inst;
  return instances;
}

/** Time walk: bake per-target-symbol key streams; `steps` = clip duration. */
PoseKey[][string] interpretAnim(const(LSym)[] symbols, const Symbol[string] poses, const TurtleConfig cfg, out int steps) {
  auto sink = AnimSink();
  walk(symbols, poses, cfg, sink);
  steps = (sink.t > 0) ? sink.t : 1;
  return sink.tracks;
}
