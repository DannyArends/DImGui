/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : createCommandBuffer;
import descriptor : createDescriptorSetLayout, createDescriptorSet, updateDescriptorData;
import images : imageBarrier, transitionImageLayout;
import shaders : loadShaders, createStageInfo;
import sync : insertFillBarrier;
import textures : idx;
import validation : pushLabel, popLabel, nameVulkanObject;
import vector : vCeilDiv;

/** Compute structure with shaders, command buffer and pipelines */
struct Compute {
  Shader[] shaders;                     /// Compute shader objects
  VkCommandBuffer[][string] commands;   /// Command buffers
  GraphicsPipeline[string] pipelines;   /// Pipelines
  ComputePass[string] passes;           /// Per-shader pre/workItems/post hooks, keyed by shader.path
}

/** When a compute pass is dispatched relative to the scene render. */
enum ComputeStage : ubyte {
  PreRender,    /// before the scene pass — feeds it (e.g. light culling)
  PostDepth     /// after the scene pass writes depth — consumes it (e.g. SSAO)
}

/** Per-shader compute behaviour, keyed by shader.path (like DescriptorProvider is keyed by descriptor name).
 * pre/post record commands (barriers, buffer fills, image transitions); workItems is CPU-side sizing only —
 * it records no commands, just returns raw item counts before group-size division. */
struct ComputePass {
  ComputeStage stage = ComputeStage.PreRender;
  bool delegate(ref App app) enabled; /// null = always enabled; else pass runs only when it returns true
  uint[3] delegate(ref App app, Shader shader) workItems; /// required
  uint[2] delegate(ref App app) resolution; /// null = full camera res; else maps base dims
  void delegate(ref App app, VkCommandBuffer cmd, Shader shader) pre; /// null = none
  void delegate(ref App app, VkCommandBuffer cmd, Shader shader) post; /// null = none
}

ShaderDef[] ComputeShaders = [
  ShaderDef("data/shaders/compute.cull.glsl", shaderc_glsl_compute_shader),
  ShaderDef("data/shaders/compute.ssao.glsl", shaderc_glsl_compute_shader)
];

/** Load shader modules for compute */
void initializeCompute(ref App app) {
  app.loadShaders(app.compute.shaders, ComputeShaders);

  // cull.glsl: ClusterHeads/ClusterCounter/ClusterLights are cross-stage
  app.compute.passes["data/shaders/compute.cull.glsl"] = ComputePass(
    stage: ComputeStage.PreRender,
    pre: (ref App a, VkCommandBuffer cmd, Shader shader) {
      VkBuffer headBuf = a.buffers["ClusterHeads"][a.syncIndex].buffer;
      VkBuffer cursorBuf = a.buffers["ClusterCounter"][a.syncIndex].buffer;
      vkCmdFillBuffer(cmd, headBuf, 0, VK_WHOLE_SIZE, NIL);
      vkCmdFillBuffer(cmd, cursorBuf, 0, VK_WHOLE_SIZE, 0);
      cmd.insertFillBarrier(headBuf, VK_WHOLE_SIZE);
      cmd.insertFillBarrier(cursorBuf, VK_WHOLE_SIZE);
    },
    workItems: (ref App a, Shader shader) { uint[3] r = [cast(uint)a.lights.length, 1u, 1u]; return r; }
  );

  app.compute.passes["data/shaders/compute.ssao.glsl"] = ComputePass(
    stage: ComputeStage.PostDepth,
    enabled: (ref App a) => a.useSSAO,
    resolution: (ref App a) { uint[2] r = [a.camera.width, a.camera.height]; return(r); },
    workItems: (ref App a, Shader shader) {
      auto p = shader.path in a.compute.passes;
      auto d = (p && p.resolution) ? p.resolution(a) : cast(uint[2])[a.camera.width, a.camera.height];
      uint[3] r = [d[0], d[1], 1u]; return(r);
    },
    pre: (ref App a, VkCommandBuffer cmd, Shader shader) {
      // order the depth read after the previous frame's depth writes (same queue, earlier submission)
      imageBarrier(cmd, a.depthBuffer.image,
                   VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
                   VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT,
                   VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                   0, 1, 0, 1, VK_IMAGE_ASPECT_DEPTH_BIT);
      a.transitionImageLayout(cmd, a.textures[a.textures.idx("ssaoOut")].image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_GENERAL);
    },
    post: (ref App a, VkCommandBuffer cmd, Shader shader) {
      a.transitionImageLayout(cmd, a.textures[a.textures.idx("ssaoOut")].image, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    }
  );
}

/** A pass runs when it has no enabled predicate, or its predicate returns true */
bool passEnabled(ref App app, string path) {
  auto pass = path in app.compute.passes; return(pass is null || pass.enabled is null || pass.enabled(app));
}

/** True if the compute pass runs at the given stage (PreRender if unregistered). */
bool isStage(ref App app, string path, ComputeStage s) {
  auto pass = path in app.compute.passes; return((pass is null ? ComputeStage.PreRender : pass.stage) == s);
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
  VkCommandPool pool = app.isStage(shader.path, ComputeStage.PreRender) ? app.computePool : app.commandPool;
  app.compute.commands[shader.path] = app.createCommandBuffer(pool, app.framesInFlight);
  if(app.verbose) SDL_Log("createComputeCommandBuffers: %d ComputeCommand, commandpool[%p]", app.framesInFlight, pool);
  app.swapDeletionQueue.add((){
    for (uint i = 0; i < app.framesInFlight; i++) { vkFreeCommandBuffers(app.device, pool, 1, &app.compute.commands[shader.path][i]); }
  });
}

/** Record one compute pass's dispatch into an existing command buffer (no begin/end). */
void dispatchCompute(ref App app, VkCommandBuffer cmd, Shader shader) {
  auto pass = shader.path in app.compute.passes;
  auto pipeline = app.compute.pipelines[shader.path];

  pushLabel(cmd, cstr("Compute: %s", baseName(fromStringz(shader.path))), Colors.palegoldenrod);
  app.updateDescriptorData([shader], app.sceneCmd.commands, app.syncIndex);
  if(pass.pre !is null) pass.pre(app, cmd, shader);
  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.pipeline);
  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.layout, 0, 1, &app.sets[shader.path][app.syncIndex], 0, null);
  uint[3] groups = vCeilDiv(pass.workItems(app, shader), shader.groupCount);
  vkCmdDispatch(cmd, groups[0], groups[1], groups[2]);
  if(pass.post !is null) pass.post(app, cmd, shader);
  popLabel(cmd);
}

/** recordComputeCommandBuffer: pure scaffold — begin/bind/dispatch/end. All per-shader behaviour lives in app.compute.passes[shader.path]. */
void recordComputeCommandBuffer(ref App app, Shader shader) {
  if(app.trace) SDL_Log("Record Compute Command Buffer [%s]: %d", toStringz(shader.path), app.syncIndex);
  auto cmd = app.compute.commands[shader.path][app.syncIndex];
  auto pipeline = app.compute.pipelines[shader.path];
  enforceVK(vkResetCommandBuffer(cmd, 0));

  VkCommandBufferBeginInfo commandBufferInfo = { sType : VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
  enforceVK(vkBeginCommandBuffer(cmd, &commandBufferInfo));
  app.nameVulkanObject(cmd, cstr("[COMMANDBUFFER] Compute %s %d", fromStringz(shader.path), app.syncIndex), VK_OBJECT_TYPE_COMMAND_BUFFER);

  pushLabel(cmd, cstr("Compute: %s", baseName(fromStringz(shader.path))), Colors.palegoldenrod);
  app.updateDescriptorData([shader], app.compute.commands[shader.path], app.syncIndex);

  auto pass = shader.path in app.compute.passes;
  assert(pass !is null, "No ComputePass registered for " ~ shader.path);

  if(pass.pre !is null) pass.pre(app, cmd, shader);

  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.pipeline);
  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.layout, 0, 1, &app.sets[shader.path][app.syncIndex], 0, null);

  uint[3] groups = vCeilDiv(pass.workItems(app, shader), shader.groupCount);
  vkCmdDispatch(cmd, groups[0], groups[1], groups[2]);

  if(pass.post !is null) pass.post(app, cmd, shader);

  popLabel(cmd);
  enforceVK(vkEndCommandBuffer(cmd));
  if(app.trace) SDL_Log("Compute Command Buffer: %d Done", app.syncIndex);
}
