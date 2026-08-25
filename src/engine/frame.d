/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import descriptorupdate : repointDirtyDescriptors;
import commands : recordSceneCommandBuffer, recordPostCommandBuffer, recordDepthPrePass, recordUploadPass;
import compute : recordComputeCommandBuffer, ComputeStage, passEnabled, isStage;
import imgui : recordImGuiCommandBuffer;
import lights : updateDisco, updateLightGeometries, LMode, computeActiveLighting;
import mesh : updateMeshInfo;
import shadow :  recordShadowCommandBuffer;
import sfx : updateTracks;
import textures : updateTextures;
import timing : timed;
import text : updateWorldTextBillboards;
import window : createOrResizeWindow;

/** waitForFrame */
@nogc void waitForFrame(ref App app) nothrow {
  if(app.trace) SDL_Log("Phase 0: Wait for CPU-GPU Sync for current frame in flight");
  if(app.fences[app.syncIndex].computeSubmitted) {
    enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.syncIndex].computeInFlight, true, ulong.max));
    app.fences[app.syncIndex].computeSubmitted = false;
  }
  enforceVK(vkResetFences(app.device, 1, &app.fences[app.syncIndex].computeInFlight));

  enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.syncIndex].renderInFlight, true, ulong.max));
  enforceVK(vkResetFences(app.device, 1, &app.fences[app.syncIndex].renderInFlight));
  app.bufferDeletionQueue.flush();
}

/** Orchestrate one frame: acquire → CPU work → compute → record → submit. */
void renderFrame(ref App app, double dt) {
  if(app.trace) SDL_Log("renderFrame");
  if(!app.acquireFrame()) return;                          // Phase 1: acquire (early-out on out-of-date)

  app.recordCPUWork(dt);                                   // Phase 1.1: CPU updates
  app.submitPreRenderCompute();                            // Phase 2: record all compute, submit PreRender (cull)
  app.timed!recordUploadPass();                            // Phase 2.5: upload dirty geometry

  bool shadowsThisFrame = app.recordShadows(dt);           // Phase 3: shadow maps
  app.recordScenePasses();                                 // Phase 4: depth, scene, post, imgui

  app.submitFrame(shadowsThisFrame);                       // Phase 5: three-way submit
  if(app.trace) SDL_Log("Done renderFrame: %d", app.syncIndex);
  app.totalFramesRendered++;
}

/** Phase 1: acquire the next swapchain image. Returns false if the frame must be skipped (swapchain out of date). */
bool acquireFrame(ref App app) {
  VkSemaphore imageAcquired = app.sync[app.syncIndex].imageAcquired;
  if(app.trace) SDL_Log("Phase 1: Aquire the image");
  auto err = vkAcquireNextImageKHR(app.device, app.swapChain, ulong.max, imageAcquired, null, &app.frameIndex);
  if(err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR || err == VK_ERROR_SURFACE_LOST_KHR) app.rebuild = true;
  if(err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_ERROR_SURFACE_LOST_KHR) return(false);
  if(err != VK_SUBOPTIMAL_KHR) enforceVK(err);
  if(app.trace) SDL_Log("Phase 1: Aquired %d", app.frameIndex);
  return(true);
}

/** Phase 1.1: per-frame CPU updates (sound, textures, lighting, billboards, descriptors). */
void recordCPUWork(ref App app, double dt) {
  if(app.trace) SDL_Log("Phase 1.1: Do CPU work");
  app.timed!updateTracks();
  app.timed!updateTextures();
  app.timed!updateMeshInfo();
  app.timed!updateDisco(dt);
  app.timed!computeActiveLighting();
  app.timed!updateWorldTextBillboards();
  app.timed!repointDirtyDescriptors();
}

/** Phase 2: record every compute pass, then submit the PreRender ones (e.g. cull) on the compute queue. */
void submitPreRenderCompute(ref App app) {
  if(!app.hasCompute) return;
  if(app.trace) SDL_Log("Phase 2.1: Prepare Compute Work");
  VkCommandBuffer[] computeCommandBuffers;
  foreach(ref shader; app.compute.shaders){
    if(!app.passEnabled(shader.path)) continue;
    app.timed!recordComputeCommandBuffer(shader);
    if(app.isStage(shader.path, ComputeStage.PreRender)) { computeCommandBuffers ~= app.compute.commands[shader.path][app.syncIndex]; }
  }
  if(computeCommandBuffers.length == 0) return;
  VkSemaphore computeComplete = app.sync[app.syncIndex].computeComplete;
  VkSubmitInfo submitComputeInfo = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    signalSemaphoreCount : 1, pSignalSemaphores : &computeComplete,
    commandBufferCount : cast(uint)computeCommandBuffers.length, pCommandBuffers : &computeCommandBuffers[0],
  };
  if(app.trace) SDL_Log("Phase 2.2: Submit Compute work");
  enforceVK(vkQueueSubmit(app.queues.compute.queue, 1, &submitComputeInfo, app.fences[app.syncIndex].computeInFlight));
  app.fences[app.syncIndex].computeSubmitted = true;
}

/** Phase 3: record shadow maps if enabled this frame; returns whether shadows were recorded. */
bool recordShadows(ref App app, double dt) {
  bool shadowsThisFrame = app.lMode >= LMode.LightsAndShadows;
  if(app.trace) SDL_Log("Phase 3: Prepare ShadowMap");
  if(app.worldReady && shadowsThisFrame) {
    app.timed!updateLightGeometries(dt);
    app.timed!recordShadowCommandBuffer(app.syncIndex);
    return(true);
  }
  return(false);
}

/** Phase 4: record depth pre-pass, scene, post-process, and ImGui command buffers. */
void recordScenePasses(ref App app) {
  if(app.trace) SDL_Log("Phase 4: Recording Scene, Post-processing, and ImGui");
  if(app.worldReady) {
    app.timed!recordDepthPrePass();
    app.timed!recordSceneCommandBuffer(app.shaders);
    app.timed!recordPostCommandBuffer();
  }
  app.timed!recordImGuiCommandBuffer();
}

/** Phase 5: graphics(depth+resolve) → async compute(SSAO) → graphics(shadows+scene+post+imgui). */
void submitFrame(ref App app, bool shadowsThisFrame) {
  if(app.trace) SDL_Log("Phase 5: Submit CommandBuffers");
  bool ssaoAsync = app.submitDepth();
  app.submitAsyncSSAO(ssaoAsync);
  app.submitScene(shadowsThisFrame, ssaoAsync);
}

/** Submit 1 (graphics): upload + depth + resolve. Returns whether async SSAO runs this frame (signals depthComplete if so). */
bool submitDepth(ref App app) {
  bool ssaoAsync = false;
  if(app.worldReady && app.hasCompute){ foreach(ref shader; app.compute.shaders) {
    if(!app.passEnabled(shader.path)) continue;
    if(app.isStage(shader.path, ComputeStage.PostDepthAsync)){ ssaoAsync = true; }
  } }

  VkCommandBuffer[] depthCmds;
  depthCmds ~= app.uploadCmd[app.syncIndex];
  if(app.worldReady) {
    depthCmds ~= app.depthCmd[app.syncIndex];
    if(app.hasCompute){ foreach(ref shader; app.compute.shaders) {
      if(!app.passEnabled(shader.path)) continue;
      if(app.isStage(shader.path, ComputeStage.PostDepth)){ depthCmds ~= app.compute.commands[shader.path][app.syncIndex]; }
    } }
  }
  VkSemaphore depthComplete = app.sync[app.syncIndex].depthComplete;
  VkSubmitInfo si = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount : cast(uint)depthCmds.length, pCommandBuffers : &depthCmds[0],
    signalSemaphoreCount : ssaoAsync ? 1 : 0, pSignalSemaphores : ssaoAsync ? &depthComplete : null
  };
  enforceVK(vkQueueSubmit(app.queues.graphics.queue, 1, &si, null));
  return(ssaoAsync);
}

/** Submit 2 (compute): async SSAO; waits depthComplete, signals ssaoComplete. No-op when ssaoAsync is false. */
void submitAsyncSSAO(ref App app, bool ssaoAsync) {
  if(!ssaoAsync) return;
  VkCommandBuffer[] ssaoCmds;
  foreach(ref shader; app.compute.shaders) {
    if(!app.passEnabled(shader.path)) continue;
    if(app.isStage(shader.path, ComputeStage.PostDepthAsync)){ ssaoCmds ~= app.compute.commands[shader.path][app.syncIndex]; }
  }
  VkSemaphore depthComplete = app.sync[app.syncIndex].depthComplete;
  VkSemaphore ssaoComplete = app.sync[app.syncIndex].ssaoComplete;
  VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
  VkSubmitInfo si = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    waitSemaphoreCount : 1, pWaitSemaphores : &depthComplete, pWaitDstStageMask : &waitStage,
    commandBufferCount : cast(uint)ssaoCmds.length, pCommandBuffers : &ssaoCmds[0],
    signalSemaphoreCount : 1, pSignalSemaphores : &ssaoComplete
  };
  enforceVK(vkQueueSubmit(app.queues.compute.queue, 1, &si, null));
}

/** Submit 3 (graphics): shadows + scene + post + imgui; waits imageAcquired (+compute/ssao), signals renderComplete. */
void submitScene(ref App app, bool shadowsThisFrame, bool ssaoAsync) {
  VkCommandBuffer[] submitCommandBuffers;
  if(app.worldReady) {
    if(shadowsThisFrame) { submitCommandBuffers ~= app.shadows.cmd[app.syncIndex]; }
    submitCommandBuffers ~= app.sceneCmd[app.syncIndex];
    submitCommandBuffers ~= app.postCmd[app.syncIndex];
  }
  submitCommandBuffers ~= app.imguiCmd[app.syncIndex];

  VkSemaphore computeComplete = app.sync[app.syncIndex].computeComplete;
  VkSemaphore imageAcquired   = app.sync[app.syncIndex].imageAcquired;
  VkSemaphore ssaoComplete    = app.sync[app.syncIndex].ssaoComplete;
  VkSemaphore renderComplete  = app.renderComplete[app.frameIndex];

  WaitList!3 wait;
  wait.add(imageAcquired, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
  if(app.fences[app.syncIndex].computeSubmitted) { wait.add(computeComplete, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT); }
  if(ssaoAsync) { wait.add(ssaoComplete, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT); }

  VkSubmitInfo submitInfo = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    waitSemaphoreCount : wait.count, pWaitSemaphores : &wait.sems[0], pWaitDstStageMask : &wait.stages[0],
    commandBufferCount : cast(uint)submitCommandBuffers.length, pCommandBuffers : &submitCommandBuffers[0],
    signalSemaphoreCount : 1, pSignalSemaphores : &renderComplete
  };
  enforceVK(vkQueueSubmit(app.queues.graphics.queue, 1, &submitInfo, app.fences[app.syncIndex].renderInFlight));
}

@nogc void presentFrame(ref App app) nothrow {
  if (app.trace) SDL_Log("presentFrame");
  if (app.rebuild) return;
  VkSemaphore renderComplete = app.renderComplete[app.frameIndex];
  VkPresentInfoKHR info = {
    sType : VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
    waitSemaphoreCount : 1,
    pWaitSemaphores : &renderComplete,
    swapchainCount : 1,
    pSwapchains : &app.swapChain,
    pImageIndices : &app.frameIndex,
  };
  auto err = vkQueuePresentKHR(app.queues.graphics.queue, &info);
  if(err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR || err == VK_ERROR_SURFACE_LOST_KHR) app.rebuild = true;
  if(err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_ERROR_SURFACE_LOST_KHR) return;
  if(err != VK_SUBOPTIMAL_KHR) enforceVK(err);
  app.syncIndex = (app.syncIndex + 1) % app.sync.length; // Now we can use the next set of semaphores
  if(app.trace) SDL_Log("Done presentFrame");
}

