/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import devices : getMSAASamples;
import images : createImage;
import swapchain : createImageView;

struct FrameBuffer {
  VkFramebuffer[] scene;
  VkFramebuffer[] postprocess;
  VkFramebuffer[] imgui;
}

/** Function to create an offscreen HDR color image and its view (MSAA if enabled)
 */
void createOffscreenHDRImage(ref App app) {
  if(app.verbose) SDL_Log("Creating Offscreen HDR Image");

  app.createImage(app.camera.width, app.camera.height, &app.offscreenHDR.colorImage, &app.offscreenHDR.colorImageMemory,
                  app.colorFormat, app.getMSAASamples(), VK_IMAGE_TILING_OPTIMAL,
                  VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT);
  app.offscreenHDR.colorImageView = app.createImageView(app.offscreenHDR.colorImage, app.colorFormat, 1);
  app.frameDeletionQueue.add((){ 
    vkFreeMemory(app.device, app.offscreenHDR.colorImageMemory, app.allocator);
    vkDestroyImageView(app.device, app.offscreenHDR.colorImageView, app.allocator);
    vkDestroyImage(app.device, app.offscreenHDR.colorImage, app.allocator);
  });
}

/** Function to create the resolved HDR image (non-MSAA, will be sampled by post-process)
 */
void createResolvedHDRImage(ref App app) {
  if(app.verbose) SDL_Log("Creating Resolved HDR Image");
  
  app.createImage(app.camera.width, app.camera.height, &app.resolvedHDR.colorImage, &app.resolvedHDR.colorImageMemory,
                  app.colorFormat, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL,
                  VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT);
  app.resolvedHDR.colorImageView = app.createImageView(app.resolvedHDR.colorImage, app.colorFormat, 1);
  app.frameDeletionQueue.add((){ 
    vkFreeMemory(app.device, app.resolvedHDR.colorImageMemory, app.allocator);
    vkDestroyImageView(app.device, app.resolvedHDR.colorImageView, app.allocator);
    vkDestroyImage(app.device, app.resolvedHDR.colorImage, app.allocator);
  });
}

/** Create a framebuffer for each SwapChain ImageView with Color and Depth attachement
 */
void createFramebuffers(ref App app) {
  if(app.verbose) SDL_Log("createFramebuffers");

  // Allocate arrays for all framebuffer types
  app.framebuffers.scene.length = app.imageCount;
  app.framebuffers.postprocess.length = app.imageCount;
  app.framebuffers.imgui.length = app.imageCount;

  for (size_t i = 0; i < app.imageCount; i++) {
    // 1. Framebuffers for the MAIN SCENE RENDER PASS (renders to offscreen HDR)
    SDL_Log("MAIN SCENE RENDER");
    VkImageView[] sceneAttachments = [
        app.offscreenHDR.colorImageView,    // 0: MSAA HDR Color buffer
        app.resolvedHDR.colorImageView,     // 1: Resolved single-sample HDR Color buffer
        app.depthBuffer.depthImageView      // 2: Depth buffer
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
    SDL_Log("POST-PROCESSING RENDER");
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
    SDL_Log("IMGUI RENDER");
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

  if(app.verbose) SDL_Log("%d Scene Framebuffers created", app.framebuffers.scene.length);
  if(app.verbose) SDL_Log("%d Post-Process Framebuffers created", app.framebuffers.postprocess.length);
  if(app.verbose) SDL_Log("%d ImGui Framebuffers created", app.framebuffers.imgui.length);

  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.imageCount; i++) {
      vkDestroyFramebuffer(app.device, app.framebuffers.scene[i], app.allocator);
      vkDestroyFramebuffer(app.device, app.framebuffers.postprocess[i], app.allocator);
      vkDestroyFramebuffer(app.device, app.framebuffers.imgui[i], app.allocator);
    }
  });
}

