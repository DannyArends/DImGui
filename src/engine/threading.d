/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : loadOpenAsset, isOpenAsset;
import bone : mergeBones;
import io : dir, fixPath;
import material : registerAMaterials;
import images : deAllocate;
import textures: isTexture, mapTextures, transferTextureAsync, toRGBA, checkPendingTextures;

class TaskThread : Thread {
  protected Tid main;
  protected Tid mytid;
  private bool verbose = false;
  private bool active = true;

  this(Tid id, bool verbose = false) {
    this.main = id;
    this.verbose = verbose;
    this.isDaemon(true);
    super(&run, 8 * 1024 * 1024);  // 8MB stack
  }

  void handleGameObjects() { }

  void run() { if(verbose) SDL_Log("Worker spawned: %p", thisTid);
    mytid = thisTid();
    main.send(mytid);
    while (active) {
      receiveTimeout(dur!"msecs"(-1),
        (string path) {
          if (verbose) SDL_Log("Received path: %s", toStringz(extension(path)));
          if (path.isTexture()) {
            auto surface = IMG_Load(fixPath(toStringz(path)));
            if (SDL_GetPixelFormatDetails(surface.format).bytes_per_pixel < 4) { surface.toRGBA(verbose); }
            auto texture = cast(immutable(Texture))Texture(path, surface.w, surface.h, surface);
            main.send(texture, mytid);
          } else if(path.isOpenAsset()) {
            auto openasset = cast(immutable(OpenAsset))loadOpenAsset(toStringz(path), verbose);
            main.send(openasset, mytid);
          } else { main.send("Unknown file", mytid); }
        },
        (bool active) { this.active = active; }  // shutdown signal
      );
      handleGameObjects();
      SDL_Delay(1);
    }
  }
}

struct Threading {
  string[] paths;
  bool[Tid] workers;
  TaskThread function(Tid, bool) factory;
}

void initializeAsync(ref App app, bool preLoadAssimp = true, uint numWorkers = 16){
  if(preLoadAssimp) app.concurrency.paths ~= dir("data/objects/", "*.{obj,fbx}", false);
  app.concurrency.paths ~= dir("data/textures/", "*.{png,jpg}", false);
  foreach (i; 0 .. numWorkers) {
    auto worker = app.concurrency.factory ? app.concurrency.factory(thisTid, app.verbose > 0) : new TaskThread(thisTid, app.verbose > 0);
    worker.start();
    auto id = receiveOnly!Tid();
    app.concurrency.workers[id] = false;
  }
  if(app.verbose) SDL_Log(toStringz(format("Workers %s", app.concurrency.workers)));
}

void dispatchPendingAssets(ref App app) {
  foreach(tid; app.concurrency.workers.keys) {
    if(app.concurrency.paths.length == 0) break;
    if(!app.concurrency.workers[tid]) {
      auto idx = uniform(0, app.concurrency.paths.length);
      tid.send(app.concurrency.paths[idx]);
      app.concurrency.workers[tid] = true;
      app.concurrency.paths = app.concurrency.paths.remove(idx);
    }
  }
}

void stopWorkers(ref App app) { foreach(tid; app.concurrency.workers.keys) { tid.send(false); } }

void checkAsync(ref App app) {
  if(app.trace) SDL_Log("Checking Async, jobs: %d", app.concurrency.paths.length);
  app.dispatchPendingAssets();    // Submit pending textures / objects to available workers
  app.checkPendingTextures();     // Check all pending texture transfers; promote to app.textures once GPU is done

  receiveTimeout(dur!"msecs"(-1), (string message, Tid tid) {
    app.concurrency.workers[tid] = false;
    SDL_Log("Received back: %s", toStringz(message));
  });
  // Accept any incoming assimp objects, merge bones with the global array when received
  receiveTimeout(dur!"msecs"(-1), (immutable(OpenAsset) message, Tid tid) {
    app.concurrency.workers[tid] = false;
    auto obj = cast(OpenAsset)message;
    app.mergeBones(obj);
    app.objects ~= obj;
    app.registerAMaterials(app.objects[($-1)]);
    app.mapTextures(app.objects[($-1)]);
  });
  // Accept any incoming texture transfers
  while(receiveTimeout(dur!"msecs"(0), (immutable(Texture) message, Tid tid) {
    app.concurrency.workers[tid] = false;
    Texture texture = cast(Texture)message;
    app.transferTextureAsync(texture);
    app.mainDeletionQueue.add((){ app.deAllocate(texture); });
  })) {}
}
