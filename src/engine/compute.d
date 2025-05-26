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
import uniforms : UBO, ParticleUniformBuffer;

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

/** Update the DescriptorSet 
 * TODO: This should depend whole on the 'compute' we could use e.g. the other shader modules as well as long as it's combined
 * in a stages that were combine, then we can use it for rendering as well (vert + frage)
 */
void updateComputeDescriptorSet(ref App app, Shader[] shaders, ref VkDescriptorSet[] dstSet, uint syncIndex = 0) {
  VkWriteDescriptorSet[] descriptorWrites;
  for(uint s = 0; s < shaders.length; s++) {
    auto shader = shaders[s];
    for(uint d = 0; d < shader.descriptors.length; d++) {
      // Image sampler write
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) {
        VkDescriptorImageInfo[] textureInfo;
        textureInfo.length = app.textures.length;

        for (size_t i = 0; i < app.textures.length; i++) {
          VkDescriptorImageInfo textureImage = {
            imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            imageView: app.textures[i].view,
            sampler: app.sampler
          };
          textureInfo[i] = textureImage;
        }
        descriptorWrites ~= VkWriteDescriptorSet(
          sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
          dstSet: dstSet[syncIndex],
          dstBinding: shader.descriptors[d].binding,
          dstArrayElement: 0,
          descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
          descriptorCount: cast(uint)app.textures.length,
          pImageInfo: &textureInfo[0]
        );
      }
      // Uniform Buffer Write
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
        VkDescriptorBufferInfo bufferInfo = {
          buffer: app.ubos[shader.descriptors[d].base].buffer[syncIndex],
          offset: 0,
          range: ParticleUniformBuffer.sizeof
        };
        descriptorWrites ~= VkWriteDescriptorSet(
          sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
          dstSet: dstSet[syncIndex],
          dstBinding: shader.descriptors[d].binding,
          dstArrayElement: 0,
          descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
          descriptorCount: 1,
          pBufferInfo: &bufferInfo,
          pImageInfo: null,
          pTexelBufferView: null
        );
      }
      // SSBO Buffer Write
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
        if(strcmp(shader.descriptors[d].base, "lastFrame")){ syncIndex = ((syncIndex--) % app.framesInFlight); }
        VkDescriptorBufferInfo bufferInfo = {
          buffer: app.buffers[shader.descriptors[d].base].buffers[syncIndex],
          offset: 0,
          range: 4 * 1024
        };
        descriptorWrites ~= VkWriteDescriptorSet(
          sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
          dstSet: dstSet[syncIndex],
          dstBinding: shader.descriptors[d].binding,
          dstArrayElement: 0,
          descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
          descriptorCount: 1,
          pBufferInfo: &bufferInfo,
          pImageInfo: null,
          pTexelBufferView: null
        );
      }
      // Compute Stored Image
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
        VkDescriptorImageInfo imageInfo = {
          imageLayout: VK_IMAGE_LAYOUT_GENERAL,
          imageView: app.textures[app.textures.idx(shader.descriptors[d].name)].view,
        };
        descriptorWrites ~= VkWriteDescriptorSet(
          sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
          dstSet: dstSet[syncIndex],
          dstBinding: shader.descriptors[d].binding,
          dstArrayElement: 0,
          descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
          descriptorCount: shader.descriptors[d].count,
          pImageInfo: &imageInfo
        );
      }
    }
  }
  vkUpdateDescriptorSets(app.device, cast(uint)descriptorWrites.length, &descriptorWrites[0], 0, null);
  if(app.verbose) SDL_Log("updateComputeDescriptorSet DONE");
}

void createComputeCommandBuffers(ref App app) {
  app.compute.commandBuffer = app.device.createCommandBuffer(app.commandPool, app.framesInFlight, app.verbose);
}

void createComputeResources(ref App app) {
  for(uint s = 0; s < app.compute.shaders.length; s++) {
    auto shader = app.compute.shaders[s];
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) app.createStorageImage(shader.descriptors[d]);
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) app.createSSBO(shader.descriptors[d]);
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) app.createComputeUBO(shader.descriptors[d]);
    }
  }
  SDL_Log("Rendering Shader Resources: %d ", app.shaders.length);
  for(uint s = 0; s < app.shaders.length; s++) {
    auto shader = app.shaders[s];
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) app.createStorageImage(shader.descriptors[d]);
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) app.createSSBO(shader.descriptors[d]);
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) app.createComputeUBO(shader.descriptors[d]);
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

  app.createImage(texture.width, texture.height, &texture.image, &texture.memory, VK_FORMAT_R16G16B16A16_SFLOAT, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL, usage);
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

void createSSBO(ref App app, Descriptor descriptor, uint size = 4 * 1024) {
  if(app.verbose) SDL_Log("createSSBO at %s, size = %d", descriptor.base, size);
  app.buffers[descriptor.base] = SSBO();
  app.buffers[descriptor.base].buffers.length = app.framesInFlight;
  app.buffers[descriptor.base].memory.length = app.framesInFlight;

  for(uint i = 0; i < app.framesInFlight; i++) {
    app.createBuffer(&app.buffers[descriptor.base].buffers[i], &app.buffers[descriptor.base].memory[i], size, 
                     VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  }

  app.frameDeletionQueue.add((){
    if(app.verbose) SDL_Log("Delete SSBO at %s", descriptor.base);
    for(uint i = 0; i < app.framesInFlight; i++) {
      vkDestroyBuffer(app.device, app.buffers[descriptor.base].buffers[i], app.allocator);
      vkFreeMemory(app.device, app.buffers[descriptor.base].memory[i], app.allocator);
    }
  });
}

void createComputeUBO(ref App app, Descriptor descriptor) {
  SDL_Log("create UBO at %s", descriptor.base);
  app.ubos[descriptor.base] = UBO();
  app.ubos[descriptor.base].buffer.length = app.framesInFlight;
  app.ubos[descriptor.base].memory.length = app.framesInFlight;
  for(uint i = 0; i < app.framesInFlight; i++) {
    app.createBuffer(&app.ubos[descriptor.base].buffer[i], &app.ubos[descriptor.base].memory[i], ParticleUniformBuffer.sizeof, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
  }
  if(app.verbose) SDL_Log("Created %d ComputeBuffers of size: %d bytes", app.imageCount, ParticleUniformBuffer.sizeof);

  app.frameDeletionQueue.add((){
    if(app.verbose) SDL_Log("Delete Compute UBO at %s", descriptor.base);
    for(uint i = 0; i < app.framesInFlight; i++) {
      vkDestroyBuffer(app.device, app.ubos[descriptor.base].buffer[i], app.allocator);
      vkFreeMemory(app.device, app.ubos[descriptor.base].memory[i], app.allocator);
    }
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
