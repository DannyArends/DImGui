/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : createCommandBuffer, beginSingleTimeCommands, endSingleTimeCommands;
import descriptor : createDescriptorSetLayout, createDescriptorSet, updateDescriptorData;
import images : createImage, nameImageBuffer, cleanup, transitionImageLayout;
import shaders : loadShaders, createStageInfo;
import ssbo : updateSSBO, createSSBO;
import sync : insertWriteBarrier, insertReadBarrier, insertFillBarrier;
import textures : idx, registerTexture;
import quaternion : xyzw;
import uniforms : createUBO;
import validation : pushLabel, popLabel, nameVulkanObject;
import views : createImageView, createLayerViews;
import vector : vCeilDiv;

/** Compute structure with shaders, command buffer and pipelines */
struct Compute {
  size_t lastTick;                      /// Last tick
  ParticleSystem system;                /// Particles
  Shader[] shaders;                     /// Compute shader objects
  VkCommandBuffer[][string] commands;   /// Command buffers
  GraphicsPipeline[string] pipelines;   /// Pipelines
  ComputePass[string] passes;           /// Per-shader pre/workItems/post hooks, keyed by shader.path
}

/** Per-shader compute behaviour, keyed by shader.path (like DescriptorProvider is keyed by descriptor name).
 * pre/post record commands (barriers, buffer fills, image transitions); workItems is CPU-side sizing only —
 * it records no commands, just returns raw item counts before group-size division. */
struct ComputePass {
  void delegate(ref App app, VkCommandBuffer cmd, Shader shader, uint syncIndex) pre; /// null = none
  uint[3] delegate(ref App app, Shader shader) workItems; /// required
  void delegate(ref App app, VkCommandBuffer cmd, Shader shader, uint syncIndex) post; /// null = none
}

ShaderDef[] ComputeShaders = [ShaderDef("data/shaders/texture.glsl", shaderc_glsl_compute_shader),
                              ShaderDef("data/shaders/particle.glsl", shaderc_glsl_compute_shader),
                              ShaderDef("data/shaders/cull.glsl", shaderc_glsl_compute_shader)];

/** Load shader modules for compute */
void initializeCompute(ref App app) {
  app.compute.system = new ParticleSystem(2048);
  app.loadShaders(app.compute.shaders, ComputeShaders);

  // cull.glsl — ClusterHeads/ClusterCounter/ClusterLights are cross-stage (also read by scene.glsl's forward+ shading),
  // so their providers stay wherever shared render/shadow resources are registered, not here.
  app.compute.passes["data/shaders/cull.glsl"] = ComputePass(
    pre: (ref App a, VkCommandBuffer cmd, Shader shader, uint syncIndex) {
      VkBuffer headBuf = a.buffers["ClusterHeads"][syncIndex].buffer;
      VkBuffer cursorBuf = a.buffers["ClusterCounter"][syncIndex].buffer;
      vkCmdFillBuffer(cmd, headBuf, 0, VK_WHOLE_SIZE, NIL);
      vkCmdFillBuffer(cmd, cursorBuf, 0, VK_WHOLE_SIZE, 0);
      cmd.insertFillBarrier(headBuf);
      cmd.insertFillBarrier(cursorBuf);
    },
    workItems: (ref App a, Shader shader) { uint[3] r = [cast(uint)a.lights.length, 1u, 1u]; return r; }
  );

  // particle.glsl — ParticleUniformBuffer/lastFrame/currentFrame exist only for this shader (no #include shares them),
  // so their providers are grouped here with the pass that owns them.
  app.providers["ParticleUniformBuffer"] = DescriptorProvider(  // UBO
    (ref a, ref d){ a.createUBO(d); },
    (ref a, ref d, cmd){ a.updateComputeUBO(d, a.syncIndex); });

  app.providers["lastFrame"] = DescriptorProvider(  // SSBO
    (ref a, ref d){
      a.createSSBO(d, a.compute.system.particles);
      auto cmd = app.beginSingleTimeCommands(app.commandPool);
      for(uint i = 0; i < app.framesInFlight; i++) { app.updateSSBO(cmd, a.compute.system.particles, d, i); }
      app.endSingleTimeCommands(cmd, app.queue);
    },
    null);
  app.providers["currentFrame"] = DescriptorProvider((ref a, ref d){ a.createSSBO(d, a.compute.system.particles); }, null);
  
  app.compute.passes["data/shaders/particle.glsl"] = ComputePass(
    workItems: (ref App a, Shader shader) {
      foreach(ref d; shader.descriptors) {
        if(d.type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) { uint[3] r = [a.buffers[d.base].nObjects, 1u, 1u]; return r; }
      }
      uint[3] r = [1u, 1u, 1u]; return r;
    },
    post: (ref App a, VkCommandBuffer cmd, Shader shader, uint syncIndex) {
      VkBuffer src = a.buffers["currentFrame"][syncIndex].buffer;
      VkBuffer dst = a.buffers["lastFrame"][syncIndex].buffer;
      VkBufferCopy copyRegion = { size: a.buffers["currentFrame"].size };
      cmd.insertWriteBarrier(dst);
      vkCmdCopyBuffer(cmd, src, dst, 1, &copyRegion);
      cmd.insertReadBarrier(src);
    }
  );

  // texture.glsl — storage image created generically via createResources' VK_DESCRIPTOR_TYPE_STORAGE_IMAGE fallback, no provider needed
  app.compute.passes["data/shaders/texture.glsl"] = ComputePass(
    pre: (ref App a, VkCommandBuffer cmd, Shader shader, uint syncIndex) {
      foreach(ref d; shader.descriptors) {
        if(d.type != VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) continue;
        uint idx = a.textures.idx(d.name);
        a.transitionImageLayout(cmd, a.textures[idx].image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_GENERAL);
      }
    },
    workItems: (ref App a, Shader shader) {
      foreach(ref d; shader.descriptors) {
        if(d.type != VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) continue;
        uint idx = a.textures.idx(d.name);
        uint[3] r = [a.textures[idx].width, a.textures[idx].height, 1u]; return r;
      }
      uint[3] r = [1u, 1u, 1u]; return r;
    },
    post: (ref App a, VkCommandBuffer cmd, Shader shader, uint syncIndex) {
      foreach(ref d; shader.descriptors) {
        if(d.type != VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) continue;
        uint idx = a.textures.idx(d.name);
        a.transitionImageLayout(cmd, a.textures[idx].image, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
      }
    }
  );
}

/** Create the compute pipeline specified by the selectedShader */
void createComputePipeline(ref App app, Shader shader) {
  if(app.verbose) SDL_Log("createComputePipeline for Shader %s", toStringz(shader.path));
  app.compute.pipelines[shader.path] = GraphicsPipeline();
  app.layouts[shader.path] = app.createDescriptorSetLayout([shader]);
  app.nameVulkanObject(app.layouts[shader.path], cstr("[DESCRIPTORLAYOUT] %s", fromStringz(shader.path)), VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT);

  app.sets[shader.path] = createDescriptorSet(app.device, app.pools[Stage.COMPUTE], app.layouts[shader.path],  app.framesInFlight);
  for (uint i = 0; i < app.framesInFlight; i++) {
    app.nameVulkanObject(app.sets[shader.path][i], cstr("[DESCRIPTORSET] %s #%d", fromStringz(shader.path), i), VK_OBJECT_TYPE_DESCRIPTOR_SET);
  }
  VkPipelineLayoutCreateInfo computeLayout = {
    sType : VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pSetLayouts : &app.layouts[shader.path],
    setLayoutCount : 1,
    pNext : null
  };
  enforceVK(vkCreatePipelineLayout(app.device, &computeLayout, null, &app.compute.pipelines[shader.path].layout));

  ShaderStage stage = createStageInfo([shader], VK_PRIMITIVE_TOPOLOGY_POINT_LIST, Specialization.init);

  VkComputePipelineCreateInfo computeInfo = {
    sType : VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
    layout : app.compute.pipelines[shader.path].layout,
    stage : stage.info[0],
    pNext : null
  };

  VkPipeline computePipeline;
  enforceVK(vkCreateComputePipelines(app.device, null, 1, &computeInfo, null, &computePipeline));
  app.compute.pipelines[shader.path].set(computePipeline);

  app.nameVulkanObject(app.compute.pipelines[shader.path].layout, cstr("[LAYOUT] Compute %s", fromStringz(shader.path)), VK_OBJECT_TYPE_PIPELINE_LAYOUT);
  app.nameVulkanObject(app.compute.pipelines[shader.path].pipeline, cstr("[PIPELINE] Compute %s", fromStringz(shader.path)), VK_OBJECT_TYPE_PIPELINE);

  if(app.verbose) SDL_Log("Compute pipeline [sel: %s] at: %p", toStringz(shader.path), app.compute.pipelines[shader.path].pipeline);

  app.swapDeletionQueue.add((){
    vkDestroyDescriptorSetLayout(app.device, app.layouts[shader.path], app.allocator);
    vkDestroyPipelineLayout(app.device, app.compute.pipelines[shader.path].layout, app.allocator);
    vkDestroyPipeline(app.device, app.compute.pipelines[shader.path].pipeline, app.allocator);
  });
}

void createComputeCommandBuffers(ref App app, Shader shader) {
  app.compute.commands[shader.path] = app.createCommandBuffer(app.commandPool, app.framesInFlight);
  if(app.verbose) SDL_Log("createComputeCommandBuffers: %d ComputeCommand, commandpool[%p]", app.framesInFlight, app.commandPool);
  app.swapDeletionQueue.add((){
    for (uint i = 0; i < app.framesInFlight; i++) {
      vkFreeCommandBuffers(app.device, app.commandPool, 1, &app.compute.commands[shader.path][i]);
    }
  });
}

void updateComputeUBO(ref App app, Descriptor d, uint syncIndex) {
  size_t now = SDL_GetTicks();
  ParticleUniformBuffer buffer = {
    position:  app.compute.system.position.xyzw,
    gravity:   app.compute.system.gravity.xyzw,
    floor:     app.compute.system.floor,
    deltaTime: cast(float)(now - app.compute.lastTick) / 100.0f
  };
  app.compute.lastTick = now;
  memcpy(app.ubos[d.base][syncIndex].data, &buffer, d.bytes);
}

void createStorageImage(ref App app, Descriptor descriptor){
  VkImageUsageFlags usage;
  usage |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  usage |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  usage |= VK_IMAGE_USAGE_STORAGE_BIT;
  usage |= VK_IMAGE_USAGE_SAMPLED_BIT;
  usage |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

  Texture texture = Texture(path : descriptor.name, width: app.camera.width, height: app.camera.height);

  app.createImage(texture, texture.width, texture.height,
                  VK_FORMAT_R8G8B8A8_UNORM, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL, usage);
  app.createLayerViews(texture, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_ASPECT_COLOR_BIT);
  app.nameImageBuffer(texture, "Compute Image");

  auto cmd = app.beginSingleTimeCommands(app.commandPool);
  app.transitionImageLayout(cmd, texture.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
  app.endSingleTimeCommands(cmd, app.queue);

  if(app.verbose) SDL_Log("Create compute image %p, view: %p", texture.image, texture.view);
  app.registerTexture(texture); // Register texture with ImGui

  // Update the Texture Array for rendering
  app.textures ~= texture;
  app.mainDeletionQueue.add((){ app.cleanup(texture); });
}

/** recordComputeCommandBuffer: pure scaffold — begin/bind/dispatch/end. All per-shader behaviour lives in app.compute.passes[shader.path]. */
void recordComputeCommandBuffer(ref App app, Shader shader, uint syncIndex = 0) {
  if(app.trace) SDL_Log("Record Compute Command Buffer [%s]: %d", toStringz(shader.path), syncIndex);
  auto cmd = app.compute.commands[shader.path][syncIndex];
  auto pipeline = app.compute.pipelines[shader.path];
  enforceVK(vkResetCommandBuffer(cmd, 0));

  VkCommandBufferBeginInfo commandBufferInfo = { sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
  enforceVK(vkBeginCommandBuffer(cmd, &commandBufferInfo));
  app.nameVulkanObject(cmd, cstr("[COMMANDBUFFER] Compute %s %d", fromStringz(shader.path), syncIndex), VK_OBJECT_TYPE_COMMAND_BUFFER);

  pushLabel(cmd, cstr("Compute: %s", baseName(fromStringz(shader.path))), Colors.palegoldenrod);
  app.updateDescriptorData([shader], app.compute.commands[shader.path], syncIndex);

  auto pass = shader.path in app.compute.passes;
  assert(pass !is null, "No ComputePass registered for " ~ shader.path);

  if(pass.pre !is null) pass.pre(app, cmd, shader, syncIndex);

  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.pipeline);
  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.layout, 0, 1, &app.sets[shader.path][syncIndex], 0, null);

  uint[3] groups = vCeilDiv(pass.workItems(app, shader), shader.groupCount);
  vkCmdDispatch(cmd, groups[0], groups[1], groups[2]);

  if(pass.post !is null) pass.post(app, cmd, shader, syncIndex);

  popLabel(cmd);
  enforceVK(vkEndCommandBuffer(cmd));
  if(app.trace) SDL_Log("Compute Command Buffer: %d Done", syncIndex);
}
