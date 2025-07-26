/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : loadOpenAsset, OpenAsset;
import cube : Cube;
import geometry : Instance, Geometry, computeNormals, computeTangents, position, rotate, scale;
import io : dir;
import images : deAllocate;
import textures: Texture, mapTextures, transferTextureAsync, toRGBA;
import validation : nameVulkanObject;

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
    this.isDaemon(true);
    super(&run);
  }

  void run() { // Load a single texture from path, and upload to GPU A-Sync
    if((*app).trace) SDL_Log("loadTexture '%s'", toStringz(path));
    auto surface = IMG_Load(toStringz(path));
    if((*app).trace) SDL_Log("loadTexture '%s', Surface: %p [%dx%d:%d]", toStringz(path), surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));
    if (surface.format.BitsPerPixel != 32) { surface.toRGBA((*app).verbose); }  // Adapt surface to 32 bit
    Texture t = Texture(path, surface.w, surface.h, surface);
    if((*app).verbose) SDL_Log("loadTexture '%s' DONE", toStringz(path));
    immutable(Texture) immutableT = cast(immutable)t;
    main.send(immutableT);
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
    this.isDaemon(true);
    super(&run);
  }

  void run() {
    Geometry a = (*app).loadOpenAsset(toStringz(path));
    a.computeNormals();
    a.computeTangents();
    a.scale([0.15f, 0.15f, 0.15f]);
    a.position([1.5f, -0.9f, -2.5f + (xpos / 1.2f)]);
    immutable(Geometry) immutableA = cast(immutable)a;
    main.send(immutableA);
  }
}

/** loadGeometries on different threads
 */
void loadGeometries(ref App app, const(char)* folder = "data/objects", string pattern = "*.{obj,fbx}"){
  string[] files = dir(folder, pattern, false);
  if(!app.objects.loaded){
    foreach(i, file; files){
      auto worker = new geometryLoader(&app, format("%s/%s", fromStringz(folder), baseName(file)), cast(uint)i, thisTid);
      worker.start();
    }
    app.objects.loaded = true;
  }else{
    receiveTimeout(dur!"msecs"(-1),
      (immutable(Geometry) message) {
        app.objects ~= cast(Geometry)message;
        app.mapTextures(app.objects[($-1)]); // Map Textures for the object loaded
      },
    );
  }
}

/** loadNextTexture, when the previous texture has finished loading
 * TODO: We could use multiple transfer queues to transfer several at once
 */
void loadNextTexture(ref App app, const(char)* folder = "data/textures/", string pattern = "*.{png,jpg}"){
  if(!app.textures.loaded){
    string[] files = dir(folder, pattern, false);
    foreach(i, file; files){
      auto worker = new textureLoader(&app, file, thisTid);
      worker.start();
    }
    app.textures.loaded = true;
  }
  if(!app.textures.transfer){
    receiveTimeout(dur!"msecs"(-1),
      (immutable(Texture) message) {
        Texture texture = cast(Texture)message;
        app.textures.transfer = true;
        app.transferTextureAsync(texture);
        app.mapTextures();
        app.mainDeletionQueue.add((){ app.deAllocate(texture); });
      }
    );
  }else{
    VkResult result = vkGetFenceStatus(app.device, app.textures.cmdBuffer.fence);
    if (result == VK_SUCCESS) { 
      app.textures.transfer = false;
    }
  }
}