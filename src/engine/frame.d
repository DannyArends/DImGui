/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import bone : updateBoneOffsets;
import descriptor : updateDescriptorSet, createDescriptors;
import commands : recordSceneCommandBuffer, recordPostCommandBuffer;
import compute : recordComputeCommandBuffer, updateComputeUBO;
import imgui : recordImGuiCommandBuffer;
import lights : updateDisco, updateLightGeometries, LMode;
import mesh : updateMeshInfo;
import shadow : updateShadowMapUBO, recordShadowCommandBuffer;
import sfx : updateTracks;
import textures : updateTextures;
import timing : timed;
import uniforms : updateRenderUBO;
import window : createOrResizeWindow;

/** waitForFrame */
void waitForFrame(ref App app) {
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
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);
  if(app.trace) SDL_Log("Phase 1: Aquired %d", app.frameIndex);
  VkSemaphore renderComplete = app.renderComplete[app.frameIndex];

  if(app.trace) SDL_Log("Phase 1.1: Do CPU work");

  app.timed!updateTracks();                         /// Check for sound effects that have finished
  app.timed!updateTextures();                       /// If a texture was loaded, update it
  app.timed!updateMeshInfo();                       /// Check for Mesh Information change
  app.timed!updateBoneOffsets(app.syncIndex, dt);   /// Check for animation causing BoneOffsets changes
  app.timed!updateDisco(dt);                        /// Update when disco mode 🕺 🪩 💃
  if(app.hasCompute) app.timed!updateComputeUBO(app.syncIndex);
  app.timed!updateShadowMapUBO(app.shadows.shaders, app.syncIndex);
  app.timed!updateRenderUBO(app.shaders, app.syncIndex);

  if(app.hasCompute && "ClusterCounter" in app.buffers) {
    // TODO: growing ClusterLights via app.rebuild recreates the whole swapchain/pipeline.
    // Replace with a targeted buffer recreate + descriptor update to avoid the frame hitch.
    uint used = *cast(uint*)app.buffers["ClusterCounter"].data[0];
    if(used > app.clusterCapacity) { app.clusterCapacity = used * 2; app.rebuild = true; }
  }

  // SDL_Log("Frame[%d]: S:%d, F:%d", app.totalFramesRendered, app.syncIndex, app.frameIndex);

  // --- Phase 2: Prepare & Submit Compute Work ---
  if (app.hasCompute) {
    if(app.trace) SDL_Log("Phase 2.1: Prepare Compute Work");
    VkCommandBuffer[] computeCommandBuffers = [];
    foreach(ref shader; app.compute.shaders){
      app.timed!recordComputeCommandBuffer(shader, app.syncIndex);
      computeCommandBuffers ~= app.compute.commands[shader.path][app.syncIndex];
    }

    VkSubmitInfo submitComputeInfo = {
      sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
      commandBufferCount : cast(uint)computeCommandBuffers.length,
      pCommandBuffers : &computeCommandBuffers[0],
      signalSemaphoreCount : 1,
      pSignalSemaphores : &computeComplete
    };
    if(app.trace) SDL_Log("Phase 2.2: Submit Compute work");
    enforceVK(vkQueueSubmit(app.queue, 1, &submitComputeInfo, app.fences[app.syncIndex].computeInFlight));
  }

  // --- Phase 3: Prepare Shadowmap ---
  if(app.trace) SDL_Log("Phase 3: Prepare ShadowMap");
  if(shadowsThisFrame) {
    app.timed!updateLightGeometries(dt);
    app.timed!recordShadowCommandBuffer(app.syncIndex);
  }else{ shadowsThisFrame = false; }

  // --- Phase 4: Prepare & Submit Graphics & ImGui Work ---
  if(app.trace) SDL_Log("Phase 4: Recording Scene, Post-processing, and ImGui");
  app.timed!recordSceneCommandBuffer(app.shaders, app.syncIndex);
  app.timed!recordPostCommandBuffer(app.syncIndex);
  app.timed!recordImGuiCommandBuffer(app.syncIndex);

  if(app.trace) SDL_Log("Phase 5: Submit CommandBuffers");
  VkCommandBuffer[] submitCommandBuffers = [];
  if (shadowsThisFrame){ submitCommandBuffers ~= app.shadows.renderPass.commands[app.syncIndex]; }
  submitCommandBuffers ~= [
    app.scenePass.commands[app.syncIndex],
    app.postPass.commands[app.syncIndex],
    app.imguiPass.commands[app.syncIndex]
  ];

  VkSemaphore[] waitSemaphores = [ imageAcquired ];
  VkPipelineStageFlags[] waitStages = [ VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT ];

  if (app.hasCompute) {
    waitSemaphores ~= computeComplete;
    waitStages ~= VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
  }

  VkSubmitInfo submitInfo = {
    sType : VK_STRUCTURE_TYPE_SUBMIT_INFO,
    waitSemaphoreCount : cast(uint)waitSemaphores.length,
    pWaitSemaphores : &waitSemaphores[0],
    pWaitDstStageMask : &waitStages[0],

    commandBufferCount : cast(uint)submitCommandBuffers.length,
    pCommandBuffers : &submitCommandBuffers[0],
    signalSemaphoreCount : 1,
    pSignalSemaphores : &renderComplete
  };

  //SDL_Log("vkQueueSubmit: frame=%d sync=%d frameIndex=%d", app.totalFramesRendered, app.syncIndex, app.frameIndex);
  enforceVK(vkQueueSubmit(app.queue, 1, &submitInfo, app.fences[app.syncIndex].renderInFlight));
  if(app.trace) SDL_Log("Done renderFrame: %d", app.syncIndex);
  app.totalFramesRendered++;
}

void presentFrame(ref App app) {
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
  if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) app.rebuild = true;
  if (err == VK_ERROR_OUT_OF_DATE_KHR) return;
  if (err != VK_SUBOPTIMAL_KHR) enforceVK(err);
  app.syncIndex = (app.syncIndex + 1) % app.sync.length; // Now we can use the next set of semaphores
  if(app.trace) SDL_Log("Done presentFrame");
}

