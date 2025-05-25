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
import images : createImage;
import swapchain : createImageView;
import shaders : createShaderModule, createShaderStageInfo;

struct Compute {
  uint lastTick = 0;
  VkDescriptorPool pool = null;
  VkDescriptorSetLayout[] layout = null;
  VkDescriptorSet[] set = null;

  VkCommandBuffer[] commandBuffer = null;
  GraphicsPipeline pipeline;

  VkImage image;
  VkDeviceMemory memory;
  VkImageView imageView;
}

/** Compute Descriptor Pool
 */
void createComputeDescriptorPool(ref App app){
  if(app.verbose) SDL_Log("Creating Compute DescriptorPool");
  VkDescriptorPoolSize[] poolSizes = [
    { type : VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, descriptorCount : cast(uint)(app.framesInFlight) },
    { type : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount : cast(uint)(app.framesInFlight) },
    { type : VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, descriptorCount : 2 * cast(uint)(app.framesInFlight) }
  ];
  app.compute.pool = app.createDSPool("Compute", poolSizes, cast(uint)(app.framesInFlight));
  app.frameDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.compute.pool, app.allocator); });
}

/** Compute DescriptorSetLayout (Image)
 */
void createComputeDescriptorSetLayout(ref App app) {
  app.compute.layout.length = 2;
  
  DescriptorLayoutBuilder builder;
  builder.add(0, 1, VK_SHADER_STAGE_COMPUTE_BIT, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE);
  app.compute.layout[0] = builder.build(app.device);
  builder.clear();
  builder.add(0, 1, VK_SHADER_STAGE_COMPUTE_BIT, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
  builder.add(1, 1, VK_SHADER_STAGE_COMPUTE_BIT, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
  builder.add(2, 1, VK_SHADER_STAGE_COMPUTE_BIT, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
  app.compute.layout[1] = builder.build(app.device);
  app.frameDeletionQueue.add((){ 
    for(uint i = 0; i < app.compute.layout.length; i++) {
      vkDestroyDescriptorSetLayout(app.device, app.compute.layout[i], app.allocator);
    }
  });
}

void createComputeStages(ref App app) {
  app.computeStages ~= app.createComputeShader("assets/shaders/texture.glsl");
  app.computeStages ~= app.createComputeShader("assets/shaders/particle.glsl");
}

VkPipelineShaderStageCreateInfo createComputeShader(ref App app, const(char)* path = "assets/shaders/texture.spv") {
  VkPipelineShaderStageCreateInfo shaderStage;
  auto cShader = app.createShaderModule(path, shaderc_glsl_compute_shader);
  shaderStage = createShaderStageInfo(VK_SHADER_STAGE_COMPUTE_BIT, cShader);
  app.mainDeletionQueue.add(() { vkDestroyShaderModule(app.device, cShader, app.allocator); });
  return(shaderStage);
}

void createComputePipeline(ref App app, uint stage = 0, uint layout = 0) {
  VkPipelineLayoutCreateInfo computeLayout = {
    sType : VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pSetLayouts : &app.compute.layout[layout],
    setLayoutCount : 1,
    pNext : null
  };
  enforceVK(vkCreatePipelineLayout(app.device, &computeLayout, null, &app.compute.pipeline.pipelineLayout));
  
  VkComputePipelineCreateInfo computeInfo = {
    sType : VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
    layout : app.compute.pipeline.pipelineLayout,
    stage : app.computeStages[stage],
    pNext : null
  };
  enforceVK(vkCreateComputePipelines(app.device, null, 1, &computeInfo, null, &app.compute.pipeline.graphicsPipeline));
  SDL_Log("Compute pipeline [stage: %d] at: %p", stage, app.compute.pipeline.graphicsPipeline);
  app.frameDeletionQueue.add((){
    vkDestroyPipelineLayout(app.device, app.compute.pipeline.pipelineLayout, app.allocator);
    vkDestroyPipeline(app.device, app.compute.pipeline.graphicsPipeline, app.allocator);
  });
}

void createComputeDescriptorSet(ref App app, uint layout = 0) {
  app.compute.set = createDescriptorSet(app.device, app.compute.pool, app.compute.layout[layout],  app.framesInFlight);
}

void updateComputeDescriptorSet(ref App app, uint syncIndex = 0) {
  VkDescriptorImageInfo imageInfo = {
    imageLayout: VK_IMAGE_LAYOUT_GENERAL,
    imageView: app.compute.imageView,
  };
  if(app.verbose) SDL_Log("Linking image: %p", app.compute.imageView);

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

void createComputeBufferAndImage(ref App app){
  app.compute.commandBuffer = app.device.createCommandBuffer(app.commandPool, app.framesInFlight, app.verbose);

  VkImageUsageFlags usage;
  usage |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  usage |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  usage |= VK_IMAGE_USAGE_STORAGE_BIT;
  usage |= VK_IMAGE_USAGE_SAMPLED_BIT;
  usage |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

  app.createImage(app.camera.width, app.camera.height, &app.compute.image, &app.compute.memory, VK_FORMAT_R16G16B16A16_SFLOAT, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL, usage);
  app.compute.imageView = app.createImageView(app.compute.image, VK_FORMAT_R16G16B16A16_SFLOAT);
  if(app.verbose) SDL_Log("Create compute image %p, view: %p", app.compute.image, app.compute.imageView);

  app.frameDeletionQueue.add((){
    if(app.verbose) SDL_Log("Delete compute image");
    vkDestroyImageView(app.device, app.compute.imageView, app.allocator);
    vkDestroyImage(app.device, app.compute.image, app.allocator);
    vkFreeMemory(app.device, app.compute.memory, app.allocator);
  });

  int idx = app.textures.idx("Compute");
  Texture texture = {
    path : "Compute", width: app.camera.width, height: app.camera.height,
    textureImage: app.compute.image,
    textureImageMemory: app.compute.memory,
    textureImageView: app.compute.imageView
  };
  app.registerTexture(texture);

  if(idx < 0){
   app.textures ~= texture;
  }else{
   app.textures[idx] = texture;
  }
  if(app.verbose) SDL_Log("Compute texture at: %d", app.textures.idx("Compute"));
}

void transitionImage(ref App app, VkCommandBuffer commandBuffer, VkImage image, 
                           VkImageLayout oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, 
                           VkImageLayout newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                           VkFormat format = VK_FORMAT_R8G8B8A8_SRGB) {
  if(app.verbose) SDL_Log("transitionImage");
  VkImageSubresourceRange subresourceRange = {
    aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
    baseMipLevel: 0,
    levelCount: 1,
    baseArrayLayer: 0,
    layerCount: 1,
  };

  VkImageMemoryBarrier barrier = {
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    oldLayout: oldLayout,
    newLayout: newLayout,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: image,
    subresourceRange: subresourceRange,
  };

  VkPipelineStageFlags sourceStage;
  VkPipelineStageFlags destinationStage;

  barrier.srcAccessMask = 0;
  barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

  sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
  destinationStage = VK_PIPELINE_STAGE_TRANSFER_BIT;

  vkCmdPipelineBarrier(commandBuffer, sourceStage, destinationStage, 0, 0, null, 0, null, 1, &barrier);
  if(app.verbose) SDL_Log("transitionImage done");
}

void recordComputeCommandBuffer(ref App app, uint syncIndex) {
  if(app.verbose) SDL_Log("Record Compute Command Buffer: %d", syncIndex);
  enforceVK(vkResetCommandBuffer(app.compute.commandBuffer[syncIndex], 0));

  VkCommandBufferBeginInfo commandBufferInfo = {
    sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
  };
  enforceVK(vkBeginCommandBuffer(app.compute.commandBuffer[syncIndex], &commandBufferInfo));

  app.transitionImage(app.compute.commandBuffer[syncIndex], app.compute.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL);

  // bind the gradient drawing compute pipeline
  vkCmdBindPipeline(app.compute.commandBuffer[syncIndex], VK_PIPELINE_BIND_POINT_COMPUTE, app.compute.pipeline.graphicsPipeline);

  // bind the descriptor set containing the draw image for the compute pipeline
  vkCmdBindDescriptorSets(app.compute.commandBuffer[syncIndex], VK_PIPELINE_BIND_POINT_COMPUTE, app.compute.pipeline.pipelineLayout, 0, 1, &app.compute.set[syncIndex], 0, null);

  // execute the compute pipeline dispatch. We are using 16x16 workgroup size so we need to divide by it
  vkCmdDispatch(app.compute.commandBuffer[syncIndex], cast(uint)ceil(app.camera.width / 16.0), cast(uint)ceil(app.camera.height / 16.0), 1);

  app.transitionImage(app.compute.commandBuffer[syncIndex], app.compute.image, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

  vkEndCommandBuffer(app.compute.commandBuffer[syncIndex]);
  if(app.verbose) SDL_Log("Compute Command Buffer: %d Done", syncIndex);
}
