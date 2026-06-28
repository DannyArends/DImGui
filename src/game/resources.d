/** 
 * Authors: Danny Arends (adapted from CalderaD)
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import game;

import io : dir, fixPath;
import textures : transferTextureAsync, idx, toRGBA;

struct ClassVal { ubyte cls; float value = 0.0f; }   // cls = cast(ubyte)ResourceClass — avoids the cross-module enum forward-ref

struct ResourceT {
  string name = "None", meshName = "Blocks", tex3D = "", tex2D = "";
  float scale = 1.0f;
  Colors color = Colors.white;
  ClassVal[] classes;
}

// primitives on ResourceT
@nogc bool hasClass(ResourceType t, ResourceClass c) pure nothrow {
  foreach(cv; resourceData(t).classes) { if(cv.cls == cast(ubyte)c) { return true; } } return false;
}
@nogc float classVal(ResourceType t, ResourceClass c) pure nothrow {
  foreach(cv; resourceData(t).classes) { if(cv.cls == cast(ubyte)c) { return cv.value; } } return 0.0f;
}

// legacy field accessors (UFCS shims over classes — keep old call sites working)
@nogc bool  traversable(const ResourceType r) pure nothrow { return r.hasClass(ResourceClass.Traversable); }
@nogc bool  buildable(const ResourceType r)   pure nothrow { return r.hasClass(ResourceClass.Buildable); }
@nogc float cost(const ResourceType r)        pure nothrow { return r.classVal(ResourceClass.Traversable); }
@nogc int   maxStack(const ResourceType r)    pure nothrow { return cast(int)r.classVal(ResourceClass.Item); }
@nogc bool isFood(const ResourceType r)       pure nothrow { return r.hasClass(ResourceClass.Food); }
@nogc float foodValue(const ResourceType r)   pure nothrow { return r.classVal(ResourceClass.Food); }

void injectResourceMeshes(ref GameApp app) {
  app.meshes.length = 0;
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    auto ttype = cast(ResourceType)tt;
    app.world.resources[ttype] = cast(uint)app.meshes.length;
    if(app.materials.length <= tt) app.materials ~= Material();  // only add material once
    app.meshes ~= Mesh([0, 0], cast(int)tt);  // reuse existing material slot
  }
}

void updateMaterials(ref GameApp app) {
  foreach (tt; 0 .. cast(int)ResourceType.max + 1) {
    auto ttype = cast(ResourceType)tt;
    uint idx =  app.world.resources[ttype];
    app.materials[app.meshes[idx].mid].tid = app.textures.idx(resourceData(ttype).tex3D);
    if((resourceData(ttype).meshName != "Blocks")) {
      app.materials[app.meshes[idx].mid].nid = app.textures.idx(resourceData(ttype).tex3D.replace("_base", "_normal"));
    }
  }
}
