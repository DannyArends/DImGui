/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commandpool : createCommandBuffer, beginSingleTimeCommands, endSingleTimeCommands;
import ssbo : updateSSBO, createSSBO;
import textures : idx;
import uniforms : createUBO, updateRenderUBO;
import shadow : updateShadowMapUBO;
import ssao : updateSSAO;
import validation : nameVulkanObject;

/** Register creators for the render SSBOs */
void registerRenderProviders(ref App app) {
  // UBO
  app.providers["UniformBufferObject"] = DescriptorProvider(
    (ref a, ref d){ a.createUBO(d); },
    (ref a, ref d, cmd){ a.updateRenderUBO(d, a.syncIndex); });
  app.providers["LightSpaceMatrices"] = DescriptorProvider(
    (ref a, ref d){ a.createUBO(d); },
    (ref a, ref d, cmd){ a.updateShadowMapUBO(d, a.syncIndex); });
  // SSBO
  app.providers["BoneMatrices"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, a.boneOffsets); },
    (ref a, ref d, cmd){ a.updateSSBO!Matrix(cmd, a.boneOffsets, d, a.syncIndex); });
  app.providers["LightMatrices"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, a.lights); },
    (ref a, ref d, cmd){ a.updateSSBO!Light(cmd, a.lights, d, a.syncIndex); });
  app.providers["MaterialBuffer"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, a.materials); },
    (ref a, ref d, cmd){ a.updateSSBO!Material(cmd, a.materials, d, a.syncIndex); });
  app.providers["ColorBuffer"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, a.colors); },
    (ref a, ref d, cmd){ a.updateSSBO!Material(cmd, a.colors, d, a.syncIndex); });
  /// Lights
  app.providers["ClusterLights"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, a.clusterCapacity, true, true); }, null);
  app.providers["ClusterHeads"] = DescriptorProvider(
    (ref a, ref d){
      a.createSSBO(d, CLUSTER_COUNT, true, true);
      auto cmd = a.beginSingleTimeCommands(a.commandPool);
      foreach(i; 0 .. a.buffers[d.base].length){ vkCmdFillBuffer(cmd, a.buffers[d.base][i].buffer, 0, VK_WHOLE_SIZE, NIL); }
      a.endSingleTimeCommands(cmd, a.gfxQueue);
    },
    null);
  app.providers["ClusterCounter"] = DescriptorProvider(
    (ref a, ref d){ a.createSSBO(d, 1, false); }, null);
  /// SSAO
  app.providers["SSAO"] = DescriptorProvider(
    (ref a, ref d){ a.createUBO(d); },
    (ref a, ref d, cmd){ a.updateSSAO(d, a.syncIndex); });
}

void updateDescriptorData(ref App app, Shader[] shaders, VkCommandBuffer[] cmdBuffer, uint syncIndex) {
  Descriptor[string] elements;
  foreach(shader; shaders){ foreach(ref d; shader.descriptors){
    if(!(d.base in elements)){ elements[d.base] = d; }
  } }
  foreach(base, ref d; elements){ if(auto p = base in app.providers) { if(p.onFrame) {
    if(p.lastFrame == app.totalFramesRendered) continue;
    p.lastFrame = app.totalFramesRendered;
    p.onFrame(app, d, cmdBuffer[syncIndex]);
  } } }
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

/** Helper to append imageInfos */
void append(T)(ref VkDescriptorImageInfo[] infos, T images, VkSampler sampler, uint layer = 0, 
               VkImageLayout layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
  foreach(ref img; images){ infos ~= VkDescriptorImageInfo(sampler, img.view(layer), layout); }
}

/** Populate imageInfos for a given descriptor target */
void writeImageInfos(ref App app, ref VkDescriptorImageInfo[] imageInfos, Descriptor d) {
  final switch(d.target) {
    case DescriptorTarget.Textures: imageInfos.append(app.textures.textures, app.sampler); break;
    case DescriptorTarget.Shadow: imageInfos.append(app.shadows.images, app.shadows.sampler, 1); break;
    case DescriptorTarget.HDR: imageInfos.append([app.resolvedHDR], app.sampler); break;
    case DescriptorTarget.Compute: imageInfos.append([app.textures[app.textures.idx(d.name)]], app.sampler, 0, VK_IMAGE_LAYOUT_GENERAL); break;
    case DescriptorTarget.Depth: imageInfos.append([app.depthBuffer], app.sampler, 0, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL); break;
    case DescriptorTarget.SSAO: imageInfos.append([app.textures[app.textures.idx("ssaoOut")]], app.sampler); break;
    case DescriptorTarget.WBOITAccum:  imageInfos.append([app.wboit.accumulation], null, 0, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL); break;
    case DescriptorTarget.WBOITReveal: imageInfos.append([app.wboit.revealage], null, 0, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL); break;
    case DescriptorTarget.None: break;
  }
}

/** Re-point descriptor sets whose buffers/images were swapped this frame. Safe when syncIndex's render+compute fences are 
 * cleared in waitForFrame and nothing has bound sets[syncIndex] yet this frame. */
void repointDirtyDescriptors(ref App app) {
  if(!app.buffers.descriptorsDirty[app.syncIndex] && !app.shadows.shadowDescriptorsDirty[app.syncIndex]) return;
  foreach(key, sets; app.sets) {
    switch(key) {
      case Stage.RENDER: app.updateDescriptorSet(app.shaders, sets, app.syncIndex); break;
      case Stage.SHADOWS: app.updateDescriptorSet(app.shadows.shaders, sets, app.syncIndex); break;
      case Stage.POST: app.updateDescriptorSet(app.postProcess, sets, app.syncIndex); break;
      case Stage.RESOLVE: app.updateDescriptorSet(app.wboit.shaders, sets, app.syncIndex); break;
      case Stage.IMGUI: break;
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
    bufferInfos ~= VkDescriptorBufferInfo(app.ubos[d.base][syncIndex].buffer, 0, d.bytes);
    write ~= makeWrite(dst, d.binding, d.type, null, null);
    infoIndex ~= bufferInfos.length - 1;
  }
  // Image sampler / Compute Stored Image Write
  if(d.type == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER ||
     d.type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE ||
     d.type == VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT) {
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
      if(app.trace) { SDL_Log(cstr("- Descriptor[%d]: '%s'", d.binding, d)); }
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
