/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : Colors;
import descriptor : Descriptor, updateDescriptorData;
import boundingbox : computeBoundingBox;
import geometry : draw, bufferGeometries;
import shaders : Shader;
import ssbo : updateSSBO;
import validation : pushLabel, popLabel;
import window: supportedTopologies;

/** Record Vulkan render command buffer by rendering all objects to all render buffers
 */
void recordRenderCommandBuffer(ref App app, Shader[] shaders, uint syncIndex) {
  if(app.trace) SDL_Log("recordRenderCommandBuffer %d recording to frame: %d/%d", syncIndex, app.frameIndex, app.framebuffers.scene.length);

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    pInheritanceInfo: null // Optional
  };
  enforceVK(vkBeginCommandBuffer(app.renderBuffers[syncIndex], &beginInfo));

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
                            app.pipelines[topology].layout, 0, 1, &app.sets[RENDER][syncIndex], 0, null);
    
    for(size_t x = 0; x < app.objects.length; x++) {
      if(topology == VK_PRIMITIVE_TOPOLOGY_LINE_LIST && app.showBounds) app.draw(app.objects[x].box, syncIndex);
      if(app.objects[x].topology != topology) continue;
      if(app.objects[x].isVisible) app.draw(app.objects[x], syncIndex);
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
                          app.postProcessPipeline.layout, 0, 1, &app.sets[POST][app.syncIndex], 0, null);

  vkCmdDraw(app.renderBuffers[app.syncIndex], 3, 1, 0, 0);
  vkCmdEndRenderPass(app.renderBuffers[app.syncIndex]);
  popLabel(app.renderBuffers[app.syncIndex]);
  if(app.trace) SDL_Log("Finished Post-processing");
  enforceVK(vkEndCommandBuffer(app.renderBuffers[syncIndex]));
}

void createCommandPools(ref App app) {
  app.commandPool = app.createCommandPool();
  app.transferPool = app.createCommandPool();
  if(app.verbose) SDL_Log("createCommandPools[family:%d] Queue: %p, Transfer: %p", app.queueFamily, app.commandPool, app.transferPool);
}

VkCommandPool createCommandPool(ref App app) {
  VkCommandPool commandPool;

  VkCommandPoolCreateInfo poolInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    queueFamilyIndex: app.queueFamily,
    flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
  };
  enforceVK(vkCreateCommandPool(app.device, &poolInfo, null, &commandPool));
  app.mainDeletionQueue.add((){ vkDestroyCommandPool(app.device, commandPool, app.allocator); });

  if(app.trace) SDL_Log("Commandpool %p at queue %d created", commandPool, poolInfo.queueFamilyIndex);
  return(commandPool);
}

VkCommandBuffer[] createCommandBuffer(App app, VkCommandPool commandPool, uint nBuffers = 1) {
  VkCommandBuffer[] commandBuffer;
  commandBuffer.length = nBuffers;

  VkCommandBufferAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool: commandPool,
    level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount: nBuffers
  };
  enforceVK(vkAllocateCommandBuffers(app.device, &allocInfo, &(commandBuffer[0])));
  if(app.trace) SDL_Log("%d CommandBuffer created for pool %p", allocInfo.commandBufferCount, commandPool);
  return(commandBuffer);
}

void createCommandBuffers(ref App app, ref VkCommandBuffer[] dst) { 
  dst = app.createCommandBuffer(app.commandPool, app.framesInFlight);
  if(app.trace) SDL_Log("createRenderCommandBuffers: %d RenderBuffer, commandpool[%p]", app.renderBuffers.length, app.commandPool);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.framesInFlight; i++) {
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &dst[i]);
    }
  });
}

VkCommandBuffer beginSingleTimeCommands(ref App app, VkCommandPool pool) {
  VkCommandBuffer[1] commandBuffer = app.createCommandBuffer(pool, 1);

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  vkBeginCommandBuffer(commandBuffer[0], &beginInfo);
  return commandBuffer[0];
}

void endSingleTimeCommands(ref App app, VkCommandBuffer commandBuffer, VkCommandPool pool, VkQueue queue) {
  vkEndCommandBuffer(commandBuffer);

  VkSubmitInfo submitInfo = {
    sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount: 1,
    pCommandBuffers: &commandBuffer
  };

  vkQueueSubmit(queue, 1, &submitInfo, null);
  vkQueueWaitIdle(queue);

  vkFreeCommandBuffers(app.device, pool, 1, &commandBuffer);
}


