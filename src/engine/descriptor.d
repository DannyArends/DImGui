/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import uniforms : UniformBufferObject;
import textures : Texture;

struct DescriptorLayoutBuilder {
  VkDescriptorSetLayoutBinding[] bindings;

  void add(uint binding, uint count, VkShaderStageFlags shaderStage, VkDescriptorType type){
    VkDescriptorSetLayoutBinding layout = {
      binding: binding,
      stageFlags: shaderStage,
      descriptorCount: count,
      descriptorType: type
    };
    bindings ~= layout;
  }
  void clear(){ bindings = []; }

  VkDescriptorSetLayout build(VkDevice device, VkDescriptorSetLayoutCreateFlags flags = 0, void* pNext = null){
    VkDescriptorSetLayoutCreateInfo info = {
      sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      pBindings: &bindings[0],
      bindingCount: cast(uint)bindings.length,
      flags: flags,
      pNext: pNext
    };
    VkDescriptorSetLayout set;
    enforceVK(vkCreateDescriptorSetLayout(device, &info, null, &set));
    return set;
  }
};

/** ImGui DescriptorPool (Images)
 */
void createImGuiDescriptorPool(ref App app){
  if(app.verbose) SDL_Log("Creating ImGui DescriptorPool");
  VkDescriptorPoolSize[] poolSizes = [
    {
      type : VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      descriptorCount : 1000 ///IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE
    }
  ];

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : 1000, // Allocate 1000 texture space
    poolSizeCount : cast(uint)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.imguiPool));
  if(app.verbose) SDL_Log("Created ImGui DescriptorPool: %p", app.imguiPool);
  app.mainDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.imguiPool, app.allocator); });
}

/** Our DescriptorPool (UBO and Combined image sampler)
 */
void createDescriptorPool(ref App app){
  if(app.verbose) SDL_Log("Creating Render DescriptorPool");
  VkDescriptorPoolSize[] poolSizes = [
    { type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: cast(uint)(app.framesInFlight) },
    { type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, descriptorCount: cast(uint)(app.framesInFlight * app.textures.length) }
  ];

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : app.framesInFlight,
    poolSizeCount : cast(uint)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.descriptorPool));
  if(app.verbose) SDL_Log("Created Render DescriptorPool: %p", app.descriptorPool);
  app.frameDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.descriptorPool, app.allocator); });
}

/** Our DescriptorSetLayout (UBO and Combined image sampler)
 */
void createDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating Render DescriptorSetLayout");
  DescriptorLayoutBuilder builder;
  builder.add(0, 1, VK_SHADER_STAGE_VERTEX_BIT, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
  builder.add(1, cast(uint) app.textures.length, VK_SHADER_STAGE_FRAGMENT_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
  app.descriptorSetLayout = builder.build(app.device);
  app.frameDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.descriptorSetLayout, app.allocator); });
}

/** ImGui DescriptorSetLayout (Combined image sampler)
 */
void createImGuiDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating ImGui DescriptorSetLayout");
  DescriptorLayoutBuilder builder;
  builder.add(0, 1, VK_SHADER_STAGE_FRAGMENT_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
  app.ImGuiSetLayout = builder.build(app.device);
  app.mainDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.ImGuiSetLayout, app.allocator); });
}

VkDescriptorSet[] createDescriptorSet(VkDevice device, VkDescriptorPool pool, VkDescriptorSetLayout layout, uint size){
  VkDescriptorSetLayout[] layouts;
  VkDescriptorSet[] set;
  layouts.length = set.length = size;

  for(uint i = 0; i < size; i++) { layouts[i] = layout; }

  VkDescriptorSetAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    descriptorPool: pool,
    descriptorSetCount: size,
    pSetLayouts: &layouts[0]
  };

  enforceVK(vkAllocateDescriptorSets(device, &allocInfo, &set[0]));
  return(set);
}

/** Create our DescriptorSet (UBO and Combined image sampler)
 */
void createRenderDescriptor(ref App app) {
  if(app.verbose) SDL_Log("creating Render DescriptorSet");
  app.descriptorSet = createDescriptorSet(app.device, app.descriptorPool, app.descriptorSetLayout,  app.framesInFlight);
}

void createTextureDescriptors(ref App app) {
  app.textureImagesInfo.length = app.textures.length;

  for (size_t i = 0; i < app.textures.length; i++) {
    VkDescriptorImageInfo textureImage = {
      imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      imageView: app.textures[i].textureImageView,
      sampler: app.sampler
    };
    app.textureImagesInfo[i] = textureImage;
  }
}

void updateDescriptorSet(ref App app, uint syncIndex) {
  if(app.verbose) SDL_Log("Update DescriptorSet, adding %d textures", app.textures.length);

  VkDescriptorBufferInfo bufferInfo = {
    buffer: app.uniform.uniformBuffers[syncIndex],
    offset: 0,
    range: UniformBufferObject.sizeof
  };

  VkWriteDescriptorSet[2] descriptorWrites = [
    {
      sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      dstSet: app.descriptorSet[syncIndex],
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
      dstSet: app.descriptorSet[syncIndex],
      dstBinding: 1,
      dstArrayElement: 0,
      descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      descriptorCount: cast(uint)app.textures.length,
      pImageInfo: &app.textureImagesInfo[0]
    }
  ];
  vkUpdateDescriptorSets(app.device, descriptorWrites.length, &descriptorWrites[0], 0, null);
}

