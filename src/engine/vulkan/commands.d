/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import frustum : cullFrustum, extractFrustum;
import boundingbox : computeBoundingBox;
import descriptor : updateDescriptorData;
import geometry : draw, bufferGeometries;
import ssbo : updateSSBO;
import matrix : multiply;
import validation : pushLabel, popLabel, nameVulkanObject;
import wboit : drawWBOITResolve;
import window: supportedTopologies;

enum DrawPass : int { Opaque = 0, Transparent = 1 }

/** A recordable command buffer (one per syncIndex); records one or more RenderPass instances. */
struct CommandBuffer(size_t N){
  RenderPass[N] renderpass;
  VkCommandBuffer[] commands;       /// per-syncIndex buffers
  alias commands this;

  void create(ref App app, VkCommandPool pool, uint nBuffers) { app.createCommandBuffer(commands, pool, nBuffers); }

  @property ref RenderPass pass(uint id = 0) { return(renderpass[id]); }

  VkCommandBuffer begin(ref App app, uint syncIndex, string label) {
    enforceVK(vkResetCommandBuffer(commands[syncIndex], 0));
    VkCommandBufferBeginInfo beginInfo = { sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
    enforceVK(vkBeginCommandBuffer(commands[syncIndex], &beginInfo));
    app.nameVulkanObject(commands[syncIndex], cstr("[COMMANDBUFFER] %s %d", label, syncIndex), VK_OBJECT_TYPE_COMMAND_BUFFER);
    return commands[syncIndex];
  }

  void end(uint syncIndex) { enforceVK(vkEndCommandBuffer(commands[syncIndex])); }
}

/** Draw per-object bounding boxes (debug, LINE_LIST, alpha-test variant) */
void drawBoundingBoxes(ref App app, VkCommandBuffer cmd) {
  pushLabel(cmd, cstr("%d x Bounding Boxes", app.objects.length), Colors.lightgray);

  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipelines[VK_PRIMITIVE_TOPOLOGY_LINE_LIST].get(app, Specialization(false, true)));
  for(size_t x = 0; x < app.objects.length; x++) {
    if(!app.objects[x].isDrawable || !app.objects[x].inFrustum || !app.objects[x].isVisible) continue;
    if(app.objects[x].hasBoundingBox && app.objects[x].box.isDrawable) app.draw(app.objects[x].box, cmd);
  }
  popLabel(cmd);
}

/** Draw every visible object of one topology for one DrawPass; rebinds the pipeline only when the specialization changed */
void drawTopologyPass(ref App app, VkCommandBuffer cmd, VkPrimitiveTopology topology, VkDescriptorSet set, 
                      DrawPass pass, bool depthPass = false, bool wboit = false) {
  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipelines[topology].layout, 0, 1, &set, 0, null);

  Specialization last; bool first = true;
  foreach(obj; app.objects) {
    if(!obj.isTopology(topology) || !obj.isDrawable || !obj.inFrustum || !obj.isVisible) continue;
    if(!depthPass && obj.isOpaque && pass == DrawPass.Transparent) continue;  // opaque never in WBOIT
    auto s = Specialization(!obj.isOpaque, obj.instancedMesh, obj.isSDF, app.useSSAO, obj.isAnimated, depthPass, wboit);
    pushLabel(cmd, cstr("%s [topo: %d, A=%d, I=%d, S=%d, D=%d]", obj.geometry(), topology, s.alpha, s.instanced, s.sdf, s.depthPass), Colors.lightgray);
    if(first || last != s) {
      vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.pipelines[topology].get(app, s)); 
      last = s; first = false; 
    }
    app.draw(obj, cmd);
    popLabel(cmd);
  }
}

/** Record scene command buffer: SSBO -> Objects -> Rendering */
void recordSceneCommandBuffer(ref App app, Shader[] shaders) {
  auto cmd = app.sceneCmd.begin(app, app.syncIndex, "Render");

  pushLabel(cmd, "Rendering", Colors.lightgray);
  if(app.trace) SDL_Log("Starting Scene renderpass");

  if(app.camera.isDirty) { app.objects.cullFrustum(extractFrustum(app.camera.proj.multiply(app.camera.view))); app.camera.isDirty = false; }

  pushLabel(cmd, "Descriptors & SSBO", Colors.lightgray);
  app.updateDescriptorData(app.shaders, app.depthCmd.commands, app.syncIndex);
  popLabel(cmd);

  app.sceneCmd.pass.begin(cmd, app.frameIndex, app.camera.currentExtent, app.clearValue);
  if(app.trace) SDL_Log("Render pass recording to buffer %d", app.syncIndex);

  if(app.trace) SDL_Log("Going to draw %d objects to renderBuffer %d", app.objects.length, app.syncIndex);
  auto set = app.sets[Stage.RENDER][app.syncIndex];

  // Subpass 0: Opaque draws
  foreach(topology; supportedTopologies) { app.drawTopologyPass(cmd, topology, set, DrawPass.Opaque); }
  if(app.showBounds) app.drawBoundingBoxes(cmd);

  // Subpass 1: WBOIT: Accumulation of transparent draws
  vkCmdNextSubpass(cmd, VK_SUBPASS_CONTENTS_INLINE);
  foreach(topology; supportedTopologies) { app.drawTopologyPass(cmd, topology, set, DrawPass.Transparent, false, true); }

  // Subpass 2: WBOIT: Resolve into composite
  vkCmdNextSubpass(cmd, VK_SUBPASS_CONTENTS_INLINE);
  app.drawWBOITResolve(cmd);

  app.sceneCmd.pass.end(cmd);
  popLabel(cmd);

  app.sceneCmd.end(app.syncIndex);
}

/** Record post-process command buffer */
void recordPostCommandBuffer(ref App app) {
  auto cmd = app.postCmd.begin(app, app.syncIndex, "Post");

  pushLabel(cmd, "Post-processing", Colors.lightgray);
  if(app.trace) SDL_Log("Starting Post-processing");

  app.postCmd.pass.begin(cmd, app.frameIndex, app.camera.currentExtent, app.clearValue[0..1]);

  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.postProcessPipeline.pipeline());
  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.postProcessPipeline.layout, 0, 1, &app.sets[Stage.POST][app.syncIndex], 0, null);

  vkCmdDraw(cmd, 3, 1, 0, 0);
  app.postCmd.pass.end(cmd);
  popLabel(cmd);
  if(app.trace) SDL_Log("Finished Post-processing");
  app.postCmd.end(app.syncIndex);
}

/** Record the depth pre-pass: opaque geometry, depth-only, into app.depthCmd (feeds SSAO before the lit scene pass). */
void recordDepthPrePass(ref App app) {
  auto cmd = app.depthCmd.begin(app, app.syncIndex, "DepthPrePass");
  pushLabel(cmd, "Depth Pre-pass", Colors.lightgray);
    pushLabel(cmd, "Objects Buffering", Colors.lightgray);
    if(app.trace) SDL_Log("Objects Buffering");
    app.bufferGeometries(cmd);
    popLabel(cmd);

    pushLabel(cmd, "Descriptors & SSBO", Colors.lightgray);
    app.updateDescriptorData(app.shaders, app.depthCmd.commands, app.syncIndex);
    popLabel(cmd);

    app.depthCmd.pass.begin(cmd, app.frameIndex, app.camera.currentExtent, app.clearValue[2..3]);  // depth clear only

    auto set = app.sets[Stage.RENDER][app.syncIndex];
    foreach(topology; supportedTopologies) {
      if(topology !in app.pipelines) continue;
      app.drawTopologyPass(cmd, topology, set, DrawPass.Opaque, true);
    }

    app.depthCmd.pass.end(cmd);
  popLabel(cmd);
  app.depthCmd.end(app.syncIndex);
}

void createCommandPools(ref App app) {
  app.commandPool = app.createCommandPool(app.queueFamily);
  app.transferPool = app.createCommandPool(app.queueFamily);

  app.nameVulkanObject(app.commandPool, toStringz("[COMMANDPOOL] Render"), VK_OBJECT_TYPE_COMMAND_POOL);
  app.nameVulkanObject(app.transferPool, toStringz("[COMMANDPOOL] Transfer"), VK_OBJECT_TYPE_COMMAND_POOL);

  if(app.verbose) SDL_Log("createCommandPools[family:%d] Queue: %p, Transfer: %p", app.queueFamily, app.commandPool, app.transferPool);
}

VkCommandPool createCommandPool(ref App app, uint queueFamilyIndex) {
  VkCommandPool commandPool;

  VkCommandPoolCreateInfo poolInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    queueFamilyIndex: queueFamilyIndex,
    flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
  };
  enforceVK(vkCreateCommandPool(app.device, &poolInfo, null, &commandPool));
  app.mainDeletionQueue.add((){ vkDestroyCommandPool(app.device, commandPool, app.allocator); });

  if(app.trace) SDL_Log("Commandpool %p at queue %d created", commandPool, poolInfo.queueFamilyIndex);
  return(commandPool);
}

VkCommandBuffer[] createCommandBuffer(App app, VkCommandPool pool, uint nBuffers = 1) {
  VkCommandBuffer[] commandBuffer;
  commandBuffer.length = nBuffers;

  VkCommandBufferAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool: pool,
    level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount: nBuffers
  };
  enforceVK(vkAllocateCommandBuffers(app.device, &allocInfo, &(commandBuffer[0])));
  if(app.trace) SDL_Log("%d CommandBuffer(s) created from pool %p", nBuffers, pool);
  app.swapDeletionQueue.add((){ vkFreeCommandBuffers(app.device, pool, cast(uint)commandBuffer.length, &commandBuffer[0]); });
  return(commandBuffer);
}

void createCommandBuffer(ref App app, ref VkCommandBuffer[] dst, VkCommandPool pool, uint nBuffers = 1) { 
  dst = app.createCommandBuffer(pool, nBuffers);
}

/** Structure returned as result of an (async) SingleTimeCommand submission */
struct SingleTimeCommand {
  bool async = false;       /// Is the transfer happening async ?
  VkFence fence;            /// If aSync the fence we need to wait for before data is on the GPU
  VkCommandPool pool;       /// The command pool the buffer was allocated from
  VkCommandBuffer commands; /// The command buffer used for this specific transfer
  alias commands this;
}

/** beginSingleTimeCommands() begins a commandbuffer using the VkCommandPool pool
 * async: If true: add commands, submit to the correct queue. 
          If false: add commands, the use endSingleTimeCommands to submit and WaitIdle for the Queue */
SingleTimeCommand beginSingleTimeCommands(ref App app, VkCommandPool pool, bool async = false) {
  VkCommandBuffer commandBuffer = app.createCommandBuffer(pool, 1)[0];

  VkCommandBufferBeginInfo beginInfo = {
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
  };
  vkBeginCommandBuffer(commandBuffer, &beginInfo);
  VkFence completionFence;
  if(async) {
    VkFenceCreateInfo fenceInfo = {
        sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        flags: 0
    };
    enforceVK(vkCreateFence(app.device, &fenceInfo, app.allocator, &completionFence));
  }
  return SingleTimeCommand(async, completionFence, pool, commandBuffer);
}

void endSingleTimeCommands(ref App app, SingleTimeCommand cmd, VkQueue queue) {
  if(cmd.async) assert(0, "Never endSingleTimeCommands() on Async events");
  vkEndCommandBuffer(cmd.commands);

  VkSubmitInfo submitInfo = {
    sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount: 1,
    pCommandBuffers: &cmd.commands
  };

  enforceVK(vkQueueSubmit(queue, 1, &submitInfo, null));
  enforceVK(vkQueueWaitIdle(queue));
  vkFreeCommandBuffers(app.device, cmd.pool, 1, &cmd.commands);
}
