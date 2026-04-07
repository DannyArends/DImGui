/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import boundingbox : computeBoundingBox;
import descriptor : updateDescriptorData;
import geometry : draw, bufferGeometries;
import ssbo : updateSSBO;
import validation : pushLabel, popLabel, nameVulkanObject;
import window: supportedTopologies;

/** Record scene command buffer: SSBO -> Objects -> Rendering
 */
void recordSceneCommandBuffer(ref App app, Shader[] shaders, uint syncIndex) {
  auto cmd = app.scenePass.commands[syncIndex];
  if(app.trace) SDL_Log("recordSceneCommandBuffer %d recording to frame: %d/%d", syncIndex, app.frameIndex, app.scenePass.framebuffers.length);

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    pInheritanceInfo: null
  };
  enforceVK(vkResetCommandBuffer(cmd, 0)); // Reset for recording
  enforceVK(vkBeginCommandBuffer(cmd, &beginInfo));
  app.nameVulkanObject(cmd, toStringz(format("[COMMANDBUFFER] Render %d", syncIndex)), VK_OBJECT_TYPE_COMMAND_BUFFER);

  pushLabel(cmd, "SSBO Buffering", Colors.lightgray);
  if(app.trace) SDL_Log("SSBO Buffering");
  app.updateDescriptorData(shaders, app.scenePass.commands, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, syncIndex);
  popLabel(cmd);

  pushLabel(cmd, "Objects Buffering", Colors.lightgray);
  if(app.trace) SDL_Log("Objects Buffering");
  app.bufferGeometries(cmd);
  popLabel(cmd);

  pushLabel(cmd, "Rendering", Colors.lightgray);
  if(app.trace) SDL_Log("Starting Scene renderpass");

  app.scenePass.begin(cmd, app.frameIndex, app.camera.currentExtent, app.clearValue);
  if(app.trace) SDL_Log("Render pass recording to buffer %d", syncIndex);

  if(app.trace) SDL_Log("Going to draw %d objects to renderBuffer %d", app.objects.length, syncIndex);
  foreach(topology; supportedTopologies) {
    pushLabel(cmd, toStringz(format("T:%s", topology)), Colors.lightgray);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipelines[topology].pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, 
                            app.pipelines[topology].layout, 0, 1, &app.sets[Stage.RENDER][syncIndex], 0, null);
    
    for(size_t x = 0; x < app.objects.length; x++) {
      if(!app.objects[x].isVisible) continue;
      if(topology == VK_PRIMITIVE_TOPOLOGY_LINE_LIST && app.showBounds) app.draw(app.objects[x].box, syncIndex);
      if(app.objects[x].topology != topology) continue;
      app.draw(app.objects[x], syncIndex);
    }
    popLabel(cmd);
  }
  app.scenePass.end(cmd);
  popLabel(cmd);

  enforceVK(vkEndCommandBuffer(cmd));
}

/** Record post-process command buffer
 */
void recordPostCommandBuffer(ref App app, uint syncIndex) {
  auto cmd = app.postPass.commands[syncIndex];
  if(app.trace) SDL_Log("recordPostCommandBuffer %d", syncIndex);

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    pInheritanceInfo: null
  };
  enforceVK(vkResetCommandBuffer(cmd, 0)); // Reset for recording
  enforceVK(vkBeginCommandBuffer(cmd, &beginInfo));
  app.nameVulkanObject(cmd, toStringz(format("[COMMANDBUFFER] Post %d", syncIndex)), VK_OBJECT_TYPE_COMMAND_BUFFER);

  pushLabel(cmd, "Post-processing", Colors.lightgray);
  if(app.trace) SDL_Log("Starting Post-processing");

  app.postPass.begin(cmd, app.frameIndex, app.camera.currentExtent, app.clearValue[0..1]);

  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.postProcessPipeline.pipeline);
  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, 
                          app.postProcessPipeline.layout, 0, 1, &app.sets[Stage.POST][syncIndex], 0, null);

  vkCmdDraw(cmd, 3, 1, 0, 0);
  app.postPass.end(cmd);
  popLabel(cmd);
  if(app.trace) SDL_Log("Finished Post-processing");
  enforceVK(vkEndCommandBuffer(cmd));
}

void createCommandPools(ref App app) {
  app.commandPool = app.createCommandPool(app.queueFamily);
  app.transferPool = app.createCommandPool(app.queueFamily);

  app.nameVulkanObject(app.commandPool, toStringz("[COMMANDPOOL] Render"), VK_OBJECT_TYPE_COMMAND_POOL);
  app.nameVulkanObject(app.transferPool, toStringz("[COMMANDPOOL] Transfer"), VK_OBJECT_TYPE_COMMAND_POOL);

  if(app.verbose) SDL_Log("createCommandPools[family:%d] Queue: %p, Transfer: %p", app.queueFamily, app.commandPool, app.transferPool);
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

void createCommandBuffer(ref App app, ref VkCommandBuffer[] dst, VkCommandPool pool, uint nBuffers = 1) { 
  dst = app.createCommandBuffer(pool, nBuffers);
}

// Structure returned as result of an (async) SingleTimeCommand submission
struct SingleTimeCommand {
  bool async = false;       /// Is the transfer happening async ?
  VkFence fence;            /// If aSync the fence we need to wait for before data is on the GPU
  VkCommandPool pool;       /// The command pool the buffer was allocated from
  VkCommandBuffer commands; /// The command buffer used for this specific transfer
  alias commands this;
}

/** beginSingleTimeCommands() begins a commandbuffer using the VkCommandPool pool
 * async: If true: add commands, submit to the correct queue. 
          If false: add commands, the use endSingleTimeCommands to submit and WaitIdle for the Queue
 */
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
    app.mainDeletionQueue.add((){
      vkDestroyFence(app.device, completionFence, app.allocator);
      vkFreeCommandBuffers(app.device, pool, 1, &commandBuffer);
    });
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
