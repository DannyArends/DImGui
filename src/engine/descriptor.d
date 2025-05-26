/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import uniforms : UniformBufferObject;
import shaders : createDescriptorSetLayout, createPoolSizes;
import textures : Texture;

struct Descriptor {
  VkDescriptorType type;
  const(char)* name;
  const(char)* base;
  uint set;
  uint binding;
  uint count;
}

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


VkDescriptorPool createDSPool(ref App app, const(char)* name, VkDescriptorPoolSize[] poolSizes, uint maxSets = 1024){
  if(app.verbose) SDL_Log("Creating %s DescriptorPool", name);
  VkDescriptorPool pool;
  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : maxSets, /// Allocate maxSets (Default: 1024 Sets)
    poolSizeCount : cast(uint)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &pool));
  if(app.verbose) SDL_Log("Created %s DescriptorPool: %p", name, pool);
  return(pool);
}

/** ImGui DescriptorPool (Images)
 */
void createImGuiDescriptorPool(ref App app){
  VkDescriptorPoolSize[] poolSizes = [{
    type : VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount : 1000 ///IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE
  }];
  app.imguiPool = app.createDSPool("ImGui", poolSizes);
  app.mainDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.imguiPool, app.allocator); });
}

/** ImGui DescriptorSetLayout (1024 * Combined Image Samplers)
 */
void createImGuiDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating ImGui DescriptorSetLayout");
  DescriptorLayoutBuilder builder;
  builder.add(0, 1, VK_SHADER_STAGE_FRAGMENT_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
  app.ImGuiSetLayout = builder.build(app.device);
  app.mainDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.ImGuiSetLayout, app.allocator); });
}

/** Our DescriptorPool (FiF * UBO and FiF * Textures * Combined Image samplers)
 */
void createDescriptorPool(ref App app){
  VkDescriptorPoolSize[] poolSizes = app.createPoolSizes(app.shaders);
  app.descriptorPool = app.createDSPool("Rendering", poolSizes, app.framesInFlight);
  app.frameDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.descriptorPool, app.allocator); });
}

/** Our DescriptorSetLayout (1 x UBO and Textures * Combined Image Sampler)
 */
void createDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating Render DescriptorSetLayout");
  app.descriptorSetLayout = app.createDescriptorSetLayout(app.shaders);
  if(app.verbose) SDL_Log("Created Render DescriptorSetLayout");
  app.frameDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.descriptorSetLayout, app.allocator); });
}

/** Allocate a Descriptor Set
 */
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
      imageView: app.textures[i].view,
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

