/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import std.math : ceil;
import core.time : MonoTime;

import engine;

import textures : Texture, idx, registerTexture;
import commands : createCommandBuffer;
import descriptor : Descriptor, createDSPool, createPoolSizes, createDescriptorSetLayout, createDescriptorSet;
import pipeline : GraphicsPipeline;
import images : createImage, transitionImageLayout;
import swapchain : createImageView;
import shaders : Shader, createShaderModule;
import ssbo : SSBO;
import reflection : createResources;
import uniforms : UBO;

struct Compute {
  VkCommandBuffer[][const(char)*] commands;
  GraphicsPipeline[const(char)*] pipelines;
  Shader[] shaders;
}

/** Load shader modules for compute
 */
void createComputeShaders(ref App app) {
  const(char)*[] computePaths = ["assets/shaders/texture.glsl", "assets/shaders/particle.glsl"];
  foreach(path; computePaths){
    app.compute.shaders ~= app.createShaderModule(path, shaderc_glsl_compute_shader);
  }

  app.mainDeletionQueue.add(() { 
    for(uint i = 0; i < app.compute.shaders.length; i++) {
      vkDestroyShaderModule(app.device, app.compute.shaders[i], app.allocator);
    }
  });
}

/** Create the compute pipeline specified by the selectedShader
 */
void createComputePipeline(ref App app, Shader shader) {
  SDL_Log("Created Compute Pipeline for %s", shader.path);
  app.compute.pipelines[shader.path] = GraphicsPipeline();
  VkDescriptorSetLayout pSetLayouts = app.createDescriptorSetLayout([shader]);
  app.sets[shader.path] = createDescriptorSet(app.device, app.pools[COMPUTE], pSetLayouts,  app.framesInFlight);

  VkPipelineLayoutCreateInfo computeLayout = {
    sType : VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pSetLayouts : &pSetLayouts,
    setLayoutCount : 1,
    pNext : null
  };
  enforceVK(vkCreatePipelineLayout(app.device, &computeLayout, null, &app.compute.pipelines[shader.path].pipelineLayout));
  
  VkComputePipelineCreateInfo computeInfo = {
    sType : VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
    layout : app.compute.pipelines[shader.path].pipelineLayout,
    stage : shader.info,
    pNext : null
  };
  enforceVK(vkCreateComputePipelines(app.device, null, 1, &computeInfo, null, &app.compute.pipelines[shader.path].graphicsPipeline));
  if(app.verbose) SDL_Log("Compute pipeline [sel: %s] at: %p", shader.path, app.compute.pipelines[shader.path].graphicsPipeline);

  app.frameDeletionQueue.add((){
    vkDestroyDescriptorSetLayout(app.device, pSetLayouts, app.allocator);
    vkDestroyPipelineLayout(app.device, app.compute.pipelines[shader.path].pipelineLayout, app.allocator);
    vkDestroyPipeline(app.device, app.compute.pipelines[shader.path].graphicsPipeline, app.allocator);
  });
}

void createComputeCommandBuffers(ref App app, Shader shader) {
  app.compute.commands[shader.path] = app.device.createCommandBuffer(app.commandPool, app.framesInFlight, app.verbose);
  if(app.verbose) SDL_Log("createComputeCommandBuffers: %d RenderBuffer, commandpool[%p]", app.renderBuffers.length, app.commandPool);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.framesInFlight; i++) {
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.compute.commands[shader.path][i]);
    }
  });
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
void recordComputeCommandBuffer(ref App app, Shader shader, uint syncIndex = 0) {
  if(app.verbose) SDL_Log("Record Compute Command Buffer: %d", syncIndex);
  enforceVK(vkResetCommandBuffer(app.compute.commands[shader.path][syncIndex], 0));


  VkCommandBufferBeginInfo commandBufferInfo = { sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
  enforceVK(vkBeginCommandBuffer(app.compute.commands[shader.path][syncIndex], &commandBufferInfo));

  float[3] nJobs = [1, 1, 1];
  for(uint d = 0; d < shader.descriptors.length; d++) {
    if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
      uint idx = app.textures.idx(shader.descriptors[d].name);
      app.transitionImageLayout(app.textures[idx].image, app.compute.commands[shader.path][syncIndex], VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL);
      nJobs[0] = app.textures[idx].width;
      nJobs[1] = app.textures[idx].height;
    }else{
      nJobs[0] = 500; // Set based on the size of the SSBO and the Object being Send
    }
  }

  // Bind the compute pipeline
  vkCmdBindPipeline(app.compute.commands[shader.path][syncIndex], VK_PIPELINE_BIND_POINT_COMPUTE, app.compute.pipelines[shader.path].graphicsPipeline);

  // Bind the descriptor set containing the compute resources for the compute pipeline
  vkCmdBindDescriptorSets(app.compute.commands[shader.path][syncIndex], VK_PIPELINE_BIND_POINT_COMPUTE, 
                          app.compute.pipelines[shader.path].pipelineLayout, 0, 1, &app.sets[shader.path][syncIndex], 0, null);

  // Execute the compute pipeline dispatch
  vkCmdDispatch(app.compute.commands[shader.path][syncIndex], cast(uint)ceil(nJobs[0] / shader.groupCount[0])
                                                    , cast(uint)ceil(nJobs[1] / shader.groupCount[1])
                                                    , cast(uint)ceil(nJobs[2] / shader.groupCount[2]));

  for(uint d = 0; d < shader.descriptors.length; d++) {
    if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
      uint idx = app.textures.idx(shader.descriptors[d].name);
      app.transitionImageLayout(app.textures[idx].image, app.compute.commands[shader.path][syncIndex], VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    }
  }

  vkEndCommandBuffer(app.compute.commands[shader.path][syncIndex]);
  if(app.verbose) SDL_Log("Compute Command Buffer: %d Done", syncIndex);
}
