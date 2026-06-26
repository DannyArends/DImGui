/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : loadOpenAsset, isOpenAsset;
import bone : mergeBones;
import animation : animateAsset;
import io : dir, fixPath;
import material : registerAMaterials;
import images : cleanup;
import textures: isTexture, mapTextures, transferTextureAsync, toRGBA, checkPendingTextures;

/** Worker thread that loads textures and assimp assets off the main thread, returning results via messages */
class TaskThread : Thread {
  protected Tid main;
  protected Tid mytid;
  private bool verbose = false;
  private bool active = true;

  /** Spawn a daemon worker bound to the main thread's Tid */
  this(Tid id, bool verbose = false) {
    this.main = id;
    this.verbose = verbose;
    this.isDaemon(true);
    super(&run, 8 * 1024 * 1024);  // 8MB stack
  }

  /** Hook for subclasses to do per-loop work (overridden by GameTaskThread) */
  void handleGameObjects() { }

  /** Worker loop: receive a file path, load texture/asset, send result back; exits on shutdown signal */
  void run() { if(verbose) SDL_Log("Worker spawned: %p", thisTid);
    mytid = thisTid();
    main.send(mytid);
    while (active) {
      receiveTimeout(dur!"msecs"(2),
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
    }
  }
}

struct Threading {
  string[] paths;
  bool[Tid] workers;
  TaskThread function(Tid, bool) factory;
}

/** Spawn the worker pool and queue all asset/texture paths for background loading */
void initializeAsync(ref App app, bool preLoadAssimp = true, uint numWorkers = 16){
  if(preLoadAssimp) app.concurrency.paths ~= dir("data/objects/", "*.{obj,fbx}", false);
  app.concurrency.paths ~= dir("data/textures/", "*.{png,jpg}", false);
  foreach (i; 0 .. numWorkers) {
    auto worker = app.concurrency.factory ? app.concurrency.factory(thisTid, app.verbose > 0) : new TaskThread(thisTid, app.verbose > 0);
    worker.start();
    auto id = receiveOnly!Tid();
    app.concurrency.workers[id] = false;
  }
  if(app.verbose) SDL_Log(cstr("Workers %s", app.concurrency.workers));
}

/** Drain all queued messages of type T, resetting the worker and running handler for each */
bool drainMessages(T)(ref App app, void delegate(T) handler, uint max = uint.max) {
  bool any = false;
  uint n = 0;
  while(n < max && receiveTimeout(dur!"msecs"(0), (immutable(T) msg, Tid tid) {
    app.concurrency.workers[tid] = false;
    handler(cast(T)msg);
    any = true;
    n++;
  })) {}
  return any;
}

/** Hand queued asset paths to idle workers, one per free worker */
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

/** Signal all workers to exit their loop */
void stopWorkers(ref App app) { foreach(tid; app.concurrency.workers.keys) { tid.send(false); } }

/** Per-frame: dispatch pending work, promote finished textures, and drain all completed worker results */
void checkAsync(ref App app) {
  if(app.trace) SDL_Log("Checking Async, jobs: %d", app.concurrency.paths.length);
  app.dispatchPendingAssets();    // Submit pending textures / objects to available workers
  app.checkPendingTextures();     // Check all pending texture transfers; promote to app.textures once GPU is done

  app.drainMessages!string((msg) { SDL_Log("Received back: %s", toStringz(msg)); });
  app.drainMessages!OpenAsset((obj) {
    app.mergeBones(obj);
    app.objects ~= obj;
    auto asset = app.objects[($-1)];
    if(asset.animations.length > 0 && asset.rootnode.name !is null){ asset.onFrame = (float dt) { app.animateAsset(asset, dt); }; }
    app.registerAMaterials(asset);
    app.mapTextures(asset);
  });
  app.drainMessages!Texture((t) {
    app.transferTextureAsync(t);
    app.mainDeletionQueue.add((){ app.cleanup(t); });
  });
}
