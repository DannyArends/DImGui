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
  private int tid;
  private string path;
  private Tid main;

  this(App* a, int i, string p, Tid id) {
    this.app = a;
    this.tid = i;
    this.path = p;
    this.main = id;
    super(&run);
  }

  void run() {
    uint slot = (*app).findTextureSlot(path);
    if((*app).verbose) SDL_Log("loadTexture '%s' to %d", toStringz(path), slot);
    auto surface = IMG_Load(toStringz(path));
    if((*app).trace) SDL_Log("loadTexture '%s', Surface: %p [%dx%d:%d]", toStringz(path), surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));
    if (surface.format.BitsPerPixel != 32) { surface.toRGBA((*app).verbose); }  // Adapt surface to 32 bit
    (*app).textures[slot].surface = surface;
    if((*app).verbose) SDL_Log("loadTexture '%s' DONE", toStringz(path));
    main.send(format("%s", path));
  }
}

/** loadNextTexture when the previous one has finished
 */
void loadNextTexture(ref App app, const(char)* folder = "data/textures/", string pattern = "*.{png,jpg}"){
  string[] files = dir(folder, pattern, false);
  if(!app.textureLoading){
    app.textureLoading = true;
    if(app.currentTexture < files.length){
      auto worker = new textureLoader(&app, app.currentTexture, files[app.currentTexture], thisTid);
      worker.start();
    }
  }else{
    receiveTimeout(dur!"msecs"(-1),
      (string message) {
        if(app.verbose) SDL_Log("%s", toStringz(message));
        uint slot = app.findTextureSlot(message);
        app.toGPU(app.textures[slot], 0);
        app.textures[slot].dirty = true;
        app.currentTexture++;
        app.textureLoading = false;
      },
    );
  }
}