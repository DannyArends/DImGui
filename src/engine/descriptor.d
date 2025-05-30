/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import uniforms : UniformBufferObject, ParticleUniformBuffer;
import shaders : Shader;
import textures : Texture, idx;

struct Descriptor {
  VkDescriptorType type;
  const(char)* name;
  const(char)* base;
  size_t bytes;            /// Size  of the structure
  size_t nObjects;        /// Number of objects stored

  uint set;
  uint binding;
  uint count;

  @property uint size(){ return(cast(uint)(bytes * nObjects)); }
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

VkDescriptorSetLayout createDescriptorSetLayout(ref App app, Shader[] shaders){
  DescriptorLayoutBuilder builder;
  foreach(shader; shaders) {
    foreach(descriptor; shader.descriptors) {
      builder.add(descriptor.binding, descriptor.count, shader.stage, descriptor.type);
    }
  }
  return(builder.build(app.device));
}

VkDescriptorPoolSize[] createPoolSizes(ref App app, Shader[] shaders){
  VkDescriptorPoolSize[] poolSizes;
  foreach(shader; shaders) {
    foreach(descriptor; shader.descriptors) {
      poolSizes ~= VkDescriptorPoolSize(descriptor.type, descriptor.count * cast(uint)(app.framesInFlight));
    }
  }
  return(poolSizes);
}

void createDSPool(ref App app, const(char)* poolID, VkDescriptorPoolSize[] poolSizes, uint maxSets = 1024){
  if(app.verbose) SDL_Log("Creating DescriptorPool[%s]", poolID);
  app.pools[poolID] = VkDescriptorPool();
  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : maxSets, /// Allocate maxSets (Default: 1024 Sets)
    poolSizeCount : cast(uint)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.pools[poolID]));
  if(app.verbose) SDL_Log("Created %s DescriptorPool: %p", poolID, app.pools[poolID]);
}



/** ImGui DescriptorPool (Images)
 */
void createImGuiDescriptorPool(ref App app){
  VkDescriptorPoolSize[] poolSizes = [{
    type : VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount : 1000 ///IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE
  }];
  app.createDSPool(IMGUI, poolSizes);
  app.mainDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.pools[IMGUI], app.allocator); });
}

/** ImGui DescriptorSetLayout (1000 * Combined Image Samplers)
 */
void createImGuiDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating ImGui DescriptorSetLayout");
  DescriptorLayoutBuilder builder;
  builder.add(0, 1, VK_SHADER_STAGE_FRAGMENT_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
  app.layouts[IMGUI] = builder.build(app.device);
  app.mainDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.layouts[IMGUI], app.allocator); });
}

/** Create a descriptor pool based on the shaders provided
 */
void createDSPool(ref App app, const(char)* poolID, Shader[] shaders) {
  uint nShaders = 1;
  if(strstr(poolID, COMPUTE) != null){ nShaders = cast(uint)shaders.length; }
  if(app.verbose) SDL_Log("createDSPool by shader: %s, with %d shader size", poolID, nShaders);
  VkDescriptorPoolSize[] poolSizes = app.createPoolSizes(shaders);
  app.createDSPool(poolID, poolSizes, nShaders * app.framesInFlight); // TODO this should be based on the number of shaders
  app.frameDeletionQueue.add((){ 
    vkDestroyDescriptorPool(app.device, app.pools[poolID], app.allocator); 
  });
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
void createDescriptors(ref App app) {
  if(app.verbose) SDL_Log("createDescriptors for rendering pipeline");
  app.layouts[RENDER] = app.createDescriptorSetLayout(app.shaders);
  app.sets[RENDER] = createDescriptorSet(app.device, app.pools[RENDER], app.layouts[RENDER],  app.framesInFlight);
  app.frameDeletionQueue.add((){ 
    vkDestroyDescriptorSetLayout(app.device, app.layouts[RENDER], app.allocator); 
  });
}

/** Update the DescriptorSet 
 */
void updateDescriptorSet(ref App app, Shader[] shaders, ref VkDescriptorSet[] dstSet, uint syncIndex = 0) {
  if(app.verbose) SDL_Log("updateDescriptorSet");
  VkWriteDescriptorSet[] descriptorWrites;
  for(uint s = 0; s < shaders.length; s++) {
    auto shader = shaders[s];
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(app.verbose) SDL_Log("- Descriptor: %d %s %s", shader.descriptors[d].binding, shader.descriptors[d].base, shader.descriptors[d].name);
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
        VkDescriptorBufferInfo* bufferInfo = new VkDescriptorBufferInfo(
          buffer: app.ubos[shader.descriptors[d].base].buffer[syncIndex],
          range: shader.descriptors[d].bytes
        );
        descriptorWrites ~= VkWriteDescriptorSet(
          sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
          dstSet: dstSet[syncIndex],
          dstBinding: shader.descriptors[d].binding,
          dstArrayElement: 0,
          descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
          descriptorCount: 1,
          pBufferInfo: bufferInfo
        );
      }
      // SSBO Buffer Write
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
        VkDescriptorBufferInfo* bufferInfo = new VkDescriptorBufferInfo(
          buffer: app.buffers[shader.descriptors[d].base].buffers[syncIndex],
          range: shader.descriptors[d].size
        ); // Weird this overwrites the previous one
        descriptorWrites ~= VkWriteDescriptorSet(
          sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
          dstSet: dstSet[syncIndex],
          dstBinding: shader.descriptors[d].binding,
          dstArrayElement: 0,
          descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
          descriptorCount: 1,
          pBufferInfo: bufferInfo
        );
      }
      // Compute Stored Image
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
        VkDescriptorImageInfo* imageInfo = new VkDescriptorImageInfo(
          imageLayout: VK_IMAGE_LAYOUT_GENERAL,
          imageView: app.textures[app.textures.idx(shader.descriptors[d].name)].view,
        );
        descriptorWrites ~= VkWriteDescriptorSet(
          sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
          dstSet: dstSet[syncIndex],
          dstBinding: shader.descriptors[d].binding,
          dstArrayElement: 0,
          descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
          descriptorCount: shader.descriptors[d].count,
          pImageInfo: imageInfo
        );
      }
    }
  }
  vkUpdateDescriptorSets(app.device, cast(uint)descriptorWrites.length, &descriptorWrites[0], 0, null);
  if(app.verbose) SDL_Log("updateComputeDescriptorSet DONE");
}

