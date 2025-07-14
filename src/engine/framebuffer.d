/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import images : createImage, ImageBuffer;
import swapchain : createImageView;

struct FrameBuffer {
  VkFramebuffer[] scene;
  VkFramebuffer[] postprocess;
  VkFramebuffer[] imgui;
}

/** Function to create an HDR color image and its view (MSAA if enabled)
 */
void createHDRImage(ref App app, ref ImageBuffer buffer, VkSampleCountFlagBits flag, VkMemoryPropertyFlags properties) {
  if(app.verbose) SDL_Log("Creating Offscreen HDR Image");

  app.createImage(app.camera.width, app.camera.height, &buffer.image, &buffer.memory, app.colorFormat, flag, VK_IMAGE_TILING_OPTIMAL, properties);
  buffer.view = app.createImageView(buffer.image, app.colorFormat, VK_IMAGE_ASPECT_COLOR_BIT);

  app.frameDeletionQueue.add((){
    vkFreeMemory(app.device, buffer.memory, app.allocator);
    vkDestroyImageView(app.device, buffer.view, app.allocator);
    vkDestroyImage(app.device, buffer.image, app.allocator);
  });
}

/** Create framebuffers for Rendering, Post-processing, and ImGui, for each SwapChain ImageView 
 * with appropriate Color and Depth attachements
 */
void createFramebuffers(ref App app) {
  if(app.verbose) SDL_Log("createFramebuffers for %d images", app.imageCount);

  // Allocate arrays for all framebuffer types
  app.framebuffers.scene.length = app.imageCount;
  app.framebuffers.postprocess.length = app.imageCount;
  app.framebuffers.imgui.length = app.imageCount;

  for (size_t i = 0; i < app.imageCount; i++) {
    // 1. Framebuffers for the MAIN SCENE RENDER PASS (renders to offscreen HDR)
    if(app.verbose) SDL_Log("Framebuffer - MAIN SCENE RENDER");
    VkImageView[] sceneAttachments = [
        app.offscreenHDR.view,    // 0: MSAA HDR Color buffer
        app.resolvedHDR.view,     // 1: Resolved single-sample HDR Color buffer
        app.depthBuffer.view      // 2: Depth buffer
    ];

    VkFramebufferCreateInfo sceneFramebufferInfo  = {
      sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
      renderPass: app.scene,
      attachmentCount: cast(uint)sceneAttachments.length,
      pAttachments: &sceneAttachments[0],
      width: app.camera.width,
      height: app.camera.height,
      layers: 1
    };
    enforceVK(vkCreateFramebuffer(app.device, &sceneFramebufferInfo, null, &app.framebuffers.scene[i]));

    // 2. Framebuffers for the POST-PROCESSING RENDER PASS (renders to swapchain, samples resolved HDR)
    if(app.verbose) SDL_Log("Framebuffer - POST-PROCESSING RENDER");
    VkImageView[] postProcessAttachments = [app.swapChainImageViews[i]]; // Only the swapchain image view

    VkFramebufferCreateInfo postProcessFramebufferInfo = {
      sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
      renderPass: app.postprocess, // Use the post-processing render pass
      attachmentCount: cast(uint)postProcessAttachments.length,
      pAttachments: &postProcessAttachments[0],
      width: app.camera.width,
      height: app.camera.height,
      layers: 1
    };
    enforceVK(vkCreateFramebuffer(app.device, &postProcessFramebufferInfo, null, &app.framebuffers.postprocess[i]));

    // 3. Framebuffers for the IMGUI RENDER PASS (renders to swapchain, overlays ImGui)
    if(app.verbose) SDL_Log("Framebuffer - IMGUI RENDER");
    VkImageView[] imguiAttachments = [app.swapChainImageViews[i]]; // Only the swapchain image view

    VkFramebufferCreateInfo imguiFramebufferInfo = {
      sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
      renderPass: app.imgui, // Use the ImGui render pass
      attachmentCount: cast(uint)imguiAttachments.length,
      pAttachments: &imguiAttachments[0],
      width: app.camera.width,
      height: app.camera.height,
      layers: 1
    };
    enforceVK(vkCreateFramebuffer(app.device, &imguiFramebufferInfo, null, &app.framebuffers.imgui[i]));
  }

  if(app.verbose) {
    SDL_Log("%d Scene Framebuffers created", app.framebuffers.scene.length);
    SDL_Log("%d Post-Process Framebuffers created", app.framebuffers.postprocess.length);
    SDL_Log("%d ImGui Framebuffers created", app.framebuffers.imgui.length);
  }

  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.imageCount; i++) {
      vkDestroyFramebuffer(app.device, app.framebuffers.scene[i], app.allocator);
      vkDestroyFramebuffer(app.device, app.framebuffers.postprocess[i], app.allocator);
      vkDestroyFramebuffer(app.device, app.framebuffers.imgui[i], app.allocator);
    }
  });
}

