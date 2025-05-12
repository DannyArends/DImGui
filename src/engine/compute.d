/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import std.math : ceil;
import core.time : MonoTime;

import engine;
import textures : Texture;
import commands : createCommandBuffer;
import descriptor : DescriptorLayoutBuilder, addImGuiTexture;
import pipeline : GraphicsPipeline;
import images : createImage;
import uniforms : ComputeUniform;
import swapchain : createImageView;
import shaders : createShaderModule, createShaderStageInfo;

struct Compute {
  float angle = 15.0f;
  VkDescriptorPool pool = null;
  VkDescriptorSetLayout layout = null;
  VkDescriptorSet set = null;

  VkCommandBuffer[] buffer = null;
  GraphicsPipeline pipeline;
  VkImage image;
  VkDeviceMemory memory;
  VkImageView imageView;
}

/** Compute Descriptor Pool (Image)
 */
void createComputeDescriptorPool(ref App app){
  if(app.verbose) SDL_Log("create Compute DescriptorPool");
  VkDescriptorPoolSize[] poolSizes = [
    { type : VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, descriptorCount : 1 },
    { type : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount : 1 }
  ];

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : 10, // Allocate 1000 texture space
    poolSizeCount : cast(uint32_t)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.compute.pool));
  app.mainDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.compute.pool, app.allocator); });
}

/** Compute DescriptorSetLayout (Image)
 */
void createComputeDescriptorSetLayout(ref App app) {
  DescriptorLayoutBuilder builder;
  builder.add(0, 1, VK_SHADER_STAGE_COMPUTE_BIT, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE);
  builder.add(1, 1, VK_SHADER_STAGE_COMPUTE_BIT, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
  app.compute.layout = builder.build(app.device);
  app.mainDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.compute.layout, app.allocator); });
}

void createComputePipeline(ref App app, const(char)* compPath = "assets/shaders/comp.spv") {
  auto cShader = app.createShaderModule(compPath);
  VkPipelineShaderStageCreateInfo cInfo = createShaderStageInfo(VK_SHADER_STAGE_COMPUTE_BIT, cShader);
  app.mainDeletionQueue.add(() { vkDestroyShaderModule(app.device, cShader, app.allocator); });

  VkPipelineLayoutCreateInfo computeLayout = {
    sType : VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pSetLayouts : &app.compute.layout,
    setLayoutCount : 1,
    pNext : null
  };
  enforceVK(vkCreatePipelineLayout(app.device, &computeLayout, null, &app.compute.pipeline.pipelineLayout));
  
  VkComputePipelineCreateInfo computeInfo = {
    sType : VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
    layout : app.compute.pipeline.pipelineLayout,
    stage : cInfo,
    pNext : null
  };
  enforceVK(vkCreateComputePipelines(app.device, null, 1, &computeInfo, null, &app.compute.pipeline.graphicsPipeline));
  SDL_Log("Compute pipeline at: %p", app.compute.pipeline.graphicsPipeline);
  app.mainDeletionQueue.add((){
    vkDestroyPipelineLayout(app.device, app.compute.pipeline.pipelineLayout, app.allocator);
    vkDestroyPipeline(app.device, app.compute.pipeline.graphicsPipeline, app.allocator);
  });
}

void createComputeDescriptorSet(ref App app) {
  if(app.verbose) SDL_Log("creating Compute DescriptorSet");
  VkDescriptorSetLayout[] layouts = [app.compute.layout];

  VkDescriptorSetAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    descriptorPool: app.compute.pool,
    descriptorSetCount: 1,
    pSetLayouts: &layouts[0]
  };

  enforceVK(vkAllocateDescriptorSets(app.device, &allocInfo, &app.compute.set));

  VkDescriptorImageInfo imageInfo = {
    imageLayout: VK_IMAGE_LAYOUT_GENERAL,
    imageView: app.compute.imageView,
  };

  VkDescriptorBufferInfo bufferInfo = {
    buffer: app.uniform.computeBuffers,
    offset: 0,
    range: ComputeUniform.sizeof
  };

  VkWriteDescriptorSet[2] descriptorWrites = [
    {
      sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      dstSet: app.compute.set,
      dstBinding: 0,
      dstArrayElement: 0,
      descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
      descriptorCount: 1,
      pImageInfo: &imageInfo
    },
    {
      sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      dstSet: app.compute.set,
      dstBinding: 1,
      dstArrayElement: 0,
      descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      descriptorCount: 1,
      pBufferInfo: &bufferInfo,
      pImageInfo: null,
      pTexelBufferView: null
    }

  ];
  vkUpdateDescriptorSets(app.device, descriptorWrites.length, &descriptorWrites[0], 0, null);
}

void createComputeBufferAndImage(ref App app){
  app.compute.buffer = app.device.createCommandBuffer(app.commandPool, 1, app.verbose);

  VkImageUsageFlags usage;
  usage |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  usage |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  usage |= VK_IMAGE_USAGE_STORAGE_BIT;
  usage |= VK_IMAGE_USAGE_SAMPLED_BIT;
  usage |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

  app.createImage(app.camera.width, app.camera.height, &app.compute.image, &app.compute.memory, VK_FORMAT_R16G16B16A16_SFLOAT, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL, usage);
  app.compute.imageView = app.createImageView(app.compute.image, VK_FORMAT_R16G16B16A16_SFLOAT);
  app.frameDeletionQueue.add((){
    vkDestroyImageView(app.device, app.compute.imageView, app.allocator);
    vkDestroyImage(app.device, app.compute.image, app.allocator);
    vkFreeMemory(app.device, app.compute.memory, app.allocator);
  });
  
  Texture texture = { 
    path : "Compute", width: app.camera.width, height: app.camera.height,
    textureImage: app.compute.image,
    textureImageMemory: app.compute.memory,
    textureImageView: app.compute.imageView
  };
  app.addImGuiTexture(texture);
  app.textures ~= texture;
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
}

void recordCompute(ref App app) {
  enforceVK(vkResetCommandBuffer(app.compute.buffer[0], 0));

  VkCommandBufferBeginInfo commandBufferInfo = {
    sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
  };
  enforceVK(vkBeginCommandBuffer(app.compute.buffer[0], &commandBufferInfo));

  app.transitionImage(app.compute.buffer[0], app.compute.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL);

  // bind the gradient drawing compute pipeline
  vkCmdBindPipeline(app.compute.buffer[0], VK_PIPELINE_BIND_POINT_COMPUTE, app.compute.pipeline.graphicsPipeline);

  // bind the descriptor set containing the draw image for the compute pipeline
  vkCmdBindDescriptorSets(app.compute.buffer[0], VK_PIPELINE_BIND_POINT_COMPUTE, app.compute.pipeline.pipelineLayout, 0, 1, &app.compute.set, 0, null);

  // execute the compute pipeline dispatch. We are using 16x16 workgroup size so we need to divide by it
  vkCmdDispatch(app.compute.buffer[0], cast(uint)ceil(app.camera.width / 16.0), cast(uint)ceil(app.camera.height / 16.0), 1);

  app.transitionImage(app.compute.buffer[0], app.compute.image, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

  vkEndCommandBuffer(app.compute.buffer[0]);
}
