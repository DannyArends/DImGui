/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : dir;
import textures: findTextureSlot, toRGBA, toGPU;

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
    main.send(format("%s", path));
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
      (string message) {
        if(app.verbose) SDL_Log("%s", toStringz(message));
        uint slot = app.findTextureSlot(message);
        app.toGPU(app.textures[slot]);
        app.textures[slot].dirty = true;
        app.textures.cur++;
        app.textures.busy = false;
      },
    );
  }
}