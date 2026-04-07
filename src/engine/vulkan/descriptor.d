/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import lights : updateLighting;
import ssbo : updateSSBO;
import textures : idx;
import validation : nameVulkanObject;

enum DescriptorTarget { None, Textures, Shadow, HDR, Compute }

struct Descriptor {
  VkDescriptorType type;    /// Type of Descriptor
  DescriptorTarget target;  /// Image target (resolved at load time, avoids per-frame string dispatch)

  string name;              /// Name
  string base;              /// Base / Struct Name
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
    foreach(ref b; bindings) { // Check if the binding already exists in another stage
      if(b.binding == binding) {
        b.stageFlags |= shaderStage;  // If yes, add the stageflag to the binding
        return;
      }
    }
    VkDescriptorSetLayoutBinding layout = { binding: binding, stageFlags: shaderStage, descriptorCount: count, descriptorType: type };
    bindings ~= layout;
  }

  void clear(){ bindings = []; }

  VkDescriptorSetLayout build(VkDevice device, VkDescriptorSetLayoutCreateFlags flags = 0, void* pNext = null){
    VkDescriptorBindingFlags[] bindingFlags;
    bindingFlags.length = bindings.length;
    foreach(i, ref b; bindings) { 
      bindingFlags[i] = (b.descriptorCount > 1) ? VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT : 0;
    }

    VkDescriptorSetLayoutBindingFlagsCreateInfo bindingFlagsInfo = {
      sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
      bindingCount: cast(uint)bindingFlags.length,
      pBindingFlags: &bindingFlags[0]
    };

    VkDescriptorSetLayoutCreateInfo info = {
      sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      pBindings: &bindings[0],
      bindingCount: cast(uint)bindings.length,
      flags: flags,
      pNext: &bindingFlagsInfo
    };

    VkDescriptorSetLayout set;
    enforceVK(vkCreateDescriptorSetLayout(device, &info, null, &set));
    return set;
  }
};

VkDescriptorSetLayout createDescriptorSetLayout(ref App app, Shader[] shaders) {
  DescriptorLayoutBuilder builder;
  foreach(shader; shaders) {
    foreach(descriptor; shader.descriptors) {
      if(app.verbose) SDL_Log(toStringz(format("[%d] cnt: %d = %s %s", descriptor.binding, descriptor.count, shader.stage, descriptor.type)));
      builder.add(descriptor.binding, descriptor.count, shader.stage, descriptor.type);
    }
  }
  auto layout = builder.build(app.device);
  return(layout);
}

VkDescriptorPoolSize[] createPoolSizes(ref App app, Shader[] shaders) {
  VkDescriptorPoolSize[] poolSizes;
  foreach(shader; shaders) {
    foreach(descriptor; shader.descriptors) {
      poolSizes ~= VkDescriptorPoolSize(descriptor.type, descriptor.count * cast(uint)(app.framesInFlight));
    }
  }
  return(poolSizes);
}

void createDSPool(ref App app, string poolID, VkDescriptorPoolSize[] poolSizes, uint maxSets = 1024) {
  if(app.verbose) SDL_Log("Creating DescriptorPool[%s]", toStringz(poolID));
  app.pools[poolID] = VkDescriptorPool();
  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : maxSets, /// Allocate maxSets (Default: 1024 Sets)
    poolSizeCount : cast(uint)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.pools[poolID]));
  app.nameVulkanObject(app.pools[poolID], toStringz("[POOL] " ~ fromStringz(poolID)), VK_OBJECT_TYPE_DESCRIPTOR_POOL);
  if(app.verbose) SDL_Log("Created %s DescriptorPool: %p", toStringz(poolID), app.pools[poolID]);
}

/** ImGui DescriptorPool (Images)
 */
void createImGuiDescriptorPool(ref App app) {
  VkDescriptorPoolSize[] poolSizes = [{
    type : VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount : 1000 ///IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE
  }];
  app.createDSPool(Stage.IMGUI, poolSizes);
  app.mainDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.pools[Stage.IMGUI], app.allocator); });
}

/** ImGui DescriptorSetLayout (1000 * Combined Image Samplers)
 */
void createImGuiDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating ImGui DescriptorSetLayout");
  DescriptorLayoutBuilder builder;
  builder.add(0, 1, VK_SHADER_STAGE_FRAGMENT_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
  app.layouts[Stage.IMGUI] = builder.build(app.device);
  app.nameVulkanObject(app.layouts[Stage.IMGUI], toStringz(format("[DESCRIPTOR] Layout %s", Stage.IMGUI)), VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT);

  app.mainDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.layouts[Stage.IMGUI], app.allocator); });
}

/** Create a descriptor pool based on the shaders provided
 */
void createDSPool(ref App app, string poolID, Shader[] shaders) {
  uint nShaders = 1;
  if(poolID == Stage.COMPUTE){ nShaders = cast(uint)shaders.length; }
  if(app.verbose) SDL_Log("createDSPool by shader: %s, with %d shader size", toStringz(poolID), nShaders);
  VkDescriptorPoolSize[] poolSizes = app.createPoolSizes(shaders);
  app.createDSPool(poolID, poolSizes, nShaders * app.framesInFlight);
  app.swapDeletionQueue.add((){ 
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

void updateDescriptorData(ref App app, Shader[] shaders, VkCommandBuffer[] cmdBuffer, VkDescriptorType type, uint syncIndex) {
  Descriptor[string] elements;
  foreach(shader; shaders){
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(!(shader.descriptors[d].base in elements)) elements[shader.descriptors[d].base] = shader.descriptors[d];
    }
  }
  if("BoneMatrices" in elements) {
    app.updateSSBO!Matrix(cmdBuffer[syncIndex], app.boneOffsets, elements["BoneMatrices"], syncIndex);
  }
  if("MeshMatrices" in elements) {
    app.updateSSBO!Mesh(cmdBuffer[syncIndex], app.meshes, elements["MeshMatrices"], syncIndex);
  }
  if("LightMatrices" in elements) {
    app.updateLighting(cmdBuffer[syncIndex], elements["LightMatrices"]);
  }
}

/** Create our DescriptorSet (UBO and Combined image sampler)
 */
void createDescriptors(ref App app, Shader[] shaders, Stage stage = Stage.RENDER) {
  if(app.verbose) SDL_Log("createDescriptors: %d pipeline", stage);
  app.layouts[stage] = app.createDescriptorSetLayout(shaders);
  app.nameVulkanObject(app.layouts[stage], toStringz(format("[DESCRIPTORLAYOUT] %s", stage)), VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT);
  app.sets[stage] = createDescriptorSet(app.device, app.pools[stage], app.layouts[stage],  app.framesInFlight);

  for (uint i = 0; i < app.framesInFlight; i++) {
    app.updateDescriptorSet(shaders, app.sets[stage], i);
    app.nameVulkanObject(app.sets[stage][i], toStringz(format("[DESCRIPTORSET] %s #%d", stage, i)), VK_OBJECT_TYPE_DESCRIPTOR_SET);
  }

  app.swapDeletionQueue.add((){ 
    vkDestroyDescriptorSetLayout(app.device, app.layouts[stage], app.allocator); 
  });
}

/** Helper to assemble a VkWriteDescriptorSet
 */
VkWriteDescriptorSet makeWrite(VkDescriptorSet dst, uint binding, VkDescriptorType type, VkDescriptorImageInfo* img, VkDescriptorBufferInfo* buf) {
  VkWriteDescriptorSet set = {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: dst, dstBinding: binding, dstArrayElement: 0,
    descriptorType: type, descriptorCount: 1,
    pImageInfo: img, pBufferInfo: buf
  };
  return set;
}

/** Populate imageInfos for a given descriptor target
 */
void writeImageInfos(ref App app, ref VkDescriptorImageInfo[] imageInfos, Descriptor d) {
  final switch(d.target) {
    case DescriptorTarget.Textures:
      foreach(ref img; app.textures.textures) {
        VkDescriptorImageInfo info = {
          imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
          imageView: img.view,
          sampler: app.sampler
        };
        imageInfos ~= info;
      }
      break;
    case DescriptorTarget.Shadow:
      foreach(ref img; app.shadows.images) {
        VkDescriptorImageInfo info = {
          imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
          imageView: img.view,
          sampler: app.sampler
        };
        imageInfos ~= info;
      }
      break;
    case DescriptorTarget.HDR:
      VkDescriptorImageInfo info = {
        imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        imageView: app.resolvedHDR.view,
        sampler: app.sampler
      };
      imageInfos ~= info;
      break;
    case DescriptorTarget.Compute:
      VkDescriptorImageInfo info = {
        imageLayout: VK_IMAGE_LAYOUT_GENERAL,
        imageView: app.textures[app.textures.idx(d.name)].view,
      };
      imageInfos ~= info;
      break;
    case DescriptorTarget.None: break;
  }
}

/** Write a single descriptor (buffer or image) into the write + info arrays
 */
void writeDescriptor(ref App app, ref VkWriteDescriptorSet[] write,
                     ref VkDescriptorBufferInfo[] bufferInfos,
                     ref VkDescriptorImageInfo[] imageInfos,
                     Descriptor d, VkDescriptorSet dst, uint syncIndex) {
  size_t start = imageInfos.length;
  // SSBO Buffer Write
  if(d.type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
    if(app.verbose) SDL_Log("writeDescriptor SSBO %s = %d (%d x %d)", toStringz(d.base), d.size, d.bytes, d.nObjects);
    bufferInfos ~= VkDescriptorBufferInfo(app.buffers[d.base].buffers[syncIndex], 0, d.size);
    write ~= makeWrite(dst, d.binding, d.type, null, &bufferInfos[$-1]);
  }
  // Uniform Buffer Write
  if(d.type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
    if(app.verbose) SDL_Log("writeDescriptor UBO[%s] #%d", toStringz(d.base), syncIndex);
    bufferInfos ~= VkDescriptorBufferInfo(app.ubos[d.base].buffers[syncIndex], 0, d.bytes);
    write ~= makeWrite(dst, d.binding, d.type, null, &bufferInfos[$-1]);
  }
  // Image sampler / Compute Stored Image Write
  if(d.type == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER || d.type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
    app.writeImageInfos(imageInfos, d);
    VkWriteDescriptorSet set = makeWrite(dst, d.binding, d.type, &imageInfos[start], null);
    set.descriptorCount = cast(uint)(imageInfos.length - start);
    write ~= set;
  }
}

/** Update the DescriptorSet
 */
void updateDescriptorSet(ref App app, Shader[] shaders, VkDescriptorSet[] dstSet, uint syncIndex = 0) {
  if(app.trace) SDL_Log("updateDescriptorSet");
  VkWriteDescriptorSet[] descriptorWrites;  // DescriptorSet write commands
  VkDescriptorBufferInfo[] bufferInfos;     // Buffer information for this update
  VkDescriptorImageInfo[] imageInfos;       // Image information for this update

  foreach(shader; shaders) {
    foreach(d; shader.descriptors) {
      if(app.trace) SDL_Log(toStringz(format("- Descriptor[%d]: '%s'", d.binding, d)));
      app.writeDescriptor(descriptorWrites, bufferInfos, imageInfos, d, dstSet[syncIndex], syncIndex);
    }
  }
  vkUpdateDescriptorSets(app.device, cast(uint)descriptorWrites.length, &descriptorWrites[0], 0, null);
}

