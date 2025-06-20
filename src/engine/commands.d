/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.string : toStringz;

import bone : getBoneOffsets;
import buffer : createBuffer;
import descriptor : Descriptor;
import matrix : Matrix;
import boundingbox : computeBoundingBox;
import geometry : draw;
import shaders : Shader;
import sdl : STARTUP;

void bonesToSSBO(ref App app, VkBuffer dst, uint syncIndex) {
  // Convert time to animation ticks and wrap it
  auto t = SDL_GetTicks() - app.time[STARTUP];

  double timeInTicks = (t / 10000.0f) * app.animations[app.animation].ticksPerSecond;
  double currentTick = fmod(timeInTicks, app.animations[app.animation].duration / app.animations[app.animation].ticksPerSecond);
  //SDL_Log("%f = %f  %f", t/ 1000.0f, timeInTicks, currentTick);
  Matrix[] offsets = app.getBoneOffsets(currentTick);

  uint size = cast(uint)(Matrix.sizeof * offsets.length);

  void* data;
  VkBuffer stagingBuffer;
  VkDeviceMemory stagingBufferMemory;

  app.createBuffer(&stagingBuffer, &stagingBufferMemory, size);
  vkMapMemory(app.device, stagingBufferMemory, 0, size, 0, &data);
  memcpy(data, &offsets[0], size);
  vkUnmapMemory(app.device, stagingBufferMemory);

  VkBufferCopy copyRegion = {
    srcOffset : 0, // Offset in source buffer
    dstOffset : 0, // Offset in destination buffer
    size : size // Size to copy
  };

  vkCmdCopyBuffer(app.renderBuffers[syncIndex], stagingBuffer, dst, 1, &copyRegion);

  VkBufferMemoryBarrier bufferBarrier = {
      sType : VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
      srcAccessMask : VK_ACCESS_TRANSFER_WRITE_BIT, // Data was written by transfer
      dstAccessMask : VK_ACCESS_SHADER_READ_BIT,    // Shader will read it
      srcQueueFamilyIndex : VK_QUEUE_FAMILY_IGNORED,
      dstQueueFamilyIndex : VK_QUEUE_FAMILY_IGNORED,
      buffer : dst, // The SSBO buffer itself
      offset : 0,
      size : VK_WHOLE_SIZE // Barrier applies to the whole buffer
  };

  vkCmdPipelineBarrier(
      app.renderBuffers[syncIndex],
      VK_PIPELINE_STAGE_TRANSFER_BIT,    // Source stage: Transfer (copy)
      VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, // Destination stage: Vertex shader reads
      0, // dependencyFlags
      0, null, // memoryBarriers
      1, &bufferBarrier, // bufferMemoryBarriers (our SSBO barrier)
      0, null // imageMemoryBarriers
  );
  app.frameDeletionQueue.add((){
    vkDestroyBuffer(app.device, stagingBuffer, app.allocator);
    vkFreeMemory(app.device, stagingBufferMemory, app.allocator);
  });
}

/** Record Vulkan render command buffer by rendering all objects to all render buffers
 */
void recordRenderCommandBuffer(ref App app, Shader[] shaders, uint syncIndex) {
  if(app.trace) SDL_Log("recordRenderCommandBuffer");

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    pInheritanceInfo: null // Optional
  };
  enforceVK(vkBeginCommandBuffer(app.renderBuffers[syncIndex], &beginInfo));
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

  VkBuffer dst;
  uint size;
  foreach(shader; shaders){
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
        if(SDL_strstr(shader.descriptors[d].base, "BoneMatrices") != null) { 
          dst = app.buffers[shader.descriptors[d].base].buffers[syncIndex];
          app.bonesToSSBO(dst, syncIndex);
        }
      }
    }
  }

  for(size_t x = 0; x < app.objects.length; x++) {
    if(app.showBounds) {
      app.objects[x].computeBoundingBox(app.trace);
      app.objects[x].box.buffer(app);
    }
    if(!app.objects[x].isBuffered) {
      if(app.trace) SDL_Log("Buffer object: %d %p", x, app.objects[x]);
      app.objects[x].buffer(app);
    }
  }

  vkCmdBeginRenderPass(app.renderBuffers[syncIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
  if(app.trace) SDL_Log("Render pass recording to buffer %d", syncIndex);

  if(app.trace) SDL_Log("Going to draw %d objects to renderBuffer %d", app.objects.length, syncIndex);
  for(size_t x = 0; x < app.objects.length; x++) {
    if(app.objects[x].isVisible) app.draw(app.objects[x], syncIndex);
    if(app.showBounds) app.draw(app.objects[x].box, syncIndex);
  }
  vkCmdEndRenderPass(app.renderBuffers[syncIndex]);
  enforceVK(vkEndCommandBuffer(app.renderBuffers[syncIndex]));
  if(app.trace) SDL_Log("Render pass finished to %d", syncIndex);

}

void createCommandPool(ref App app) {
  VkCommandPool commandPool;

  VkCommandPoolCreateInfo poolInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    queueFamilyIndex: app.queueFamily,
    flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
  };
  enforceVK(vkCreateCommandPool(app.device, &poolInfo, null, &app.commandPool));
  app.mainDeletionQueue.add((){ vkDestroyCommandPool(app.device, app.commandPool, app.allocator); });

  if(app.trace) SDL_Log("Commandpool %p at queue %d created", app.commandPool, poolInfo.queueFamilyIndex);
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

VkCommandBuffer beginSingleTimeCommands(ref App app) {
  VkCommandBuffer[1] commandBuffer = app.createCommandBuffer(app.commandPool, 1);

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  vkBeginCommandBuffer(commandBuffer[0], &beginInfo);
  return commandBuffer[0];
}

void endSingleTimeCommands(ref App app, VkCommandBuffer commandBuffer) {
  vkEndCommandBuffer(commandBuffer);

  VkSubmitInfo submitInfo = {
    sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount: 1,
    pCommandBuffers: &commandBuffer
  };

  vkQueueSubmit(app.queue, 1, &submitInfo, null);
  vkQueueWaitIdle(app.queue);

  vkFreeCommandBuffers(app.device, app.commandPool, 1, &commandBuffer);
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

