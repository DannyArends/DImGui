/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : createAllocation, cleanup;
import commandpool : beginSingleTimeCommands, endSingleTimeCommands;
import deletion : deAllocate;
import sync : bufferBarrier;
import validation : nameVulkanObject;

/** GPU SSBO: per-copy allocations, per-copy dirty flags, and layout. */
struct SSBO {
  GPUAllocation[] allocations;    /// Per-frame buffer copies (one per framesInFlight)
  alias allocations this;         /// An SSBO acts as its allocation array

  private bool[] dirty;           /// Per-copy upload-needed flag
  uint nObjects;                  /// Element capacity
  uint stride;                    /// Bytes per element
  bool deviceLocal;               /// Device-local (staged upload) vs host-visible (mapped)
  bool concurrent;                /// Shared across graphics + compute queue families

  @property @nogc uint size() nothrow const { return nObjects * stride; }
  @property @nogc bool buffered() nothrow const { foreach(d; dirty){ if(d){ return(false); } } return(true); }
  @nogc void invalidate() nothrow { dirty[] = true; }
  @nogc void invalidate(uint idx) nothrow { dirty[idx] = true; }
}

/** All SSBOs + the per-syncIndex "an SSBO grew, re-point this set" flags. */
struct SSBOStore {
  SSBO[string] ssbos;
  bool[] descriptorsDirty;   // per-syncIndex (length = framesInFlight)
  alias ssbos this;
}

/** CPU+GPU SSBO container with capacity tracking */
struct SSBOList(T) {
  T[] items;
  ulong capacity = 256;
  alias items this;
}

/** Name SSBO buffers and memory for debugging */
void nameSSBO(ref App app, SSBO ssbo, string name){
  for(uint i = 0; i < ssbo.length; i++) {
    app.nameVulkanObject(ssbo[i].buffer, cstr("[SSBO-BUF] %s #%d", name, i), VK_OBJECT_TYPE_BUFFER);
    app.nameVulkanObject(ssbo[i].memory, cstr("[SSBO-MEM] %s #%d", name, i), VK_OBJECT_TYPE_DEVICE_MEMORY);
  }
}

/** Create GPU SSBO buffer for nObjects. copies = per-frame buffer count (0 = app.framesInFlight).
 *  copies < framesInFlight is only safe for deviceLocal buffers ordered by a barrier within a frame;
 *  a host-visible buffer driven by updateSSBO needs framesInFlight copies or the CPU races the GPU. */
void createSSBO(ref App app, const Descriptor d, uint nObjects = 1024, bool deviceLocal = false, bool concurrent = false) {
  if(app.verbose) {
    SDL_Log("createSSBO %s, stride: %d, objects: %d, deviceLocal: %d, concurrent: %d", toStringz(d.base), d.bytes, nObjects, deviceLocal, concurrent);
  }
  if(d.base in app.buffers) return;
  app.buffers[d.base] = SSBO();
  app.buffers[d.base].nObjects = nObjects;
  app.buffers[d.base].stride = cast(uint)d.bytes;
  app.buffers[d.base].deviceLocal = deviceLocal;
  app.buffers[d.base].concurrent = concurrent;
  app.buffers[d.base].length = app.buffers[d.base].dirty.length = app.framesInFlight;

  foreach(i, ref allocation; app.buffers[d.base]) {
    app.createAllocation(allocation, app.buffers[d.base].size, deviceLocal, concurrent);
    app.buffers[d.base].dirty[i] = true;
  }
  app.nameSSBO(app.buffers[d.base], d.base);

  app.swapDeletionQueue.add((){
    if(app.verbose) SDL_Log("Deleting SSBO at %s", toStringz(d.base));
    foreach(ref allocation; app.buffers[d.base]){ app.cleanup(allocation); }
    app.buffers.ssbos.remove(d.base);
  });
}

/** Grow an SSBO in place: recreate each copy at the new size, defer-delete the old copies,
 *  remap host-visible data, flag descriptors for a targeted re-point. No swapchain/pipeline touch. */
void growSSBO(ref App app, string base, uint nObjects) {
  bool deviceLocal = app.buffers[base].deviceLocal;
  bool concurrent = app.buffers[base].concurrent;

  app.buffers[base].nObjects = nObjects;

  foreach(i, ref allocation; app.buffers[base]) {
    app.deAllocate(allocation);
    app.createAllocation(allocation, app.buffers[base].size, deviceLocal, concurrent);
    app.buffers[base].dirty[i] = true;
  }
  app.nameSSBO(app.buffers[base], base);
  app.buffers.descriptorsDirty[] = true;
  if(app.verbose) SDL_Log("growSSBO %s -> %d objects (%d bytes)", toStringz(base), nObjects, app.buffers[base].size);
}

/** Create GPU SSBO from container */
void createSSBO(T)(ref App app, const Descriptor descriptor, ref SSBOList!T container) {
  if(container.length > container.capacity) container.capacity = container.length;
  app.createSSBO(descriptor, cast(uint)container.capacity);
}

/** Upload container data to GPU, grow and rebuild if overflow */
void updateSSBO(T)(ref App app, VkCommandBuffer cmd, ref SSBOList!T container, Descriptor descriptor, uint syncIndex) {
  uint size = cast(uint)(T.sizeof * container.length);
  if(size == 0) return;
  if(size > app.buffers[descriptor.base].size) {
    while(container.capacity * T.sizeof < size) container.capacity *= 2;
    app.growSSBO(descriptor.base, cast(uint)container.capacity);
  }
  if(!app.buffers[descriptor.base].dirty[syncIndex]) return;
  if(app.trace) SDL_Log("updateSSBO: %s syncIndex=%d objects=%d", toStringz(descriptor.base), syncIndex, cast(uint)container.length);
  if(app.buffers[descriptor.base].deviceLocal) {
    GPUAllocation staging;
    app.createAllocation(staging, size, false);
    memcpy(staging.data, &container[0], size);
    VkBufferCopy region = { size : size };
    vkCmdCopyBuffer(cmd, staging.buffer, app.buffers[descriptor.base][syncIndex].buffer, 1, &region);
    // Compute-Write -> Vertex-Read barrier
    cmd.bufferBarrier(app.buffers[descriptor.base][syncIndex].buffer,
                      VK_ACCESS_SHADER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT,
                      VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_VERTEX_SHADER_BIT);
    app.deAllocate(staging);
  } else { memcpy(app.buffers[descriptor.base][syncIndex].data, &container[0], size); }
  app.buffers[descriptor.base].dirty[syncIndex] = false;
}

