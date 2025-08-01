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

/** Record Vulkan render command buffer by rendering all objects to all render buffers
 * SSBO Buffering -> Objects Buffering -> Rendering -> Post-processing
 */
void recordRenderCommandBuffer(ref App app, Shader[] shaders, uint syncIndex) {
  if(app.trace) SDL_Log("recordRenderCommandBuffer %d recording to frame: %d/%d", syncIndex, app.frameIndex, app.framebuffers.scene.length);

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    pInheritanceInfo: null // Optional
  };
  enforceVK(vkBeginCommandBuffer(app.renderBuffers[syncIndex], &beginInfo));
  app.nameVulkanObject(app.renderBuffers[syncIndex], toStringz(format("[COMMANDBUFFER] Render %d", syncIndex)), VK_OBJECT_TYPE_COMMAND_BUFFER);

  pushLabel(app.renderBuffers[app.syncIndex], "SSBO Buffering", Colors.lightgray);
  if(app.trace) SDL_Log("SSBO Buffering");
  app.updateDescriptorData(shaders, app.renderBuffers, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, syncIndex);
  popLabel(app.renderBuffers[app.syncIndex]);

  pushLabel(app.renderBuffers[app.syncIndex], "Objects Buffering", Colors.lightgray);
  if(app.trace) SDL_Log("Objects Buffering");
  app.bufferGeometries(app.renderBuffers[syncIndex]);
  popLabel(app.renderBuffers[app.syncIndex]);

  pushLabel(app.renderBuffers[app.syncIndex], "Rendering", Colors.lightgray);
  if(app.trace) SDL_Log("Starting Scene renderpass");

  VkRect2D renderArea = { extent: { width: app.camera.width, height: app.camera.height } };

  VkRenderPassBeginInfo renderPassInfo = {
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass: app.scene,
    framebuffer: app.framebuffers.scene[app.frameIndex],
    renderArea: renderArea,
    clearValueCount: app.clearValue.length,
    pClearValues: &app.clearValue[0]
  };
  vkCmdBeginRenderPass(app.renderBuffers[syncIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
  if(app.trace) SDL_Log("Render pass recording to buffer %d", syncIndex);

  if(app.trace) SDL_Log("Going to draw %d objects to renderBuffer %d", app.objects.length, syncIndex);
  foreach(topology; supportedTopologies) {
    pushLabel(app.renderBuffers[app.syncIndex], toStringz(format("T:%s", topology)), Colors.lightgray);
    vkCmdBindPipeline(app.renderBuffers[syncIndex], VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipelines[topology].pipeline);
    vkCmdBindDescriptorSets(app.renderBuffers[syncIndex], VK_PIPELINE_BIND_POINT_GRAPHICS, 
                            app.pipelines[topology].layout, 0, 1, &app.sets[Stage.RENDER][syncIndex], 0, null);
    
    for(size_t x = 0; x < app.objects.length; x++) {
      if(!app.objects[x].isVisible) continue;
      if(topology == VK_PRIMITIVE_TOPOLOGY_LINE_LIST && app.showBounds) app.draw(app.objects[x].box, syncIndex);
      if(app.objects[x].topology != topology) continue;
      app.draw(app.objects[x], syncIndex);
    }
    popLabel(app.renderBuffers[app.syncIndex]);
  }
  vkCmdEndRenderPass(app.renderBuffers[syncIndex]);

  popLabel(app.renderBuffers[app.syncIndex]);

  if(app.trace) SDL_Log("Starting Post-processing");
  pushLabel(app.renderBuffers[app.syncIndex], "Post-processing", Colors.lightgray);
  VkRenderPassBeginInfo postProcessRenderPassInfo = {
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass: app.postprocess,                                        /// Use post-processing render pass
    framebuffer: app.framebuffers.postprocess[app.frameIndex],          /// Use its dedicated framebuffer
    renderArea: { offset: {0, 0}, extent: app.camera.currentExtent },
    clearValueCount: 1,
    pClearValues: &app.clearValue[0]
  };

  vkCmdBeginRenderPass(app.renderBuffers[app.syncIndex], &postProcessRenderPassInfo, VK_SUBPASS_CONTENTS_INLINE);

  // Bind post-process pipeline & descriptor set (for sampling HDR texture)
  vkCmdBindPipeline(app.renderBuffers[app.syncIndex], VK_PIPELINE_BIND_POINT_GRAPHICS, app.postProcessPipeline.pipeline);
  vkCmdBindDescriptorSets(app.renderBuffers[app.syncIndex], VK_PIPELINE_BIND_POINT_GRAPHICS, 
                          app.postProcessPipeline.layout, 0, 1, &app.sets[Stage.POST][app.syncIndex], 0, null);

  vkCmdDraw(app.renderBuffers[app.syncIndex], 3, 1, 0, 0);
  vkCmdEndRenderPass(app.renderBuffers[app.syncIndex]);
  popLabel(app.renderBuffers[app.syncIndex]);
  if(app.trace) SDL_Log("Finished Post-processing");
  enforceVK(vkEndCommandBuffer(app.renderBuffers[syncIndex]));
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

  vkQueueSubmit(queue, 1, &submitInfo, null);
  vkQueueWaitIdle(queue);

  vkFreeCommandBuffers(app.device, cmd.pool, 1, &cmd.commands);
}
