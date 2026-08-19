/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : paletteOrdinal;
import lsystem : grammar, turnAxis, turnAngle;
import matrix : segmentTransform, position, inverse, multiply;
import quaternion : angleAxis, quatAxisAngle, qMul, rotate, toQuaternion;
import vector : vAdd;

/** One rigid part emitted by the turtle walk: a brush instance plus its place in the rig tree. */
struct RigNode {
  int parent = -1;      /// index of parent RigNode in the returned array; -1 == root
  Matrix local;         /// transform relative to parent (world == parent.world · local)
  DrawInstance inst;    /// draw instance: world matrix (bind pose) + material + color
  string symbol;        /// brush symbol -> shared geometry
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
  float side;                         /// left/right mirror sign (from bind X)
  Matrix localJ;                      /// node's rigid local (rotation + position)
  Matrix Rr;                          /// localJ with translation stripped (cursor frame)
}

/** An animation as its own L-system, walked in TIME -> baked into NodeAnimation tracks. */
struct AnimClip {
  string name;                /// "walk", "idle", ...
  string axiom = "";          /// clip L-system start symbols
  Rule[] rules;               /// clip production rules
  Symbol[string] poses;         /// symbol -> which bone it poses
  bool whenMoving = false;    /// select walk vs idle
  float fps = 8.0f;           /// steps per second (drives ticksPerSecond)
  float turn = 25.0f;         /// degrees per turn symbol (swing amplitude)
}

string boneName(string prefix, size_t k) { return format("%s%d", prefix, k); }

/** Rigid joint frame of a rig node: normalized bind rotation, origin at the segment base (the pivot). */
@nogc Matrix jointWorld(ref const RigNode n) nothrow {
  const Matrix M = n.inst.matrix;
  const float lx = sqrt(M[0]*M[0]+M[1]*M[1]+M[2]*M[2]);
  const float ly = sqrt(M[4]*M[4]+M[5]*M[5]+M[6]*M[6]);
  const float lz = sqrt(M[8]*M[8]+M[9]*M[9]+M[10]*M[10]);
  Matrix J;
  J[0]=M[0]/lx; J[1]=M[1]/lx; J[2]=M[2]/lx;
  J[4]=M[4]/ly; J[5]=M[5]/ly; J[6]=M[6]/ly;
  J[8]=M[8]/lz; J[9]=M[9]/lz; J[10]=M[10]/lz;
  J[12]=M[12]-0.5f*M[4]; J[13]=M[13]-0.5f*M[5]; J[14]=M[14]-0.5f*M[6];
  return J;
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
  foreach(k, ref n; rig) { nodes[k] = Node(boneName(prefix, k), 0, (n.parent < 0) ? J[k] : J[n.parent].inverse().multiply(J[k])); }
  foreach_reverse(k, ref n; rig) { if(n.parent >= 0) { nodes[n.parent].children ~= nodes[k]; } }
  Node root = Node(prefix ~ "root", 0, Matrix());
  foreach(k, ref n; rig) { if(n.parent < 0) { root.children ~= nodes[k]; } }
  return(root);
}

/** One bone per node; offset = jointWorld^-1 . bindWorld so a UNIT primitive at bone k lands as that segment. */
Bone[string] rigBones(const RigNode[] rig, string prefix) {
  Bone[string] bones;
  foreach(k, ref n; rig) { bones[boneName(prefix, k)] = Bone(jointWorld(n).inverse().multiply(n.inst.matrix), cast(uint)k); }
  return(bones);
}

/** Bake a species' authored clips into NodeAnimation tracks (raw order; index 0 = default). */
Animation[] buildClips(const RigNode[] rig, string prefix, immutable AnimClip[] clips, uint seed) {
  Animation[] anims;
  foreach(ref c; clips) { anims ~= clipAnimation(rig, prefix, c, seed); }
  return(anims);
}

/** One pose's contribution to a bone's local rotation at a key: world-axis swing (body frame) or cursor swing. */
Matrix poseLocal(ref immutable Symbol pb, const float[4] quat, float side, const Matrix localJ, const Matrix Rr) {
  if(pb.axis != NO_AXIS) {
    const float ang = quatAxisAngle(quat, pb.axis) * (pb.bySide ? side : 1.0f);
    return rotate(angleAxis(ang, pb.axis)).multiply(localJ);
  }
  const float[4] q = (pb.bySide && side < 0.0f) ? [-quat[0], -quat[1], -quat[2], quat[3]] : quat;
  return(rotate(q).multiply(Rr));
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

/** Local rotation for a node at one step: compose axis-poses, or the single cursor pose. */
Matrix stepLocal(ref const PoseCtx c, ref immutable AnimClip clip, int step) {
  const first = clip.poses[c.syms[0]];
  if(first.axis != NO_AXIS) { return(posesLocal(c, clip, step)); }
  return(poseLocal(first, quatAtStep(c.tracks[c.syms[0]], step), c.side, c.localJ, c.Rr));
}

/** Compose every axis-pose targeting a bone at one step. */
Matrix posesLocal(ref const PoseCtx c, ref immutable AnimClip clip, int step) {
  Matrix rot = Matrix();
  foreach(sym; c.syms) {
    const pb = clip.poses[sym];
    const float ang = quatAxisAngle(quatAtStep(c.tracks[sym], step), pb.axis) * (pb.bySide ? c.side : 1.0f);
    rot = rotate(angleAxis(ang, pb.axis)).multiply(rot);
  }
  return(rot.multiply(c.localJ));
}

/** Bake the keyframe track for one rig node from all clip poses that target its symbol. */
NodeAnimation nodeAnimation(ref const RigNode n, const string[] syms, ref immutable AnimClip clip, 
                            const PoseKey[][string] tracks, const Matrix localJ) {
  Matrix Rr = localJ; Rr[12] = 0.0f; Rr[13] = 0.0f; Rr[14] = 0.0f;
  auto c = PoseCtx(syms, tracks, (n.inst.matrix[12] < 0.0f) ? -1.0f : 1.0f, localJ, Rr);

  int[] steps;
  foreach(sym; syms) { foreach(ref pk; tracks[sym]) { if(!steps.canFind(pk.step)) { steps ~= pk.step; } } }
  steps.sort();

  NodeAnimation na = {positionKeys: [PositionKey(0.0, position(localJ))], scalingKeys:  [ScalingKey(0.0, [1.0f, 1.0f, 1.0f])]};
  na.rotationKeys.length = steps.length;
  foreach(i, step; steps) {
    na.rotationKeys[i] = RotationKey(cast(double)step, toQuaternion(stepLocal(c, clip, step)));
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
    a.nodeAnimations[boneName(prefix, k)] = nodeAnimation(n, syms, clip, tracks, localJ);
  }
  return(a);
}

/** The single turtle traversal. Structural glyphs are built-in; content symbols dispatch to the sink.
    '%' halves the turn-angle scale (compose for finer turns); scale is per-branch, saved on '(' , restored on ')'. */
void walk(Sink)(const(LSym)[] tokens, const Symbol[string] alpha, const TurtleConfig cfg, ref Sink sink) {
  float scale = 1.0f;      /// live turn-angle multiplier (1 = cfg angle)
  float[] scales;          /// scale stack, pushed alongside each branch
  bool up = false;         /// one-shot: next placed brush draws at world-up ('|')
  foreach(t; tokens) {
    if(t.name.length == 1 && !t.hasN) {
      const char c = t.name[0];
      if(c == '('){ scales ~= scale; sink.push(); continue; }
      if(c == ')'){ sink.pop(); if(scales.length){ scale = scales[$-1]; scales = scales[0 .. $-1]; } continue; }
      if(c == '~'){ sink.move(cfg.gap); continue; }
      if(c == '%'){ scale *= 0.5f; continue; }
      if(c == '|'){ up = true; continue; }
      const ax = turnAxis(c);
      if(ax != NO_AXIS){ sink.turn(ax, turnAngle(c, cfg) * scale); continue; }
    }
    if(auto s = t.name in alpha){ sink.place(t.name, *s, up, t.hasN ? t.n : 0); up = false; }
  }
}

/** Space sink: emits one RigNode per placed brush, retaining branch parentage. */
struct RigSink {
  RigNode[] nodes;            /// emitted parts (result)
  TurtleState st;             /// live cursor
  TurtleState[] stack;        /// saved cursors
  int current = -1;           /// parent for the next placed node
  int[] parents;              /// saved parents
  Random rnd;                 /// per-individual jitter stream (seeded in interpretRig)
  float latchA = 0.0f;        /// angle-jitter amplitude of the last-placed brush (0 until first brush)
  float latchL = 0.0f;        /// length-jitter amplitude of the last-placed brush

  void push(){ stack ~= st; parents ~= current; }
  void pop(){ if(stack.length){ st = stack[$-1]; stack = stack[0 .. $-1]; current = parents[$-1]; parents = parents[0 .. $-1]; } }
  void turn(const float[3] ax, float ang) {
    if(latchA != 0.0f) ang *= 1.0f + uniform(-latchA, latchA, rnd);
    st.orient = qMul(st.orient, angleAxis(ang, ax));
  }
  void move(float d) {
    if(latchL != 0.0f) d *= 1.0f + uniform(-latchL, latchL, rnd);
    const Matrix R = rotate(st.orient); st.pos = st.pos.vAdd([R[4]*d, R[5]*d, R[6]*d]);
  }
  void place(string c, ref const Symbol s, bool worldUp = false, int n = 0) {
    if(s.effect != Effect.brush) return;
    const float grow = 1.0f + s.taper * n;                       // fatten toward the base (high n), thin at the tip (n=0)
    const float rad = s.radius * grow;
    const float dep = (s.depth < 0.0f) ? s.depth : s.depth * grow;
    const Matrix Rmove = rotate(st.orient);            // heading: used for offset+advance
    const Matrix R = worldUp ? Matrix() : Rmove;       // draw frame: world-up when '|', else heading
    const float[3] o = s.offset;
    const float[3] dp = [st.pos[0] + o[0]*R[0] + o[1]*R[4] + o[2]*R[8],
                         st.pos[1] + o[0]*R[1] + o[1]*R[5] + o[2]*R[9],
                         st.pos[2] + o[0]*R[2] + o[1]*R[6] + o[2]*R[10]];
    auto color = cast(int)paletteOrdinal(s.color);
    latchA = s.jitterA; latchL = s.jitterL;                                   // turns after this brush inherit its jitter
    immutable float len = (s.jitterL != 0.0f) ? s.length * (1.0f + uniform(-s.jitterL, s.jitterL, rnd)) : s.length;
    nodes ~= RigNode(current, Matrix(), DrawInstance(segmentTransform(dp, R, rad, len, dep), s.material, color), c);
    current = cast(int)nodes.length - 1;
    if(s.advance){ st.pos = st.pos.vAdd([Rmove[4]*len*0.95f, Rmove[5]*len*0.95f, Rmove[6]*len*0.95f]); }
  }
}

/** Time sink: turns accumulate into `pending` (applied to the next pose only); `f` advances a step; a pose
    symbol records the accumulated cursor onto its own track. Branches are ignored (as the old time walk was). */
struct AnimSink {
  PoseKey[][string] tracks;
  float[4][string] cursor;
  float[4] pending = [0.0f, 0.0f, 0.0f, 1.0f];
  int t = 0;
  void push(){} void pop(){}
  void turn(const float[3] ax, float ang){ pending = qMul(pending, angleAxis(ang, ax)); }
  void move(float d){ t++; }
  void place(string c, ref const Symbol s, bool worldUp = false, int n = 0) {
    if(s.effect != Effect.pose) return;
    if(c !in cursor) cursor[c] = Quaternion.init;
    cursor[c] = qMul(cursor[c], pending);
    tracks[c] ~= PoseKey(t, cursor[c]);
    pending = Quaternion.init;
  }
}

/** Structure walk: retains branch hierarchy; each placed brush becomes a re-poseable RigNode. */
RigNode[] interpretRig(const(LSym)[] symbols, const TurtleConfig cfg, float[3] origin, float[4] orient0, uint seed = 0) {
  auto sink = RigSink(); sink.st = TurtleState(origin, orient0);
  sink.rnd = Random((seed ^ 0x9E3779B9) | 1);
  walk(symbols, cfg.alpha, cfg, sink);
  foreach(ref n; sink.nodes){ n.local = (n.parent < 0) ? n.inst.matrix : sink.nodes[n.parent].inst.matrix.inverse().multiply(n.inst.matrix); }
  return sink.nodes;
}

/** Flattened structure walk: per brush symbol, world-space DrawInstances (hierarchy discarded). */
DrawInstance[][string] interpret(const(LSym)[] symbols, const TurtleConfig cfg, float[3] origin, float[4] orient0, uint seed = 0) {
  DrawInstance[][string] instances;
  foreach(ref n; interpretRig(symbols, cfg, origin, orient0, seed)) instances[n.symbol] ~= n.inst;
  return instances;
}

/** Time walk: bake per-target-symbol key streams; `steps` = clip duration. */
PoseKey[][string] interpretAnim(const(LSym)[] symbols, const Symbol[string] poses, const TurtleConfig cfg, out int steps) {
  auto sink = AnimSink();
  walk(symbols, poses, cfg, sink);
  steps = (sink.t > 0) ? sink.t : 1;
  return sink.tracks;
}
