/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : createAllocation, createBuffer;
import deletion : deAllocate;
import validation : nameVulkanObject;

struct GeometryBuffer(T = ubyte) {
  VkBuffer[] vb = null;           /// Per-frame device buffers
  VkDeviceMemory[] vbM = null;    /// Backing memory for each vb
  GPUAllocation[] staging;        /// Host-visible upload staging (released once buffered)
  VkDeviceSize[] size;            /// Bytes uploaded per copy
  VkDeviceSize capacity = 0;      /// Allocated bytes per copy (grow-only)

  PackedArray!T data;             /// CPU-side element store
  alias data this;                /// A GeometryBuffer acts as its element store
  private bool[] dirty;           /// Per-copy upload-needed flag
  bool keepStaging = false;       /// Retain staging after upload (for frequently-updated buffers)

  @property @nogc bool buffered() nothrow const { foreach(d; dirty) if(d) return false; return true; }
  @nogc void invalidate() nothrow { dirty[] = true; }
  @nogc void invalidate(uint idx) nothrow { dirty[idx] = true; }
  @property @nogc bool needsBuffer() nothrow const { return(data.length > 0 && (vb.length == 0 || !buffered)); }
  @property @nogc bool drawable() nothrow const { return(vb.length > 0 && data.length > 0); }
  @nogc uint count(uint idx) nothrow const { return(idx < size.length ? cast(uint)(size[idx] / T.sizeof) : 0); }
  @nogc uint slot(uint sync) nothrow const { return(vb.length ? sync % cast(uint)vb.length : 0); }
}

@nogc void cleanup(T)(ref App app, ref GeometryBuffer!T buffer) nothrow {
  import buffer : cleanup;
  foreach(i; 0 .. buffer.staging.length){ app.cleanup(buffer.staging[i]); }
  foreach(i; 0 .. buffer.vb.length) {
    if(buffer.vb[i]) vkDestroyBuffer(app.device, buffer.vb[i], app.allocator);
    if(buffer.vbM[i]) vkFreeMemory(app.device, buffer.vbM[i], app.allocator);
  }
  buffer = GeometryBuffer!T();
}

void nameGeometryBuffer(T)(ref App app, GeometryBuffer!T buffer, string type, string name){
  foreach(i; 0 .. buffer.vb.length) {
    app.nameVulkanObject(buffer.vb[i], toStringz("["~type~"-BUF] " ~ name), VK_OBJECT_TYPE_BUFFER);
    app.nameVulkanObject(buffer.vbM[i], toStringz("["~type~"-MEM] " ~ name), VK_OBJECT_TYPE_DEVICE_MEMORY);
  }
  foreach(i; 0 .. buffer.staging.length) {
    app.nameVulkanObject(buffer.staging[i].buffer, toStringz("["~type~"-STAGE-BUF] " ~ name), VK_OBJECT_TYPE_BUFFER);
    app.nameVulkanObject(buffer.staging[i].memory, toStringz("["~type~"-STAGE-MEM] " ~ name), VK_OBJECT_TYPE_DEVICE_MEMORY);
  }
}

/** Allocate or grow a GeometryBuffer if needed */
bool allocateBuffer(T)(ref App app, ref GeometryBuffer!T buffer, VkBufferUsageFlags usage,
                       VkMemoryPropertyFlagBits properties = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
  if(app.trace) SDL_Log("allocateBuffer: Transferring %d x %d = %d bytes", T.sizeof, buffer.items.length, T.sizeof * buffer.items.length);
  VkDeviceSize requiredSize = cast(uint)(T.sizeof * buffer.items.length);
  if(requiredSize <= buffer.capacity) return(false);

  VkDeviceSize newCapacity = requiredSize > 0 ? (requiredSize * 2) : 256;
  if(buffer.vb.length > 0) { app.deAllocate(buffer); }

  buffer.vb = new VkBuffer[app.framesInFlight];
  buffer.vbM = new VkDeviceMemory[app.framesInFlight];
  buffer.size = new VkDeviceSize[app.framesInFlight];
  buffer.dirty = new bool[app.framesInFlight];
  buffer.staging = new GPUAllocation[app.framesInFlight];

  foreach(i; 0 .. app.framesInFlight) {
    app.createAllocation(buffer.staging[i], cast(uint)newCapacity, false);   // host-visible + mapped
    app.createBuffer(&buffer.vb[i], &buffer.vbM[i], newCapacity, usage, properties);
    buffer.dirty[i] = true;
  }
  buffer.capacity = newCapacity;
  return(true);
}

/** Release a fully-uploaded buffer's host-visible staging; deferred so in-flight copies finish first. */
void releaseStaging(T)(ref App app, ref GeometryBuffer!T buffer) {
  foreach(i; 0 .. buffer.staging.length) { if(buffer.staging[i].buffer) { app.deAllocate(buffer.staging[i]); } }
  buffer.staging = null;
}

/** Collapse device copies to one once all have converged; the extras are freed after in-flight frames drain. */
void shrinkCopies(T)(ref App app, ref GeometryBuffer!T buffer) {
  if(buffer.vb.length <= 1) return;
  VkBuffer[] oldVb = buffer.vb[1 .. $].dup;
  VkDeviceMemory[] oldVbM = buffer.vbM[1 .. $].dup;
  buffer.vb = buffer.vb[0 .. 1];
  buffer.vbM = buffer.vbM[0 .. 1];
  auto deadline = app.totalFramesRendered + app.framesInFlight;
  app.bufferDeletionQueue.add((bool force) @nogc nothrow {
    if(!force && app.totalFramesRendered < deadline) return(false);
    foreach(i; 0 .. oldVb.length) {
      if(oldVb[i])  vkDestroyBuffer(app.device, oldVb[i], app.allocator);
      if(oldVbM[i]) vkFreeMemory(app.device, oldVbM[i], app.allocator);
    }
    return(true);
  });
}

/** (Re)create staging if it was released but the buffer needs uploading again. No-op when present. */
void ensureStaging(T)(ref App app, ref GeometryBuffer!T buffer) {
  if(buffer.staging.length == app.framesInFlight && buffer.staging[0].buffer) return;
  buffer.staging = new GPUAllocation[app.framesInFlight];
  foreach(i; 0 .. app.framesInFlight) { app.createAllocation(buffer.staging[i], cast(uint)buffer.capacity, false); }
}

/** Upload CPU data to GPU via staging buffer (caller must issue a transfer→read barrier after batching) */
void uploadBuffer(T)(ref App app, ref GeometryBuffer!T buffer, VkCommandBuffer cmdBuffer) {
  if(!buffer.dirty[app.syncIndex]) return;
  app.ensureStaging(buffer);                                    // <-- re-create if a static buffer went dirty
  buffer.size[app.syncIndex] = cast(uint)(T.sizeof * buffer.items.length);
  memcpy(buffer.staging[app.syncIndex].data, cast(void*)buffer.items, buffer.size[app.syncIndex]);
  VkBufferCopy copyRegion = { size : buffer.size[app.syncIndex] };
  vkCmdCopyBuffer(cmdBuffer, buffer.staging[app.syncIndex].buffer, buffer.vb[app.syncIndex], 1, &copyRegion);
  buffer.dirty[app.syncIndex] = false;
  if(!buffer.keepStaging && buffer.buffered) app.releaseStaging(buffer);
}

/** Allocate if needed then upload — convenience wrapper */
void toGPU(T)(ref App app, ref GeometryBuffer!T buffer, VkCommandBuffer cmdBuffer, VkBufferUsageFlags usage, string type = "", string name = "",
              VkMemoryPropertyFlagBits properties = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
  if(!buffer.needsBuffer) return;
  if(app.trace) SDL_Log("toGPU: Transferring %d x %d = %d bytes", T.sizeof, buffer.items.length, T.sizeof * buffer.items.length);
  if(buffer.vb.length > 0 && buffer.vb.length < app.framesInFlight) buffer.capacity = 0;  // a settled (1-copy) buffer went dirty: regrow to framesInFlight
  if(app.allocateBuffer(buffer, usage, properties)) app.nameGeometryBuffer(buffer, type, name);
  app.uploadBuffer(buffer, cmdBuffer);
  if(buffer.buffered && buffer.vb.length > 1) app.shrinkCopies(buffer);   // every copy now holds identical data: keep one, retire the rest
}