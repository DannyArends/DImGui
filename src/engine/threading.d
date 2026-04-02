/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : loadOpenAsset, isOpenAsset, OpenAsset;
import io : dir, fixPath;
import bone : mergeBones;
import images : deAllocate;
import textures: isTexture, mapTextures, transferTextureAsync, toRGBA;

class TaskThread : Thread {
  private Tid main;
  private Tid mytid;
  private bool verbose = false;
  private bool active = true;

  this(Tid id, bool verbose = false) {
    this.main = id;
    this.verbose = verbose;
    this.isDaemon(true);
    super(&run);
  }

  void run() { if(verbose) SDL_Log("Worker spawned: %p", thisTid);
    mytid = thisTid();
    main.send(mytid);
    while (active) {
      receiveTimeout(dur!"msecs"(250),
        (string path) {
          if(verbose) SDL_Log("Received path: %s", toStringz(extension(path)));
          if(path.isTexture()){
            auto fp = fixPath(toStringz(path));
            auto surface = IMG_Load(fp);
            if (SDL_GetPixelFormatDetails(surface.format).bits_per_pixel != 32) { surface.toRGBA(verbose); }
            auto t = Texture(path, surface.w, surface.h, surface);
            auto immutableT = cast(immutable)t;
            main.send(immutableT, mytid);
          }else if(path.isOpenAsset()){
            auto g = loadOpenAsset(toStringz(path));
            auto immutableG = cast(immutable)g;
            main.send(immutableG, mytid);
          }else{ main.send("Unknown file", mytid); }
        }
      );
      SDL_Delay(10);
    }
  }
}

struct Threading {
  string[] paths;
  bool[Tid] workers;
}

void initializeAsync(ref App app, uint numWorkers = 8){
  app.concurrency.paths ~= dir("data/objects/", "*.{obj,fbx}", false);
  app.concurrency.paths ~= dir("data/textures/", "*.{png,jpg}", false);
  foreach (i; 0 .. numWorkers) {
    auto worker = new TaskThread(thisTid, app.verbose > 0);
    worker.start();
    auto id = receiveOnly!Tid();
    app.concurrency.workers[id] = false;
  }
  if(app.verbose) SDL_Log(toStringz(format("Workers %s", app.concurrency.workers)));
}

void checkAsync(ref App app) {
  //if(app.trace) SDL_Log("Checking Async, jobs: %d", app.concurrency.paths.length);
  if(app.concurrency.paths.length > 0){
    foreach(tid; app.concurrency.workers.keys) {
      //if(app.trace) SDL_Log("Checking Worker %p (status: %d)", tid, app.concurrency.workers[tid]);
      if(app.concurrency.paths.length > 0 && !app.concurrency.workers[tid]){
        auto idx = uniform(0, app.concurrency.paths.length);
        tid.send(app.concurrency.paths[idx]);
        app.concurrency.workers[tid] = true;
        app.concurrency.paths = app.concurrency.paths.remove(idx);
      }
    }
  }
  receiveTimeout(dur!"msecs"(-1), (string message, Tid tid) {
    app.concurrency.workers[tid] = false;
    SDL_Log("Received back: %s", toStringz(message));
  });
  receiveTimeout(dur!"msecs"(-1), (immutable(OpenAsset) message, Tid tid) {
    app.concurrency.workers[tid] = false;
    auto obj = cast(OpenAsset)message;
    app.mergeBones(obj);
    app.objects ~= obj;
    app.mapTextures(app.objects[($-1)]);
  });
  if(!app.textures.transfer) {
    receiveTimeout(dur!"msecs"(-1), (immutable(Texture) message, Tid tid) {
      app.concurrency.workers[tid] = false;
      Texture texture = cast(Texture)message;
      app.textures.transfer = true;
      app.transferTextureAsync(texture);
      app.mainDeletionQueue.add((){ app.deAllocate(texture); });
    });
  }else{
    VkResult result = vkGetFenceStatus(app.device, app.textures.cmdBuffer.fence);
    if (result == VK_SUCCESS) {
      app.textures.transfer = false;
      //app.mapTextures();
    }
  }
}
