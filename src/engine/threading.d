/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import assimp : loadOpenAsset, isOpenAsset, OpenAsset;
import bone : mergeBones;
import buffer : destroyStagingBuffer;
import io : dir, fixPath;
import images : deAllocate;
import textures: isTexture, mapTextures, transferTextureAsync, toRGBA;
import world : buildChunkData, finalizeChunk;

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
          if (verbose) SDL_Log("Received path: %s", toStringz(extension(path)));
          if (path.isTexture()) {
            auto fp = fixPath(toStringz(path));
            auto surface = IMG_Load(fp);
            if (SDL_GetPixelFormatDetails(surface.format).bits_per_pixel != 32) { surface.toRGBA(verbose); }
            auto texture = cast(immutable(Texture))Texture(path, surface.w, surface.h, surface);
            main.send(texture, mytid);
          } else if(path.isOpenAsset()) {
            auto openasset = cast(immutable(OpenAsset))loadOpenAsset(toStringz(path), verbose);
            main.send(openasset, mytid);
          } else { main.send("Unknown file", mytid); }
        },
        (immutable(WorldData) wd, immutable(TileAtlas) ta, int[3] coord) {
          auto data = buildChunkData(wd, ta, coord);
          main.send(cast(immutable(ChunkData))data, mytid);
        },
        (bool active) { this.active = active; }  // shutdown signal
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

void stopWorkers(ref App app) { foreach(tid; app.concurrency.workers.keys) { tid.send(false); } }

void checkAsync(ref App app) {
  if(app.trace) SDL_Log("Checking Async, jobs: %d", app.concurrency.paths.length);
  if(app.concurrency.paths.length > 0){
    foreach(tid; app.concurrency.workers.keys) {
      if(app.trace) SDL_Log("Checking Worker %p (status: %d)", tid, app.concurrency.workers[tid]);
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
  // Accept any incoming assimp objects, merge bones with the global array when received
  receiveTimeout(dur!"msecs"(-1), (immutable(OpenAsset) message, Tid tid) {
    app.concurrency.workers[tid] = false;
    auto obj = cast(OpenAsset)message;
    app.mergeBones(obj);
    app.objects ~= obj;
    app.mapTextures(app.objects[($-1)]);
  });
  // Accept any incoming texture transfers
  receiveTimeout(dur!"msecs"(-1), (immutable(Texture) message, Tid tid) {
    app.concurrency.workers[tid] = false;
    Texture texture = cast(Texture)message;
    app.transferTextureAsync(texture);
    app.mainDeletionQueue.add((){ app.deAllocate(texture); });
  });
  // Accept any incoming chunks, and submit for finalization on GPU
  receiveTimeout(dur!"msecs"(-1), (immutable(ChunkData) data, Tid tid) {
    if(app.trace) SDL_Log("Received chunk [%d, %d] verts=%d", data.coord[0], data.coord[2], data.vertices.length);
    app.concurrency.workers[tid] = false;
    app.finalizeChunk(cast(ChunkData)data);
  });
  // Check all pending texture transfers; promote to app.textures once GPU is done
  size_t i = 0;
  while(i < app.textures.pending.length) {
    auto p = app.textures.pending[i];
    if(vkGetFenceStatus(app.device, app.textures.pending[i].cmdBuffer.fence) == VK_SUCCESS) {
      app.destroyStagingBuffer(p.staging);
      SDL_DestroySurface(p.texture.surface);
      vkDestroyFence(app.device, p.cmdBuffer.fence, app.allocator);
      vkFreeCommandBuffers(app.device, p.cmdBuffer.pool, 1, &p.cmdBuffer.commands);
      app.textures ~= p.texture;
      app.textures.pending = app.textures.pending.remove(i);
      app.mapTextures();
    } else { i++; }
  }
}

