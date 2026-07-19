/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

__gshared float[16] queuePriority = 1.0f;

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
VkDeviceQueueCreateInfo[] findDedicatedQueues(ref App app, ref uint gfxQueueCount){
uint gfxFamily      = findQueueFamily(app.physicalDevice(), VK_QUEUE_GRAPHICS_BIT);
  uint computeFamily  = findQueueFamily(app.physicalDevice(), VK_QUEUE_COMPUTE_BIT,  gfxFamily, true);
  uint transferFamily = findQueueFamily(app.physicalDevice(), VK_QUEUE_TRANSFER_BIT, gfxFamily, true);

  app.queues.graphics.family = gfxFamily;
  app.queues.compute.family  = (computeFamily  != uint.max) ? computeFamily  : gfxFamily;
  app.queues.transfer.family = (transferFamily != uint.max) ? transferFamily : gfxFamily;

  // How many queues does each family actually support?
  uint32_t n; vkGetPhysicalDeviceQueueFamilyProperties(app.physicalDevice(), &n, null);
  VkQueueFamilyProperties[] props; props.length = n;
  vkGetPhysicalDeviceQueueFamilyProperties(app.physicalDevice(), &n, &props[0]);

  // Graphics family needs a queue for graphics + any role that falls back to it. Clamp to available.
  uint gfxWant = 1;                                                   // graphics
  if(app.queues.transfer.family == gfxFamily) gfxWant++;             // transfer fallback
  if(app.queues.compute.family  == gfxFamily) gfxWant++;             // compute fallback
  gfxQueueCount = min(gfxWant, props[gfxFamily].queueCount);          // CLAMP — never request more than exist

  uint[] families; VkDeviceQueueCreateInfo[] createQueue;
  void addFamily(uint fam, uint count) {
    foreach(f; families) if(f == fam) return;
    families ~= fam;
    VkDeviceQueueCreateInfo info = {
      sType : VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      queueFamilyIndex : fam, queueCount : count, pQueuePriorities : &queuePriority[0]
    };
    createQueue ~= info;
  }
  addFamily(gfxFamily, gfxQueueCount);
  if(app.queues.transfer.family != gfxFamily) addFamily(app.queues.transfer.family, 1);
  if(app.queues.compute.family  != gfxFamily) addFamily(app.queues.compute.family, 1);
  return createQueue;
}
