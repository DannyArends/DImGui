/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

struct FeaturePartT {
  string mesh;
  float scaleX = 1.0f, scaleXVariance = 0.0f;
  float scaleY = 1.0f, scaleYVariance = 0.0f;
  float taper  = 0.0f;                          /// scaleX reduction per repeated segment
  float offsetY = 0.0f;                         /// 0.0 = ground, 1.0 = top (height * tileHeight)
  bool repeat  = false;                         /// repeat per height segment
  string resourceType = "None";                 /// DrawInstance material
}

struct FeatureDropT {
  string material;
  int countMin = 1, countMax = 1;
  bool perHeight = false;
}

struct FeatureT {
  string name;
  string[] spawnOn;
  float noiseThreshold = 0.65f;
  uint hashSeed1, hashSeed2;
  uint hashMod, hashRem;
  uint heightMin = 1, heightMax = 1;
  float tilePenalty = 0.0f;
  string interaction;
  FeaturePartT[] parts;
  FeatureDropT[] drops;
}

struct Feature {
  int[3] rootTile;
  uint height;
  size_t[] instanceIdxs;  // per part — for repeated parts, trunkStart only
  uint hash;

  static bool matchGeometry(string g) {
    import raws : features;
    foreach(ref ft; features) foreach(ref p; ft.parts) if(p.mesh == g) return true;
    return false;
  }
  bool matchIndex(size_t idx) const { return instanceIdxs.canFind(idx); }
  @property float bboxHeight() const { return cast(float)height; }
}
