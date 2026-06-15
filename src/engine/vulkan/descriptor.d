/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import lights : updateLighting;
import ssbo : updateSSBO, createSSBO;
import textures : idx;
import reflection : CLUSTER_COUNT;
import validation : nameVulkanObject;

enum DescriptorTarget { None, Textures, Shadow, HDR, Compute }

struct Descriptor {
  VkDescriptorType type;    /// Type of Descriptor
  DescriptorTarget target;  /// Image target (resolved at load time, avoids per-frame string dispatch)

  string name;              /// Name
  string base;              /// Base / Struct Name
  size_t bytes;             /// Size  of the structure

  uint set;                 /// DescriptorSet
  uint binding;             /// DescriptorSet Binding
  uint count;               /// Descriptor count
}

struct DescriptorProvider {
  void delegate(ref App, ref Descriptor) create; /// once, at resource creation
  void delegate(ref App, ref Descriptor, VkCommandBuffer) onFrame; /// per pass per frame (null = none)
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

/** ImGui DescriptorPool (Images) */
void createImGuiDescriptorPool(ref App app) {
  VkDescriptorPoolSize[] poolSizes = [{
    type : VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount : 1000 ///IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE
  }];
  app.createDSPool(Stage.IMGUI, poolSizes);
  app.mainDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.pools[Stage.IMGUI], app.allocator); });
}

/** ImGui DescriptorSetLayout (1000 * Combined Image Samplers) */
void createImGuiDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating ImGui DescriptorSetLayout");
  DescriptorLayoutBuilder builder;
  builder.add(0, 1, VK_SHADER_STAGE_FRAGMENT_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
  app.layouts[Stage.IMGUI] = builder.build(app.device);
  app.nameVulkanObject(app.layouts[Stage.IMGUI], toStringz(format("[DESCRIPTOR] Layout %s", Stage.IMGUI)), VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT);

  app.mainDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.layouts[Stage.IMGUI], app.allocator); });
}

/** Create a descriptor pool based on the shaders provided */
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

/** Allocate a Descriptor Set */
VkDescriptorSet[] createDescriptorSet(VkDevice device, VkDescriptorPool pool, VkDescriptorSetLayout layout, uint size){
  VkDescriptorSetLayout[] layouts;
  VkDescriptorSet[] set;
  layouts.length = set.length = size;
  layouts[] = layout;

  VkDescriptorSetAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    descriptorPool: pool,
    descriptorSetCount: size,
    pSetLayouts: &layouts[0]
  };
  enforceVK(vkAllocateDescriptorSets(device, &allocInfo, &set[0]));
  return(set);
}

/** Register creators for the render SSBOs (mirrors updateDescriptorData) */
void registerRenderProviders(ref App app) {
  app.providers["BoneMatrices"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, a.boneOffsets); },
    (ref a, ref d, cmd){ a.updateSSBO!Matrix(cmd, a.boneOffsets, d, a.syncIndex); });
  app.providers["LightMatrices"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, a.lights); },
    (ref a, ref d, cmd){ a.updateLighting(cmd, d); });
  app.providers["MeshMatrices"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, a.meshes); },
    (ref a, ref d, cmd){ a.updateSSBO!Mesh(cmd, a.meshes, d, a.syncIndex); });
  app.providers["MaterialBuffer"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, a.materials); },
    (ref a, ref d, cmd){ a.updateSSBO!Material(cmd, a.materials, d, a.syncIndex); });

  app.providers["ClusterLights"] = DescriptorProvider(
    (ref a, ref d){ if(a.clusterCapacity == 0){ a.clusterCapacity = CLUSTER_COUNT; } a.createSSBO(d, a.clusterCapacity, 0, true); },
    null);
  app.providers["ClusterHeads"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, CLUSTER_COUNT, 0, true); },
    null);
  app.providers["ClusterCounter"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, 1, 0, false); foreach(i; 0 .. a.buffers["ClusterCounter"].length){ *cast(uint*)a.buffers["ClusterCounter"][i].data = 0; } },
    null);
}

void updateDescriptorData(ref App app, Shader[] shaders, VkCommandBuffer[] cmdBuffer, uint syncIndex) {
  Descriptor[string] elements;
  foreach(shader; shaders){ foreach(ref d; shader.descriptors){
    if(!(d.base in elements)){ elements[d.base] = d; }
  } }
  foreach(base, ref d; elements) { if(auto p = base in app.providers) {
    if(p.onFrame){ p.onFrame(app, d, cmdBuffer[syncIndex]); }
  } }
}

/** Create our DescriptorSet (UBO and Combined image sampler) */
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

/** Helper to assemble a VkWriteDescriptorSet */
VkWriteDescriptorSet makeWrite(VkDescriptorSet dst, uint binding, VkDescriptorType type, VkDescriptorImageInfo* img, VkDescriptorBufferInfo* buf) {
  VkWriteDescriptorSet set = {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: dst, dstBinding: binding, dstArrayElement: 0,
    descriptorType: type, descriptorCount: 1,
    pImageInfo: img, pBufferInfo: buf
  };
  return set;
}

void append(T)(ref VkDescriptorImageInfo[] infos, T[] images, VkSampler sampler, VkImageLayout layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
  foreach(ref img; images){ infos ~= VkDescriptorImageInfo(sampler, img.view, layout); }
}

/** Populate imageInfos for a given descriptor target */
void writeImageInfos(ref App app, ref VkDescriptorImageInfo[] imageInfos, Descriptor d) {
  final switch(d.target) {
    case DescriptorTarget.Textures: imageInfos.append(app.textures.textures, app.sampler); break;
    case DescriptorTarget.Shadow: imageInfos.append(app.shadows.images, app.shadows.sampler); break;
    case DescriptorTarget.HDR: imageInfos.append([app.resolvedHDR], app.sampler); break;
    case DescriptorTarget.Compute: imageInfos.append([app.textures[app.textures.idx(d.name)]], app.sampler, VK_IMAGE_LAYOUT_GENERAL); break;
    case DescriptorTarget.None: break;
  }
}

/** Re-point descriptor sets whose buffers/images were swapped this frame. Safe when syncIndex's render+compute fences are 
 * cleared in waitForFrame and nothing has bound sets[syncIndex] yet this frame. */
void repointDirtyDescriptors(ref App app) {
  if(!app.buffers.descriptorsDirty[app.syncIndex] && !app.shadows.shadowDescriptorsDirty[app.syncIndex]) return;
  foreach(key, sets; app.sets) {
    switch(key) {
      case Stage.RENDER:  app.updateDescriptorSet(app.shaders, sets, app.syncIndex); break;
      case Stage.SHADOWS: app.updateDescriptorSet(app.shadows.shaders, sets, app.syncIndex); break;
      case Stage.POST:    app.updateDescriptorSet(app.postProcess, sets, app.syncIndex); break;
      case Stage.IMGUI:   break;
      default: foreach(ref s; app.compute.shaders) if(s.path == key){ app.updateDescriptorSet([s], sets, app.syncIndex); break; }
    }
  }
  app.buffers.descriptorsDirty[app.syncIndex] = false;
  app.shadows.shadowDescriptorsDirty[app.syncIndex] = false;
}

/** Write a single descriptor (buffer or image) into the write + info arrays */
void writeDescriptor(ref App app, ref VkWriteDescriptorSet[] write, ref size_t[] infoIndex,
                     ref VkDescriptorBufferInfo[] bufferInfos, ref VkDescriptorImageInfo[] imageInfos,
                     Descriptor d, VkDescriptorSet dst, uint syncIndex) {
  size_t start = imageInfos.length;
  // SSBO Buffer Write
  if(d.type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
    if(app.verbose) SDL_Log("writeDescriptor %s = %d (%d x %d)", toStringz(d.base), app.buffers[d.base].size, app.buffers[d.base].stride, app.buffers[d.base].nObjects);
    uint idx = syncIndex % cast(uint)app.buffers[d.base].length;
    bufferInfos ~= VkDescriptorBufferInfo(app.buffers[d.base][idx].buffer, 0, app.buffers[d.base].size);
    write ~= makeWrite(dst, d.binding, d.type, null, null);
    infoIndex ~= bufferInfos.length - 1;
  }
  // Uniform Buffer Write
  if(d.type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
    if(app.verbose) SDL_Log("writeDescriptor UBO[%s] #%d", toStringz(d.base), syncIndex);
    bufferInfos ~= VkDescriptorBufferInfo(app.ubos[d.base].buffers[syncIndex], 0, d.bytes);
    write ~= makeWrite(dst, d.binding, d.type, null, null);
    infoIndex ~= bufferInfos.length - 1;
  }
  // Image sampler / Compute Stored Image Write
  if(d.type == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER || d.type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
    app.writeImageInfos(imageInfos, d);
    VkWriteDescriptorSet set = makeWrite(dst, d.binding, d.type, null, null);
    set.descriptorCount = cast(uint)(imageInfos.length - start);
    write ~= set;
    infoIndex ~= start;
  }
}

/** Update the DescriptorSet */
void updateDescriptorSet(ref App app, Shader[] shaders, VkDescriptorSet[] dstSet, uint syncIndex = 0) {
  if(app.trace) SDL_Log("updateDescriptorSet");
  VkWriteDescriptorSet[] descriptorWrites;  // DescriptorSet write commands
  VkDescriptorBufferInfo[] bufferInfos;     // Buffer information for this update
  VkDescriptorImageInfo[] imageInfos;       // Image information for this update
  size_t[] infoIndex;                       // per-write: slot into bufferInfos/imageInfos (array picked by type)

  foreach(shader; shaders) {
    foreach(d; shader.descriptors) {
      if(app.trace) { SDL_Log(toStringz(format("- Descriptor[%d]: '%s'", d.binding, d))); }
      app.writeDescriptor(descriptorWrites, infoIndex, bufferInfos, imageInfos, d, dstSet[syncIndex], syncIndex);
    }
  }

  foreach(i, idx; infoIndex) {              // arrays are final now — addresses are stable
    auto t = descriptorWrites[i].descriptorType;
    if(t == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER || t == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER){
      descriptorWrites[i].pBufferInfo = &bufferInfos[idx];
    }else{ descriptorWrites[i].pImageInfo = &imageInfos[idx]; }
  }
  if(descriptorWrites.length){ vkUpdateDescriptorSets(app.device, cast(uint)descriptorWrites.length, &descriptorWrites[0], 0, null); }
}
