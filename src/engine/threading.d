/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import cube : Cube;
import geometry : Instance, Geometry, computeNormals, computeTangents, position, rotate, scale;
import io : dir;
import textures: findTextureSlot, toRGBA, toGPU;
import assimp : loadOpenAsset, OpenAsset;

struct textureComplete{
  string path;
  alias path this;
}

struct geometryComplete{
  string path;
  alias path this;
}
/** Loads a texture on a separate Thread
 */
class textureLoader : Thread {
  private App* app;
  private string path;
  private Tid main;

  this(App* a, string p, Tid id) {
    this.app = a;
    this.path = p;
    this.main = id;
    super(&run);
  }

  void run() { // Load a single texture from path
    uint slot = (*app).findTextureSlot(path);
    if((*app).verbose) SDL_Log("loadTexture '%s' to %d", toStringz(path), slot);
    auto surface = IMG_Load(toStringz(path));
    if((*app).trace) SDL_Log("loadTexture '%s', Surface: %p [%dx%d:%d]", toStringz(path), surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));
    if (surface.format.BitsPerPixel != 32) { surface.toRGBA((*app).verbose); }  // Adapt surface to 32 bit
    (*app).textures[slot].surface = surface;
    (*app).textures[slot].width = surface.w;
    (*app).textures[slot].height = surface.h;
    if((*app).verbose) SDL_Log("loadTexture '%s' DONE", toStringz(path));
    main.send(textureComplete(path));
  }
}

/** Loads a texture on a separate Thread
 */
class geometryLoader : Thread {
  private App* app;
  private string path;
  private uint xpos;
  private Tid main;

  this(App* a, string p, uint x,  Tid id) {
    this.app = a;
    this.path = p;
    this.xpos = x;
    this.main = id;
    super(&run);
  }

  void run() {
    SDL_Log(toStringz(format("Loading: %s", path)));
    Geometry a = (*app).loadOpenAsset(toStringz(path));
    a.computeNormals();
    a.computeTangents();
    a.scale([0.15f, 0.15f, 0.15f]);
    a.position([1.5f, -0.9f, -2.5f + (xpos / 1.2f)]);
    (*app).objects ~= a;
    main.send(geometryComplete(path));
  }
}

/** loadGeometries,
 */
void loadGeometries(ref App app, const(char)* folder = "data/objects", string pattern = "*.{obj,fbx}"){
  string[] files = dir(folder, pattern, false);
  if(!app.objects.loaded){
    SDL_Log(toStringz(format("Loading: %s", files)));
    foreach(i, file; files){
      auto worker = new geometryLoader(&app, format("%s/%s", fromStringz(folder), baseName(file)), cast(uint)i, thisTid);
      SDL_Log(toStringz(format("worker: %s", worker)));
      worker.start();
      
    }
    app.objects.loaded = true;
  }else{
    receiveTimeout(dur!"msecs"(-1),
      (geometryComplete message) {
        SDL_Log("geometryComplete: %s", toStringz(message));
      },
    );
  }
}

/** loadNextTexture, when the previous texture has finished loading
 * TODO: We could use multiple transfer queues to transfer several at once
 */
void loadNextTexture(ref App app, const(char)* folder = "data/textures/", string pattern = "*.{png,jpg}"){
  string[] files = dir(folder, pattern, false);
  if(!app.textures.busy){
    app.textures.busy = true;
    if(app.textures.cur < files.length){
      auto worker = new textureLoader(&app, files[app.textures.cur], thisTid);
      worker.start();
    }
  }else{
    receiveTimeout(dur!"msecs"(-1),
      (textureComplete message) {
        if(app.verbose) SDL_Log("textureComplete: %s", toStringz(message));
        uint slot = app.findTextureSlot(message);
        app.toGPU(app.textures[slot]);
        app.textures[slot].dirty = true;
        app.textures.cur++;
        app.textures.busy = false;
      },
    );
  }
}