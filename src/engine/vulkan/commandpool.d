/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import validation : pushLabel, popLabel, nameVulkanObject;

/** Structure returned as result of an (async) SingleTimeCommand submission */
struct SingleTimeCommand {
  bool async = false;       /// Is the transfer happening async ?
  VkFence fence;            /// If aSync the fence we need to wait for before data is on the GPU
  VkCommandPool pool;       /// The command pool the buffer was allocated from
  VkCommandBuffer commands; /// The command buffer used for this specific transfer
  alias commands this;
}

void createCommandPools(ref App app) {
  app.queues.graphics.pool = app.createCommandPool(app.queues.graphics.family);
  app.queues.transfer.pool = app.createCommandPool(app.queues.transfer.family);
  app.queues.compute.pool  = app.createCommandPool(app.queues.compute.family);

  app.nameVulkanObject(app.queues.graphics.pool, toStringz("[COMMANDPOOL] Graphics"), VK_OBJECT_TYPE_COMMAND_POOL);
  app.nameVulkanObject(app.queues.transfer.pool, toStringz("[COMMANDPOOL] Transfer"), VK_OBJECT_TYPE_COMMAND_POOL);
  app.nameVulkanObject(app.queues.compute.pool,  toStringz("[COMMANDPOOL] Compute"),  VK_OBJECT_TYPE_COMMAND_POOL);

  if(app.verbose) SDL_Log("createCommandPools gfx[%d]=%p transfer[%d]=%p compute[%d]=%p",
    app.queues.graphics.family, app.queues.graphics.pool, app.queues.transfer.family, app.queues.transfer.pool,
    app.queues.compute.family, app.queues.compute.pool);
}

VkCommandPool createCommandPool(ref App app, uint queueFamilyIndex) {
  VkCommandPool commandPool;

  VkCommandPoolCreateInfo poolInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    queueFamilyIndex: queueFamilyIndex,
    flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
  };
  enforceVK(vkCreateCommandPool(app.device, &poolInfo, null, &commandPool));
  app.mainDeletionQueue.add((){ vkDestroyCommandPool(app.device, commandPool, app.allocator); });

  if(app.trace) SDL_Log("Commandpool %p at queue %d created", commandPool, poolInfo.queueFamilyIndex);
  return(commandPool);
}

VkCommandBuffer[] createCommandBuffer(App app, VkCommandPool pool, uint nBuffers = 1) {
  VkCommandBuffer[] commandBuffer;
  commandBuffer.length = nBuffers;

  VkCommandBufferAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool: pool,
    level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount: nBuffers
  };
  enforceVK(vkAllocateCommandBuffers(app.device, &allocInfo, &(commandBuffer[0])));
  if(app.trace) SDL_Log("%d CommandBuffer(s) created from pool %p", nBuffers, pool);
  app.swapDeletionQueue.add((){ vkFreeCommandBuffers(app.device, pool, cast(uint)commandBuffer.length, &commandBuffer[0]); });
  return(commandBuffer);
}

/** beginSingleTimeCommands() begins a commandbuffer using the VkCommandPool pool
 * async: If true: add commands, submit to the correct queue. 
          If false: add commands, the use endSingleTimeCommands to submit and WaitIdle for the Queue */
SingleTimeCommand beginSingleTimeCommands(ref App app, VkCommandPool pool, bool async = false) {
  VkCommandBuffer commandBuffer = app.createCommandBuffer(pool, 1)[0];

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  vkBeginCommandBuffer(commandBuffer, &beginInfo);
  VkFence completionFence;
  if(async) {
    VkFenceCreateInfo fenceInfo = {
        sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        flags: 0
    };
    enforceVK(vkCreateFence(app.device, &fenceInfo, app.allocator, &completionFence));
  }
  return SingleTimeCommand(async, completionFence, pool, commandBuffer);
}

void endSingleTimeCommands(ref App app, SingleTimeCommand cmd, VkQueue queue) {
  if(cmd.async) assert(0, "Never endSingleTimeCommands() on Async events");
  vkEndCommandBuffer(cmd.commands);

  VkSubmitInfo submitInfo = {
    sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount: 1,
    pCommandBuffers: &cmd.commands
  };

  enforceVK(vkQueueSubmit(queue, 1, &submitInfo, null));
  enforceVK(vkQueueWaitIdle(queue));
  vkFreeCommandBuffers(app.device, cmd.pool, 1, &cmd.commands);
}
