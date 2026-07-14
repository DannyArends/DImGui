/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import bone : updateBoneOffsets;
import descriptor : repointDirtyDescriptors;
import commands : recordSceneCommandBuffer, recordPostCommandBuffer;
import compute : recordComputeCommandBuffer, ComputeStage;
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
  if(app.hasCompute) {
    enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.syncIndex].computeInFlight, true, ulong.max));
    enforceVK(vkResetFences(app.device, 1, &app.fences[app.syncIndex].computeInFlight));
  }
  enforceVK(vkWaitForFences(app.device, 1, &app.fences[app.syncIndex].renderInFlight, true, ulong.max));
  enforceVK(vkResetFences(app.device, 1, &app.fences[app.syncIndex].renderInFlight));
  app.bufferDeletionQueue.flush();
}

/** Main Frame rendering loop a 3D Frame:
 * Aquire Image -> CPU -> GPU Compute -> Shadows -> Graphic -> ImGui */
void renderFrame(ref App app, double dt) {
  bool shadowsThisFrame = app.lMode == LMode.LightsAndShadows;
  if(app.trace) SDL_Log("renderFrame");
  VkSemaphore computeComplete  = app.sync[app.syncIndex].computeComplete;
  VkSemaphore imageAcquired = app.sync[app.syncIndex].imageAcquired;

  if(app.trace) SDL_Log("Phase 1: Aquire the image");
  auto err = vkAcquireNextImageKHR(app.device, app.swapChain, uint.max, imageAcquired, null, &app.frameIndex);
  if(err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR || err == VK_ERROR_SURFACE_LOST_KHR) app.rebuild = true;
  if(err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_ERROR_SURFACE_LOST_KHR) return;
  if(err != VK_SUBOPTIMAL_KHR) enforceVK(err);
  if(app.trace) SDL_Log("Phase 1: Aquired %d", app.frameIndex);
  VkSemaphore renderComplete = app.renderComplete[app.frameIndex];

  if(app.trace) SDL_Log("Phase 1.1: Do CPU work");

  app.timed!updateTracks();                         /// Check for sound effects that have finished
  app.timed!updateTextures();                       /// If a texture was loaded, update it
  app.timed!updateMeshInfo();                       /// Check for Mesh Information change
  app.timed!updateBoneOffsets(app.syncIndex);       /// Check for animation causing BoneOffsets changes
  app.timed!updateDisco(dt);                        /// Update when disco mode 🕺 🪩 💃
  app.timed!computeActiveLighting();                /// Compute active lighting
  app.timed!updateWorldTextBillboards();            /// Face billboarded world text toward the camera
  app.timed!repointDirtyDescriptors();              /// Repoint dirty descriptors
  // SDL_Log("Frame[%d]: S:%d, F:%d", app.totalFramesRendered, app.syncIndex, app.frameIndex);

  // --- Phase 2: Record All Compute, and submit PreRender Compute Work ---
  bool preRenderSubmitted = false;
  if (app.hasCompute) { if(app.trace) SDL_Log("Phase 2.1: Prepare Compute Work");
    VkCommandBuffer[] computeCommandBuffers;
    foreach(ref shader; app.compute.shaders){
      app.timed!recordComputeCommandBuffer(shader);
      if(app.compute.passes[shader.path].stage != ComputeStage.PreRender) continue;
      computeCommandBuffers ~= app.compute.commands[shader.path][app.syncIndex];
    }
    if(computeCommandBuffers.length > 0) { // submit only if we have pre-render compute (e.g. Cull)
      VkSubmitInfo submitComputeInfo = {
        sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
        signalSemaphoreCount : 1, pSignalSemaphores : &computeComplete,
        commandBufferCount : cast(uint)computeCommandBuffers.length, pCommandBuffers : &computeCommandBuffers[0],
      };
      if(app.trace) SDL_Log("Phase 2.2: Submit Compute work");
      enforceVK(vkQueueSubmit(app.queue, 1, &submitComputeInfo, app.fences[app.syncIndex].computeInFlight));
      preRenderSubmitted = true;
    }
  }

  // --- Phase 3: Prepare Shadowmap ---
  if(app.trace) SDL_Log("Phase 3: Prepare ShadowMap");
  if(shadowsThisFrame) {
    app.timed!updateLightGeometries(dt);
    app.timed!recordShadowCommandBuffer(app.syncIndex);
  }else{ shadowsThisFrame = false; }

  // --- Phase 4: Record Scene renderer, Post-Process and ImGui ---
  if(app.trace) SDL_Log("Phase 4: Recording Scene, Post-processing, and ImGui");
  app.timed!recordSceneCommandBuffer(app.shaders);
  app.timed!recordPostCommandBuffer();
  app.timed!recordImGuiCommandBuffer();

  // --- Phase 5:  Submit CommandBuffers: Scene renderer, Post-Depth Compute, PostProcess and ImGui ---
  if(app.trace) SDL_Log("Phase 5: Submit CommandBuffers");
  VkCommandBuffer[] submitCommandBuffers;
  if(shadowsThisFrame) { submitCommandBuffers ~= app.shadows.cmd[app.syncIndex]; }
  submitCommandBuffers ~= app.sceneCmd[app.syncIndex];
  if(app.hasCompute){ foreach(ref shader; app.compute.shaders) { // Add Post-Depth Compute Command Buffers
    if(app.compute.passes[shader.path].stage == ComputeStage.PostDepth) {
      submitCommandBuffers ~= app.compute.commands[shader.path][app.syncIndex];
    }
  } }
  submitCommandBuffers ~= app.postCmd[app.syncIndex];
  submitCommandBuffers ~= app.imguiCmd[app.syncIndex];

  WaitList!2 wait;
  wait.add(imageAcquired, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
  if(preRenderSubmitted) { wait.add(computeComplete, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT); }

  VkSubmitInfo submitInfo = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    waitSemaphoreCount : wait.count, pWaitSemaphores : &wait.sems[0], pWaitDstStageMask : &wait.stages[0],
    commandBufferCount : cast(uint)submitCommandBuffers.length, pCommandBuffers : &submitCommandBuffers[0],
    signalSemaphoreCount : 1, pSignalSemaphores : &renderComplete
  };

  //SDL_Log("vkQueueSubmit: frame=%d sync=%d frameIndex=%d", app.totalFramesRendered, app.syncIndex, app.frameIndex);
  enforceVK(vkQueueSubmit(app.queue, 1, &submitInfo, app.fences[app.syncIndex].renderInFlight));
  if(app.trace) SDL_Log("Done renderFrame: %d", app.syncIndex);
  app.totalFramesRendered++;
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
  auto err = vkQueuePresentKHR(app.queue, &info);
  if(err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR || err == VK_ERROR_SURFACE_LOST_KHR) app.rebuild = true;
  if(err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_ERROR_SURFACE_LOST_KHR) return;
  if(err != VK_SUBOPTIMAL_KHR) enforceVK(err);
  app.syncIndex = (app.syncIndex + 1) % app.sync.length; // Now we can use the next set of semaphores
  if(app.trace) SDL_Log("Done presentFrame");
}

