/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import compute : writeComputeImage;
import images : writeHDRSampler;
import sampler : writeTextureSampler;
import shaders : Shader;
import shadow : writeShadowMap;
import ssbo : writeSSBO;
import textures : Texture, idx;
import uniforms : writeUniformBuffer;

struct Descriptor {
  VkDescriptorType type;    /// Type of Descriptor
  const(char)* name;        /// Name
  const(char)* base;        /// Base / Struct Name
  size_t bytes;             /// Size  of the structure
  size_t nObjects;          /// Number of objects stored

  uint set;                 /// DescriptorSet
  uint binding;             /// DescriptorSet Binding
  uint count;               /// Descriptor count

  @property uint size(){ return(cast(uint)(bytes * nObjects)); }
}

struct DescriptorLayoutBuilder {
  VkDescriptorSetLayoutBinding[] bindings;

  void add(uint binding, uint count, VkShaderStageFlags shaderStage, VkDescriptorType type){
    foreach(ref b; bindings){
      if(b.binding == binding){
        b.stageFlags |= shaderStage;
        return;
      }
    }
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
      if(app.verbose) SDL_Log(toStringz(format("[%d] cnt: %d = %s %s", descriptor.binding, descriptor.count, shader.stage, descriptor.type)));
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
  if(SDL_strstr(poolID, COMPUTE) != null){ nShaders = cast(uint)shaders.length; }
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
void createDescriptors(ref App app, Shader[] shaders, const(char)* set = RENDER) {
  if(app.verbose) SDL_Log("createDescriptors: %s pipeline", set);
  app.layouts[set] = app.createDescriptorSetLayout(shaders);
  app.sets[set] = createDescriptorSet(app.device, app.pools[set], app.layouts[set],  app.framesInFlight);

  app.frameDeletionQueue.add((){ 
    vkDestroyDescriptorSetLayout(app.device, app.layouts[set], app.allocator); 
  });
}

/** Update the DescriptorSet
 */
void updateDescriptorSet(ref App app, Shader[] shaders, VkDescriptorSet[] dstSet, uint syncIndex = 0) {
  if(app.trace) SDL_Log("updateDescriptorSet");
  VkWriteDescriptorSet[] descriptorWrites;  // DescriptorSet write commands
  VkDescriptorBufferInfo[] bufferInfos;     // Buffer information for this update
  VkDescriptorImageInfo[] imageInfos;       // Image information for this update

  for(uint s = 0; s < shaders.length; s++) {
    auto shader = shaders[s];
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(app.trace) SDL_Log("- Descriptor[%d]: '%s' '%s'", shader.descriptors[d].binding, shader.descriptors[d].base, shader.descriptors[d].name);
      // Image sampler write
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) {
        if(to!string(shader.descriptors[d].name) == "texureSampler") {
          app.writeTextureSampler(descriptorWrites, shader.descriptors[d], dstSet[syncIndex], imageInfos);
        }
        if(to!string(shader.descriptors[d].name) == "shadowMap"){
          app.writeShadowMap(descriptorWrites, shader.descriptors[d], dstSet[syncIndex], imageInfos);
        }
        if(to!string(shader.descriptors[d].name) == "hdrSampler"){
          app.writeHDRSampler(descriptorWrites, shader.descriptors[d], dstSet[syncIndex], imageInfos);
        }
      }
      // Uniform Buffer Write
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
        app.writeUniformBuffer(descriptorWrites, shader.descriptors[d], dstSet, bufferInfos, syncIndex);
      }
      // SSBO Buffer Write
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
        app.writeSSBO(descriptorWrites, shader.descriptors[d], dstSet, bufferInfos, syncIndex);
      }
      // Compute Stored Image
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
        app.writeComputeImage(descriptorWrites, shader.descriptors[d], dstSet[syncIndex], imageInfos);
      }
    }
  }
  vkUpdateDescriptorSets(app.device, cast(uint)descriptorWrites.length, &descriptorWrites[0], 0, null);
  if(app.trace) SDL_Log("updateComputeDescriptorSet DONE");
}

