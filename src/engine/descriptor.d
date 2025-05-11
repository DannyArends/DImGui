/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import uniforms : UniformBufferObject;
import textures : Texture;

/** ImGui DescriptorPool (Images)
 */
void createImGuiDescriptorPool(ref App app){
  if(app.verbose) SDL_Log("create ImGui DescriptorPool");
  VkDescriptorPoolSize[] poolSizes = [
    {
      type : VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      descriptorCount : IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE
    }
  ];

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : 1000, // Allocate 1000 texture space
    poolSizeCount : cast(uint32_t)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.imguiPool));
  app.mainDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.imguiPool, app.allocator); });
}

/** Our DescriptorPool (UBO and Combined image sampler)
 */
void createDescriptorPool(ref App app){
  if(app.verbose) SDL_Log("create Render DescriptorPool");
  VkDescriptorPoolSize[] poolSizes = [
    { type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: cast(uint)(1) },
    { type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, descriptorCount: cast(uint)(app.textures.length) }
  ];

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : app.imageCount,
    poolSizeCount : cast(uint32_t)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.descriptorPool));
  app.frameDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.descriptorPool, app.allocator); });
}

/** Our DescriptorSetLayout (UBO and Combined image sampler)
 */
void createDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating Render DescriptorSetLayout");
  VkDescriptorSetLayoutBinding uboLayoutBinding = {
    binding: 0,
    descriptorCount: 1,
    descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    stageFlags: VK_SHADER_STAGE_VERTEX_BIT
  };

  VkDescriptorSetLayoutBinding samplerLayoutBinding = {
    binding: 1,
    descriptorCount: cast(uint)app.textures.length,
    descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT
  };

  VkDescriptorSetLayoutBinding[2] bindings = [uboLayoutBinding, samplerLayoutBinding];

  VkDescriptorSetLayoutCreateInfo layoutInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    bindingCount: bindings.length,
    pBindings: &bindings[0]
  };
  enforceVK(vkCreateDescriptorSetLayout(app.device, &layoutInfo, null, &app.descriptorSetLayout));
  app.frameDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.descriptorSetLayout, app.allocator); });
}

/** ImGui DescriptorSetLayout (Combined image sampler)
 */
void createImGuiDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating ImGui DescriptorSetLayout");
  VkDescriptorSetLayoutBinding samplerLayoutBinding = {
    binding: 0,
    descriptorCount: 1,
    descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT
  };

  VkDescriptorSetLayoutBinding[1] bindings = [samplerLayoutBinding];

  VkDescriptorSetLayoutCreateInfo layoutInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    bindingCount: bindings.length,
    pBindings: &bindings[0]
  };
  enforceVK(vkCreateDescriptorSetLayout(app.device, &layoutInfo, null, &app.ImGuiSetLayout));
  app.mainDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.ImGuiSetLayout, app.allocator); });
}

/** Create ImGui DescriptorSet (UBO and Combined image sampler)
 */
void addImGuiTexture(ref App app, ref Texture texture) {
  if(app.verbose) SDL_Log("creating imGui DescriptorSet");
  VkDescriptorSetLayout[] layouts = [app.ImGuiSetLayout];

  VkDescriptorSetAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    descriptorPool: app.imguiPool,
    descriptorSetCount: 1,
    pSetLayouts: &layouts[0]
  };
  enforceVK(vkAllocateDescriptorSets(app.device, &allocInfo, &texture.descrSet));

  VkDescriptorImageInfo textureImage = {
    imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    imageView: texture.textureImageView,
    sampler: app.sampler
  };
  VkWriteDescriptorSet[1] descriptorWrites = [
    {
      sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      dstSet: texture.descrSet,
      dstBinding: 0,
      dstArrayElement: 0,
      descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      descriptorCount: 1,
      pImageInfo: &textureImage
    }
  ];
  vkUpdateDescriptorSets(app.device, 1, &descriptorWrites[0], 0, null);
}

/** Create our DescriptorSet (UBO and Combined image sampler)
 */
void createDescriptorSet(ref App app) {
  if(app.verbose) SDL_Log("creating Render DescriptorSet");
  VkDescriptorSetLayout[] layouts = [app.descriptorSetLayout];

  VkDescriptorSetAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    descriptorPool: app.descriptorPool,
    descriptorSetCount: 1,
    pSetLayouts: &layouts[0]
  };
  if(app.verbose) SDL_Log("Allocating DescriptorSets");
  enforceVK(vkAllocateDescriptorSets(app.device, &allocInfo, &app.descriptorSet));

  if(app.verbose) SDL_Log("Update DescriptorSet, adding %d textures", app.textures.length);
  VkDescriptorImageInfo[] textureImages;
  for (size_t i = 0; i < app.textures.length; i++) {
    VkDescriptorImageInfo textureImage = {
      imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      imageView: app.textures[i].textureImageView, // Texture 0 is reserved for font
      sampler: app.sampler
    };
    textureImages ~= textureImage;
  }

  VkDescriptorBufferInfo bufferInfo = {
    buffer: app.uniform.uniformBuffers,
    offset: 0,
    range: UniformBufferObject.sizeof
  };

  VkWriteDescriptorSet[2] descriptorWrites = [
    {
      sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      dstSet: app.descriptorSet,
      dstBinding: 0,
      dstArrayElement: 0,
      descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      descriptorCount: 1,
      pBufferInfo: &bufferInfo,
      pImageInfo: null,
      pTexelBufferView: null
    },
    {
      sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      dstSet: app.descriptorSet,
      dstBinding: 1,
      dstArrayElement: 0,
      descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      descriptorCount: cast(uint)app.textures.length,
      pImageInfo: &textureImages[0]
    }
  ];
  vkUpdateDescriptorSets(app.device, descriptorWrites.length, &descriptorWrites[0], 0, null);
}

