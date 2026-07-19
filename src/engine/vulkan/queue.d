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
uint findDedicatedFamily(VkPhysicalDevice physicalDevice, VkQueueFlagBits cap, uint avoid) {
  uint32_t n; vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &n, null);
  VkQueueFamilyProperties[] props; props.length = n;
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &n, &props[0]);
  foreach(i, ref p; props) {
    if(cast(uint)i == avoid) continue;
    if((p.queueFlags & cap) && !(p.queueFlags & VK_QUEUE_GRAPHICS_BIT) && p.queueCount > 0) return cast(uint)i;
  }
  return uint.max;
}

/** Resolve families: graphics is the base; compute/transfer prefer a dedicated family, else fall back to graphics. */
VkDeviceQueueCreateInfo[] findDedicatedQueues(ref App app, ref uint gfxQueueCount){
  uint gfxFamily = selectQueueFamily(app.physicalDevice(), VK_QUEUE_GRAPHICS_BIT);
  uint computeFamily = findDedicatedFamily(app.physicalDevice(), VK_QUEUE_COMPUTE_BIT, gfxFamily);
  uint transferFamily = findDedicatedFamily(app.physicalDevice(), VK_QUEUE_TRANSFER_BIT, gfxFamily);

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
    SDL_Log("[queues] families available: %d", n);
  SDL_Log("[queues] resolved: gfx=%d compute=%d transfer=%d", gfxFamily, app.queues.compute.family, app.queues.transfer.family);
  SDL_Log("[queues] gfxQueueCount(clamped)=%d, gfx family has %d queues", gfxQueueCount, props[gfxFamily].queueCount);
  SDL_Log("[queues] createQueue.length=%d", cast(int)createQueue.length);
  foreach(i, ref ci; createQueue) {
    SDL_Log("[queues]   [%d] sType=%d family=%d count=%d pPrio=%p pNext=%p flags=%d",
            cast(int)i, cast(int)ci.sType, ci.queueFamilyIndex, ci.queueCount,
            ci.pQueuePriorities, ci.pNext, ci.flags);
  }
  
  return createQueue;
}

uint selectQueueFamily(VkPhysicalDevice physicalDevice, VkQueueFlagBits requested = VK_QUEUE_GRAPHICS_BIT) {
  uint32_t nQueue;
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &nQueue, null);
  VkQueueFamilyProperties[] queueProperties;
  queueProperties.length = nQueue;
  vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &nQueue, &queueProperties[0]);

  uint bestDedicatedIndex = uint.max;
  uint maxDedicatedSize = 0;
  uint firstGenericIndex = uint.max;

  // Find the best dedicated queue and the first available generic queue in a single pass
  foreach(i, ref queueProperty; queueProperties) {
    if (queueProperty.queueFlags & requested) {
      if (!(queueProperty.queueFlags & VK_QUEUE_GRAPHICS_BIT)) { // DEDICATED (non GFX) queue
        if (queueProperty.queueCount > maxDedicatedSize) {
          bestDedicatedIndex = cast(uint)i;
          maxDedicatedSize = queueProperty.queueCount;
        }
      } else { // GENERIC queue
        if (firstGenericIndex == uint.max) { firstGenericIndex = cast(uint)i; }
      }
    }
  }
  if (bestDedicatedIndex != uint.max){
    SDL_Log("Dedicated queue family: %d with size %d", bestDedicatedIndex, maxDedicatedSize);
    return bestDedicatedIndex;
  }
  if (firstGenericIndex != uint.max){
    SDL_Log("Generic queue family: %d", firstGenericIndex);
    return firstGenericIndex;
  }
  assert(0, format("No suitable Queue Found for: %s", requested));
}