/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import bone : getBoneOffsets;
import color : Colors;
import descriptor : Descriptor;
import matrix : Matrix;
import mesh : Mesh, getMeshes;
import boundingbox : computeBoundingBox;
import geometry : draw;
import shaders : Shader;
import ssbo : updateSSBO;
import validation : pushLabel, popLabel;

/** Record Vulkan render command buffer by rendering all objects to all render buffers
 */
void recordRenderCommandBuffer(ref App app, Shader[] shaders, uint syncIndex) {
  if(app.trace) SDL_Log("recordRenderCommandBuffer");

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    pInheritanceInfo: null // Optional
  };
  enforceVK(vkBeginCommandBuffer(app.renderBuffers[syncIndex], &beginInfo));
  pushLabel(app.renderBuffers[app.syncIndex], "SSBO Buffering", Colors.lightgray);
  if(app.trace) SDL_Log("renderBuffer %d recording to frame: %d/%d", syncIndex, app.frameIndex, app.swapChainFramebuffers.length);

  VkRect2D renderArea = {
    offset: { x:0, y:0 },
    extent: { width: app.camera.width, height: app.camera.height }
  };

  VkRenderPassBeginInfo renderPassInfo = {
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass: app.renderpass,
    framebuffer: app.swapChainFramebuffers[app.frameIndex],
    renderArea: renderArea,
    clearValueCount: app.clearValue.length,
    pClearValues: &app.clearValue[0]
  };

  foreach(shader; shaders) {
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
        if(SDL_strstr(shader.descriptors[d].base, "BoneMatrices") != null) {
          // Always update the bones for animation on each frame
          Matrix[] offsets = app.getBoneOffsets();
          app.updateSSBO!Matrix(app.renderBuffers[syncIndex], offsets, shader.descriptors[d], syncIndex);
        }
        if(SDL_strstr(shader.descriptors[d].base, "MeshMatrices") != null) {
          // Todo: we should do this data transfer only when needed (a material changed)
          Mesh[] meshes = app.getMeshes();
          app.updateSSBO!Mesh(app.renderBuffers[syncIndex], meshes, shader.descriptors[d], syncIndex);
        }
      }
    }
  }
  popLabel(app.renderBuffers[app.syncIndex]);

  pushLabel(app.renderBuffers[app.syncIndex], "Objects Buffering", Colors.lightgray);
  for(size_t x = 0; x < app.objects.length; x++) {
    if(app.showBounds) {
      app.objects[x].computeBoundingBox(app.trace);
      app.objects[x].box.buffer(app, app.renderBuffers[syncIndex]);
    }
    if(!app.objects[x].isBuffered) {
      if(app.trace) SDL_Log("Buffer object: %d %p", x, app.objects[x]);
      app.objects[x].buffer(app, app.renderBuffers[syncIndex]);
    }
  }
  popLabel(app.renderBuffers[app.syncIndex]);

  pushLabel(app.renderBuffers[app.syncIndex], "Rendering", Colors.lightgray);
  vkCmdBeginRenderPass(app.renderBuffers[syncIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
  if(app.trace) SDL_Log("Render pass recording to buffer %d", syncIndex);

  if(app.trace) SDL_Log("Going to draw %d objects to renderBuffer %d", app.objects.length, syncIndex);
  for(size_t x = 0; x < app.objects.length; x++) {
    if(app.objects[x].isVisible) app.draw(app.objects[x], syncIndex);
    if(app.showBounds) app.draw(app.objects[x].box, syncIndex);
  }
  vkCmdEndRenderPass(app.renderBuffers[syncIndex]);

  popLabel(app.renderBuffers[app.syncIndex]);

  enforceVK(vkEndCommandBuffer(app.renderBuffers[syncIndex]));
  if(app.trace) SDL_Log("Render pass finished to %d", syncIndex);

}

void createCommandPools(ref App app){
  app.commandPool = app.createCommandPool();
  app.transferPool = app.createCommandPool();
  SDL_Log("createCommandPool[family:%d] queue: %p,  transfer: %p", app.queueFamily, app.commandPool, app.transferPool);
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

void createImGuiCommandBuffers(ref App app) { 
  app.imguiBuffers = app.createCommandBuffer(app.commandPool, app.framesInFlight);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.framesInFlight; i++) {
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.imguiBuffers[i]);
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

void createRenderCommandBuffers(ref App app) { 
  app.renderBuffers = app.createCommandBuffer(app.commandPool, app.framesInFlight);
  if(app.trace) SDL_Log("createRenderCommandBuffers: %d RenderBuffer, commandpool[%p]", app.renderBuffers.length, app.commandPool);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.framesInFlight; i++) {
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.renderBuffers[i]);
    }
  });
}

