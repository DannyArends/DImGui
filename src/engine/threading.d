/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : loadOpenAsset, OpenAsset;
import cube : Cube;
import geometry : Instance, Geometry;
import io : dir;
import images : deAllocate;
import textures: Texture, mapTextures, transferTextureAsync, toRGBA;
import validation : nameVulkanObject;

/** Loads a texture on a separate Thread
 */
class Loader(T) : Thread {
  private App* app;
  private string path;
  private Tid main;

  this(App* a, string p,  Tid id) {
    this.app = a;
    this.path = p;
    this.main = id;
    this.isDaemon(true);
    super(&run);
  }

  void run() {
    T t;
    static if(is(T == OpenAsset)){ t = (*app).loadOpenAsset(toStringz(path)); }
    static if(is(T == Texture)){
      auto surface = IMG_Load(toStringz(path));
      if (surface.format.BitsPerPixel != 32) { surface.toRGBA((*app).verbose); }  // Adapt surface to 32 bit
      t = T(path, surface.w, surface.h, surface);
    }
    immutable(T) immutableT = cast(immutable)t;
    main.send(immutableT);
  }
}

/** loadGeometries on different threads
 */
void loadGeometries(ref App app, const(char)* folder = "data/objects", string pattern = "*.{obj,fbx}"){
  string[] files = dir(folder, pattern, false);
  if(!app.objects.loaded){
    foreach(file; files){
      auto worker = new Loader!OpenAsset(&app, format("%s/%s", fromStringz(folder), baseName(file)), thisTid);
      worker.start();
    }
    app.objects.loaded = true;
  }else{
    receiveTimeout(dur!"msecs"(-1),
      (immutable(OpenAsset) message) {
        app.objects ~= cast(Geometry)message;
        app.mapTextures(app.objects[($-1)]); // Map Textures for the object loaded
      },
    );
  }
}

/** loadNextTexture, when the previous texture has finished loading
 */
void loadNextTexture(ref App app, const(char)* folder = "data/textures/", string pattern = "*.{png,jpg}"){
  if(!app.textures.loaded){
    string[] files = dir(folder, pattern, false);
    foreach(i, file; files){
      auto worker = new Loader!Texture(&app, file, thisTid);
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