/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : beginSingleTimeCommands, endSingleTimeCommands;
import color : Colors;
import commands : createCommandBuffer;
import descriptor : Descriptor, createDescriptorSetLayout, createDescriptorSet;
import images : createImage, deAllocate, transitionImageLayout;
import particlesystem : ParticleSystem;
import pipeline : GraphicsPipeline;
import reflection : createResources;
import swapchain : createImageView;
import shaders : Shader, createShaderModule;
import ssbo : SSBO, updateSSBO;
import sync : insertWriteBarrier, insertReadBarrier;
import textures : Texture, idx, registerTexture, findTextureSlot;
import uniforms : ParticleUniformBuffer, UBO;
import quaternion : xyzw;
import validation : pushLabel, popLabel;

/** Compute structure with shaders, command buffer and pipelines
 */
struct Compute {
  bool enabled = true;
  uint lastTick;
  ParticleSystem system;
  Shader[] shaders;                           /// Compute shader objects
  VkCommandBuffer[][const(char)*] commands;   /// Command buffers
  GraphicsPipeline[const(char)*] pipelines;   /// Pipelines
}

/** Load shader modules for compute
 */
void createComputeShaders(ref App app, const(char)*[] computePaths = ["data/shaders/texture.glsl", "data/shaders/particle.glsl"]) {
  app.compute.system = new ParticleSystem(2048);
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
  if(app.verbose) SDL_Log("createComputePipeline for Shader %s", shader.path);
  app.compute.pipelines[shader.path] = GraphicsPipeline();
  app.layouts[shader.path] = app.createDescriptorSetLayout([shader]);
  app.sets[shader.path] = createDescriptorSet(app.device, app.pools[COMPUTE], app.layouts[shader.path],  app.framesInFlight);

  VkPipelineLayoutCreateInfo computeLayout = {
    sType : VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pSetLayouts : &app.layouts[shader.path],
    setLayoutCount : 1,
    pNext : null
  };
  enforceVK(vkCreatePipelineLayout(app.device, &computeLayout, null, &app.compute.pipelines[shader.path].layout));
  
  VkComputePipelineCreateInfo computeInfo = {
    sType : VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
    layout : app.compute.pipelines[shader.path].layout,
    stage : shader.info,
    pNext : null
  };
  enforceVK(vkCreateComputePipelines(app.device, null, 1, &computeInfo, null, &app.compute.pipelines[shader.path].pipeline));
  if(app.verbose) SDL_Log("Compute pipeline [sel: %s] at: %p", shader.path, app.compute.pipelines[shader.path].pipeline);

  app.frameDeletionQueue.add((){
    vkDestroyDescriptorSetLayout(app.device, app.layouts[shader.path], app.allocator);
    vkDestroyPipelineLayout(app.device, app.compute.pipelines[shader.path].layout, app.allocator);
    vkDestroyPipeline(app.device, app.compute.pipelines[shader.path].pipeline, app.allocator);
  });
}

void createComputeCommandBuffers(ref App app, Shader shader) {
  app.compute.commands[shader.path] = app.createCommandBuffer(app.commandPool, app.framesInFlight);
  if(app.verbose) SDL_Log("createComputeCommandBuffers: %d ComputeCommand, commandpool[%p]", app.framesInFlight, app.commandPool);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.framesInFlight; i++) {
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.compute.commands[shader.path][i]);
    }
  });
}

void transferToSSBO(ref App app, Descriptor descriptor) {
  VkCommandBuffer commandBuffer = app.beginSingleTimeCommands(app.commandPool);
  for(uint i = 0; i < app.framesInFlight; i++) {
    app.updateSSBO(commandBuffer, app.compute.system.particles, descriptor, i);
  }
  app.endSingleTimeCommands(commandBuffer, app.commandPool, app.queue);
}

void updateComputeUBO(ref App app, uint syncIndex = 0){
  for(uint s = 0; s < app.compute.shaders.length; s++) {
    auto shader = app.compute.shaders[s];
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER){
        uint now = SDL_GetTicks();
        ParticleUniformBuffer buffer = {
          position: app.compute.system.position.xyzw,
          gravity: app.compute.system.gravity.xyzw,
          floor: app.compute.system.floor,
          deltaTime: cast(float)(now - app.compute.lastTick) / 100.0f
        };
        app.compute.lastTick = now;

        memcpy(app.ubos[shader.descriptors[d].base].data[syncIndex], &buffer, ParticleUniformBuffer.sizeof);
      }
      /* Copy data off the GPU to the CPU */
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER){
        if(SDL_strstr(shader.descriptors[d].base, "currentFrame") != null){
        //  memcpy(&app.compute.system.particles[0], app.buffers[shader.descriptors[d].base].data[syncIndex], shader.descriptors[d].size);
        }
      }
    }
  }
}

void writeComputeImage(App app, ref VkWriteDescriptorSet[] write, Descriptor descriptor, VkDescriptorSet[] dst, ref VkDescriptorImageInfo[] imageInfos, uint syncIndex = 0){
  imageInfos ~= VkDescriptorImageInfo(null, app.textures[app.textures.idx(descriptor.name)].view, VK_IMAGE_LAYOUT_GENERAL);
  VkWriteDescriptorSet set = {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: dst[syncIndex],
    dstBinding: descriptor.binding,
    dstArrayElement: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
    descriptorCount: descriptor.count,
    pImageInfo: &imageInfos[($-1)]
  };
  write ~= set;
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
  app.textures[app.findTextureSlot(to!string(descriptor.name))] = texture;

  app.frameDeletionQueue.add((){ app.deAllocate(texture); });
}

/** recordComputeCommandBuffer for syncIndex and the selected ComputeShader
 */
void recordComputeCommandBuffer(ref App app, Shader shader, uint syncIndex = 0) {
  if(app.trace) SDL_Log("Record Compute Command Buffer [%s]: %d", shader.path, syncIndex);
  VkCommandBuffer cmdBuffer = app.compute.commands[shader.path][syncIndex];
  enforceVK(vkResetCommandBuffer(cmdBuffer, 0));

  VkCommandBufferBeginInfo commandBufferInfo = { sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
  enforceVK(vkBeginCommandBuffer(cmdBuffer, &commandBufferInfo));
  pushLabel(cmdBuffer, toStringz(format("Compute: %s", baseName(fromStringz(shader.path)))), Colors.palegoldenrod);

  float[3] nJobs = [1, 1, 1];
  uint size;
  VkBuffer src, dst;

  for(uint d = 0; d < shader.descriptors.length; d++) {
    if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {   // Use the command buffer to transition the image
      uint idx = app.textures.idx(shader.descriptors[d].name);
      app.transitionImageLayout(app.textures[idx].image, app.commandPool, app.queue, cmdBuffer, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL);
      nJobs[0] = app.textures[idx].width;
      nJobs[1] = app.textures[idx].height;
    }else if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
      nJobs[0] = shader.descriptors[d].nObjects; // Set based on the size of the SSBO and the Object being Send
      size = shader.descriptors[d].size;
      if(SDL_strstr(shader.descriptors[d].base, "currentFrame") != null) { 
        src = app.buffers[shader.descriptors[d].base].buffers[syncIndex];
      }
      if(SDL_strstr(shader.descriptors[d].base, "lastFrame") != null) { 
        dst = app.buffers[shader.descriptors[d].base].buffers[syncIndex];
      }
    }
  }

  // Bind the compute pipeline
  vkCmdBindPipeline(app.compute.commands[shader.path][syncIndex], VK_PIPELINE_BIND_POINT_COMPUTE, app.compute.pipelines[shader.path].pipeline);

  // Bind the descriptor set containing the compute resources for the compute pipeline
  vkCmdBindDescriptorSets(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, 
                          app.compute.pipelines[shader.path].layout, 0, 1, &app.sets[shader.path][syncIndex], 0, null);

  // Execute the compute pipeline dispatch
  vkCmdDispatch(app.compute.commands[shader.path][syncIndex], cast(uint)ceil(nJobs[0] / shader.groupCount[0])
                                                    , cast(uint)ceil(nJobs[1] / shader.groupCount[1])
                                                    , cast(uint)ceil(nJobs[2] / shader.groupCount[2]));

  if (src && dst) {
    cmdBuffer.insertWriteBarrier(dst);
    VkBufferCopy copyRegion = {size: size};
    vkCmdCopyBuffer(cmdBuffer, src, dst, 1, &copyRegion);
    cmdBuffer.insertReadBarrier(src);
  }

  for(uint d = 0; d < shader.descriptors.length; d++) {
    if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {   // Use the command buffer to transition the image
      uint idx = app.textures.idx(shader.descriptors[d].name);
      app.transitionImageLayout(app.textures[idx].image, app.commandPool, app.queue, cmdBuffer, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    }
  }
  popLabel(cmdBuffer);
  vkEndCommandBuffer(cmdBuffer);
  if(app.trace) SDL_Log("Compute Command Buffer: %d Done", syncIndex);
}

