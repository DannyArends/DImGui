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
import descriptor : Descriptor, DescriptorLayoutBuilder, createDSPool, createDescriptorSet;
import pipeline : GraphicsPipeline;
import images : createImage, transitionImageLayout;
import swapchain : createImageView;
import shaders : Shader, createShaderModule, createPoolSizes, createDescriptorSetLayout, createShaderStageInfo;
import ssbo : SSBO, createSSBO;
import uniforms : UBO, createUBO, UniformBufferObject, ParticleUniformBuffer;

struct Compute {
  uint lastTick = 0;
  VkDescriptorPool pool = null;
  VkDescriptorSetLayout[] layout = null;
  VkDescriptorSet[] set = null;

  VkCommandBuffer[] commandBuffer = null;
  GraphicsPipeline pipeline;
  Shader[] shaders;

  ParticleUniformBuffer[] particleUniformBuffer;
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

void createComputeCommandBuffers(ref App app) {
  app.compute.commandBuffer = app.device.createCommandBuffer(app.commandPool, app.framesInFlight, app.verbose);
  if(app.verbose) SDL_Log("createComputeCommandBuffers: %d RenderBuffer, commandpool[%p]", app.renderBuffers.length, app.commandPool);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.framesInFlight; i++) {
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.compute.commandBuffer[i]);
    }
  });
}

void createResources(ref App app, Shader[] shaders) {
  if(app.verbose) SDL_Log("Creating Compute Resources: %d shaders", app.shaders.length);
  for(uint s = 0; s < shaders.length; s++) {
    for(uint d = 0; d < shaders[s].descriptors.length; d++) {
      if(shaders[s].descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) app.createStorageImage(shaders[s].descriptors[d]);
      if(shaders[s].descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) app.createSSBO(shaders[s].descriptors[d]);
      if(shaders[s].descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) app.createUBO(shaders[s].descriptors[d]);
    }
  }
}

void createStorageImage(ref App app, Descriptor descriptor){
  VkImageUsageFlags usage;
  usage |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  usage |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  usage |= VK_IMAGE_USAGE_STORAGE_BIT;
  usage |= VK_IMAGE_USAGE_SAMPLED_BIT;
  usage |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

  Texture texture = { path : descriptor.name, width: app.camera.width, height: app.camera.height };

  app.createImage(texture.width, texture.height, &texture.image, &texture.memory, 
                  VK_FORMAT_R16G16B16A16_SFLOAT, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL, usage);
  texture.view = app.createImageView(texture.image, VK_FORMAT_R16G16B16A16_SFLOAT);
  if(app.verbose) SDL_Log("Create compute image %p, view: %p", texture.image, texture.view);
  app.registerTexture(texture); // Register texture with ImGui

  // Update the Texture Array for rendering
  int idx = app.textures.idx(descriptor.name);
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

/** recordComputeCommandBuffer for syncIndex and the selected ComputeShader
 */
void recordComputeCommandBuffer(ref App app, uint syncIndex = 0, uint selectedShader = 0) {
  if(app.verbose) SDL_Log("Record Compute Command Buffer: %d", syncIndex);
  enforceVK(vkResetCommandBuffer(app.compute.commandBuffer[syncIndex], 0));
  auto shader = app.compute.shaders[selectedShader];

  VkCommandBufferBeginInfo commandBufferInfo = { sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
  enforceVK(vkBeginCommandBuffer(app.compute.commandBuffer[syncIndex], &commandBufferInfo));

  float[3] nJobs = [1, 1, 1];
  for(uint d = 0; d < shader.descriptors.length; d++) {
    if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
      uint idx = app.textures.idx(shader.descriptors[d].name);
      app.transitionImageLayout(app.textures[idx].image, app.compute.commandBuffer[syncIndex], VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL);
      nJobs[0] = app.textures[idx].width;
      nJobs[1] = app.textures[idx].height;
    }else{
      nJobs[0] = 500; // Set based on the size of the SSBO and the Object being Send
    }
  }

  // Bind the compute pipeline
  vkCmdBindPipeline(app.compute.commandBuffer[syncIndex], VK_PIPELINE_BIND_POINT_COMPUTE, app.compute.pipeline.graphicsPipeline);

  // Bind the descriptor set containing the compute resources for the compute pipeline
  vkCmdBindDescriptorSets(app.compute.commandBuffer[syncIndex], VK_PIPELINE_BIND_POINT_COMPUTE, app.compute.pipeline.pipelineLayout, 0, 1, &app.compute.set[syncIndex], 0, null);

  // Execute the compute pipeline dispatch
  vkCmdDispatch(app.compute.commandBuffer[syncIndex], cast(uint)ceil(nJobs[0] / shader.groupCount[0])
                                                    , cast(uint)ceil(nJobs[1] / shader.groupCount[1])
                                                    , cast(uint)ceil(nJobs[2] / shader.groupCount[2]));

  for(uint d = 0; d < shader.descriptors.length; d++) {
    if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
      uint idx = app.textures.idx(shader.descriptors[d].name);
      app.transitionImageLayout(app.textures[idx].image, app.compute.commandBuffer[syncIndex], VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    }
  }

  vkEndCommandBuffer(app.compute.commandBuffer[syncIndex]);
  if(app.verbose) SDL_Log("Compute Command Buffer: %d Done", syncIndex);
}
