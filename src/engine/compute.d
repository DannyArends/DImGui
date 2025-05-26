/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import std.math : ceil;
import core.time : MonoTime;

import engine;

import buffer : createBuffer, copyBuffer;
import textures : Texture, idx, registerTexture;
import commands : createCommandBuffer;
import descriptor : DescriptorLayoutBuilder, createDSPool, createDescriptorSet;
import pipeline : GraphicsPipeline;
import images : createImage, transitionImage;
import swapchain : createImageView;
import shaders : createShaderModule, createPoolSizes, createDescriptorSetLayout, createShaderStageInfo;

struct SSBO {
  VkBuffer[] buffers;
  VkDeviceMemory[] memory;
}

struct Compute {
  uint lastTick = 0;
  VkDescriptorPool pool = null;
  VkDescriptorSetLayout[] layout = null;
  VkDescriptorSet[] set = null;

  VkCommandBuffer[] commandBuffer = null;
  GraphicsPipeline pipeline;
  Shader[] shaders;
}

/** Compute Descriptor Pool
 */
void createComputeDescriptorPool(ref App app){
  if(app.verbose) SDL_Log("Creating Compute DescriptorPool");
  VkDescriptorPoolSize[] poolSizes = app.createPoolSizes(app.compute.shaders);
  app.compute.pool = app.createDSPool("Compute", poolSizes, cast(uint)(app.framesInFlight));
  app.frameDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.compute.pool, app.allocator); });
}

/** Load shader modules for compute
 */
void createComputeStages(ref App app) {
  const(char)*[] computePaths = ["assets/shaders/texture.glsl", "assets/shaders/particle.glsl"];
  foreach(path; computePaths){
    auto shader = app.createShaderModule(path, shaderc_glsl_compute_shader);
    app.compute.shaders ~= shader;
    app.computeStages ~= createShaderStageInfo(VK_SHADER_STAGE_COMPUTE_BIT, shader);
  }

  app.mainDeletionQueue.add(() { 
    for(uint i = 0; i < app.compute.shaders.length; i++) {
      vkDestroyShaderModule(app.device, app.compute.shaders[i], app.allocator);
    }
  });
}

/** Create the compute pipeline specified by the selectedShader
 */
void createComputePipeline(ref App app, uint selectedShader = 0) {
  VkDescriptorSetLayout pSetLayouts = app.createDescriptorSetLayout([app.compute.shaders[selectedShader]]);
  app.compute.set = createDescriptorSet(app.device, app.compute.pool, pSetLayouts,  app.framesInFlight);

  VkPipelineLayoutCreateInfo computeLayout = {
    sType : VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pSetLayouts : &pSetLayouts,
    setLayoutCount : 1,
    pNext : null
  };
  enforceVK(vkCreatePipelineLayout(app.device, &computeLayout, null, &app.compute.pipeline.pipelineLayout));
  
  VkComputePipelineCreateInfo computeInfo = {
    sType : VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
    layout : app.compute.pipeline.pipelineLayout,
    stage : app.computeStages[selectedShader],
    pNext : null
  };
  enforceVK(vkCreateComputePipelines(app.device, null, 1, &computeInfo, null, &app.compute.pipeline.graphicsPipeline));
  if(app.verbose) SDL_Log("Compute pipeline [sel: %d] at: %p", selectedShader, app.compute.pipeline.graphicsPipeline);
  app.frameDeletionQueue.add((){
    vkDestroyDescriptorSetLayout(app.device, pSetLayouts, app.allocator);
    vkDestroyPipelineLayout(app.device, app.compute.pipeline.pipelineLayout, app.allocator);
    vkDestroyPipeline(app.device, app.compute.pipeline.graphicsPipeline, app.allocator);
  });
}

/** Update the DescriptorSet 
 * TODO: should be based on selectedShader and compute shader reflection
 */
void updateComputeDescriptorSet(ref App app, uint syncIndex = 0) {
  int idx = app.textures.idx("Compute");

  VkDescriptorImageInfo imageInfo = {
    imageLayout: VK_IMAGE_LAYOUT_GENERAL,
    imageView: app.textures[idx].view,
  };
  if(app.verbose) SDL_Log("Linking image: %p", app.textures[idx].view);

  VkWriteDescriptorSet[1] descriptorWrites = [ {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: app.compute.set[syncIndex],
    dstBinding: 0,
    dstArrayElement: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
    descriptorCount: 1,
    pImageInfo: &imageInfo
  }];
  vkUpdateDescriptorSets(app.device, descriptorWrites.length, &descriptorWrites[0], 0, null);
  if(app.verbose) SDL_Log("updateComputeDescriptorSet DONE");
}

void createComputeCommandBuffers(ref App app) {
  app.compute.commandBuffer = app.device.createCommandBuffer(app.commandPool, app.framesInFlight, app.verbose);
}

void createComputeResources(ref App app) {
  app.buffers = [];
  foreach(shader; app.compute.shaders) {
    foreach(descriptor; shader.descriptors) {
      if(descriptor.type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) app.createStorageImage();
      if(descriptor.type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) app.createSSBO();
    }
  }
}

void createStorageImage(ref App app){
  VkImageUsageFlags usage;
  usage |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  usage |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  usage |= VK_IMAGE_USAGE_STORAGE_BIT;
  usage |= VK_IMAGE_USAGE_SAMPLED_BIT;
  usage |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

  Texture texture = { path : "Compute", width: app.camera.width, height: app.camera.height };

  app.createImage(texture.width, texture.height, &texture.image, &texture.memory, VK_FORMAT_R16G16B16A16_SFLOAT, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL, usage);
  texture.view = app.createImageView(texture.image, VK_FORMAT_R16G16B16A16_SFLOAT);
  if(app.verbose) SDL_Log("Create compute image %p, view: %p", texture.image, texture.view);
  app.registerTexture(texture); // Register texture with ImGui

  // Update the Texture Array for rendering
  int idx = app.textures.idx("Compute");
  if(idx < 0) {
   app.textures ~= texture;
  }else{
   app.textures[idx] = texture;
  }
  if(app.verbose) SDL_Log("Compute texture at: %d", idx);

  app.frameDeletionQueue.add((){
    if(app.verbose) SDL_Log("Delete compute image");
    vkDestroyImageView(app.device, texture.view, app.allocator);
    vkDestroyImage(app.device, texture.image, app.allocator);
    vkFreeMemory(app.device, texture.memory, app.allocator);
  });
}

void createSSBO(ref App app, uint size = 1024 * 1024) {
  size_t idx = app.buffers.length;
  if(app.verbose) SDL_Log("createSSBO at %d, size = %d", idx, size);
  app.buffers.length++;

  app.buffers[idx].buffers.length = app.framesInFlight;
  app.buffers[idx].memory.length = app.framesInFlight;

  for(uint i = 0; i < app.framesInFlight; i++) {
    app.createBuffer(&app.buffers[idx].buffers[i], &app.buffers[idx].memory[i], size, 
                     VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  }

  app.frameDeletionQueue.add((){
    if(app.verbose) SDL_Log("Delete createSSBO at %d", idx);
    for(uint i = 0; i < app.framesInFlight; i++) {
      vkDestroyBuffer(app.device, app.buffers[idx].buffers[i], app.allocator);
      vkFreeMemory(app.device, app.buffers[idx].memory[i], app.allocator);
    }
  });
}

void recordComputeCommandBuffer(ref App app, uint syncIndex) {
  if(app.verbose) SDL_Log("Record Compute Command Buffer: %d", syncIndex);
  enforceVK(vkResetCommandBuffer(app.compute.commandBuffer[syncIndex], 0));
  int idx = app.textures.idx("Compute");

  VkCommandBufferBeginInfo commandBufferInfo = {
    sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
  };
  enforceVK(vkBeginCommandBuffer(app.compute.commandBuffer[syncIndex], &commandBufferInfo));

  app.transitionImage(app.compute.commandBuffer[syncIndex], app.textures[idx].image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL);

  // bind the gradient drawing compute pipeline
  vkCmdBindPipeline(app.compute.commandBuffer[syncIndex], VK_PIPELINE_BIND_POINT_COMPUTE, app.compute.pipeline.graphicsPipeline);

  // bind the descriptor set containing the draw image for the compute pipeline
  vkCmdBindDescriptorSets(app.compute.commandBuffer[syncIndex], VK_PIPELINE_BIND_POINT_COMPUTE, app.compute.pipeline.pipelineLayout, 0, 1, &app.compute.set[syncIndex], 0, null);

  // execute the compute pipeline dispatch. We are using 16x16 workgroup size so we need to divide by it
  vkCmdDispatch(app.compute.commandBuffer[syncIndex], cast(uint)ceil(app.camera.width / 16.0), cast(uint)ceil(app.camera.height / 16.0), 1);

  app.transitionImage(app.compute.commandBuffer[syncIndex], app.textures[idx].image, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

  vkEndCommandBuffer(app.compute.commandBuffer[syncIndex]);
  if(app.verbose) SDL_Log("Compute Command Buffer: %d Done", syncIndex);
}
