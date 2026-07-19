/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import validation : nameVulkanObject;

/** A device queue paired with the family it came from */
struct Queue {
  VkQueue queue = null;
  uint family = uint.max;
  VkCommandPool pool = null;
  @property @nogc bool valid() nothrow const { return queue !is null; }
}

/** The three logical roles. Each resolves to a dedicated family when the device has one, else the graphics family/queue. */
struct Queues {
  Queue graphics;
  Queue compute;
  Queue transfer;
}

struct QueueSetup {
  uint gfxQueueCount;
  VkDeviceQueueCreateInfo[] createInfos;
  float[] priorities;
}

/** Find a family with `cap` that lacks GRAPHICS (dedicated), distinct from `avoid`. uint.max if none. */
uint findQueueFamily(VkPhysicalDevice physicalDevice, VkQueueFlagBits cap, uint avoid = uint.max, bool dedicatedOnly = false) {
  uint32_t n; vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &n, null);
  VkQueueFamilyProperties[] props; props.length = n;
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &n, &props[0]);

  uint generic = uint.max, dedicated = uint.max, dedicatedSize = 0;   // matching + no graphics bit (best)
  foreach(i, ref p; props) {
    if(cast(uint)i == avoid) continue;
    if(!(p.queueFlags & cap) || p.queueCount == 0) continue;
    if(!(p.queueFlags & VK_QUEUE_GRAPHICS_BIT)) {           // dedicated (non-graphics)
      if(p.queueCount > dedicatedSize) { dedicated = cast(uint)i; dedicatedSize = p.queueCount; }
    } else if(generic == uint.max) {generic = cast(uint)i; }// first generic (has graphics)
  }
  return((dedicated != uint.max) ? dedicated : (dedicatedOnly ? uint.max : generic));
}

/** Resolve families: graphics is the base; compute/transfer prefer a dedicated family, else fall back to graphics. */
QueueSetup findDedicatedQueues(ref App app) {
  uint gfxFamily      = findQueueFamily(app.physicalDevice(), VK_QUEUE_GRAPHICS_BIT);
  uint computeFamily  = findQueueFamily(app.physicalDevice(), VK_QUEUE_COMPUTE_BIT,  gfxFamily, true);
  uint transferFamily = findQueueFamily(app.physicalDevice(), VK_QUEUE_TRANSFER_BIT, gfxFamily, true);

  app.queues.graphics.family = gfxFamily;
  app.queues.compute.family  = (computeFamily  != uint.max) ? computeFamily  : gfxFamily;
  app.queues.transfer.family = (transferFamily != uint.max) ? transferFamily : gfxFamily;

  uint32_t n; vkGetPhysicalDeviceQueueFamilyProperties(app.physicalDevice(), &n, null);
  VkQueueFamilyProperties[] props; props.length = n;
  vkGetPhysicalDeviceQueueFamilyProperties(app.physicalDevice(), &n, &props[0]);

  uint gfxWant = 1;
  if(app.queues.transfer.family == gfxFamily) gfxWant++;
  if(app.queues.compute.family  == gfxFamily) gfxWant++;

  QueueSetup s = QueueSetup(min(gfxWant, props[gfxFamily].queueCount));
  s.priorities = new float[](16);
  s.priorities[] = 1.0f;

  VkDeviceQueueCreateInfo[uint] byFamily;
  void addFamily(uint fam, uint count) {
    if(fam in byFamily) return;
    VkDeviceQueueCreateInfo info = {
      sType : VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      queueFamilyIndex : fam, queueCount : count, pQueuePriorities : &s.priorities[0]
    };
    byFamily[fam] = info;
  }
  addFamily(gfxFamily, s.gfxQueueCount);
  addFamily(app.queues.transfer.family, 1);
  addFamily(app.queues.compute.family, 1);
  s.createInfos = byFamily.values;
  return(s);
}

void setupQueues(ref App app, const QueueSetup setup) {
  uint nextGfxSlot = 1;
  vkGetDeviceQueue(app.device, app.queues.graphics.family, 0, &app.queues.graphics.queue);
  // Transfer
  if(app.queues.transfer.family != app.queues.graphics.family){
    vkGetDeviceQueue(app.device, app.queues.transfer.family, 0, &app.queues.transfer.queue);
  }else if(nextGfxSlot < setup.gfxQueueCount){
    vkGetDeviceQueue(app.device, app.queues.transfer.family, nextGfxSlot++, &app.queues.transfer.queue);
  }else{
    app.queues.transfer.queue = app.queues.graphics.queue;   // ran out of slots: share graphics
  }
  // Compute
  if(app.queues.compute.family != app.queues.graphics.family){
    vkGetDeviceQueue(app.device, app.queues.compute.family, 0, &app.queues.compute.queue);
  }else if(nextGfxSlot < setup.gfxQueueCount){
    vkGetDeviceQueue(app.device, app.queues.compute.family, nextGfxSlot++, &app.queues.compute.queue);
  }else{
    app.queues.compute.queue = app.queues.graphics.queue;    // ran out: share graphics
  }
  app.nameVulkanObject(app.queues.graphics.queue, toStringz("[QUEUE] Graphics"), VK_OBJECT_TYPE_QUEUE);
  app.nameVulkanObject(app.queues.transfer.queue, toStringz("[QUEUE] Transfer"), VK_OBJECT_TYPE_QUEUE);
  app.nameVulkanObject(app.queues.compute.queue,  toStringz("[QUEUE] Compute"),  VK_OBJECT_TYPE_QUEUE);
}
