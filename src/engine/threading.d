/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import cube : Cube;
import commands : beginSingleTimeCommands, endSingleTimeCommands;
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
    this.isDaemon(true);
    super(&run);
  }

  void run() { // Load a single texture from path, and upload to GPU A-Sync
    uint slot = (*app).findTextureSlot(path);
    if((*app).trace) SDL_Log("loadTexture '%s' to %d", toStringz(path), slot);
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
      },
    );
  }
}

/** loadNextTexture, when the previous texture has finished loading
 * TODO: We could use multiple transfer queues to transfer several at once
 */
void loadNextTexture(ref App app, const(char)* folder = "data/textures/", string pattern = "*.{png,jpg}"){
  string[] files = dir(folder, pattern, false);
  if(!app.textures.loading){
    app.textures.loading = true;
    if (app.textures.cur < files.length) {
      auto worker = new textureLoader(&app, files[app.textures.cur], thisTid);
      worker.start();
    }
  }
  if(!app.textures.transfer){
    receiveTimeout(dur!"msecs"(-1),
      (textureComplete message) {
        app.textures.loading = false;
        app.textures.cur++;
        app.textures.transfer = true;
        uint slot = app.findTextureSlot(message);

        app.textures.cmdBuffer = app.beginSingleTimeCommands(app.transferPool, true);
        app.toGPU(app.textures.cmdBuffer, app.textures[slot]);
        vkEndCommandBuffer(app.textures.cmdBuffer);
        VkSubmitInfo submitInfo = {
          sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
          commandBufferCount: 1,
          pCommandBuffers: &app.textures.cmdBuffer.commands,
        };
        enforceVK(vkQueueSubmit(app.transfer, 1, &submitInfo, app.textures.cmdBuffer.fence)); // Submit to the transfer queue
        app.textures[slot].dirty = true;
      }
    );
  }else{
    VkResult result = vkGetFenceStatus(app.device, app.textures.cmdBuffer.fence);
    if (result == VK_SUCCESS) { 
      app.textures.transfer = false;
      auto commands = app.textures.cmdBuffer.commands;

    }
  }
}