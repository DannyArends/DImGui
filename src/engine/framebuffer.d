/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import images : createImage, nameImageBuffer, deAllocate, ImageBuffer;
import swapchain : createImageView;
import validation : nameVulkanObject;

struct FrameBuffer {
  VkFramebuffer[] scene;
  VkFramebuffer[] shadow;
  VkFramebuffer[] postprocess;
  VkFramebuffer[] imgui;
}

/** Function to create an HDR color image and its view (MSAA if enabled)
 */
void createHDRImage(ref App app, ref ImageBuffer buffer, VkSampleCountFlagBits flag, VkMemoryPropertyFlags properties) {
  if(app.verbose) SDL_Log("Creating Offscreen HDR Image");

  app.createImage(app.camera.width, app.camera.height, &buffer.image, &buffer.memory, app.colorFormat, flag, VK_IMAGE_TILING_OPTIMAL, properties);
  buffer.view = app.createImageView(buffer.image, app.colorFormat, VK_IMAGE_ASPECT_COLOR_BIT);
  app.nameImageBuffer(buffer, "Offscreen HDR Image");

  app.swapDeletionQueue.add((){ app.deAllocate(buffer); });
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
    app.nameVulkanObject(app.framebuffers.scene[i], toStringz(format("[FRAMEBUFFER] Render #%d", i)), VK_OBJECT_TYPE_FRAMEBUFFER);

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
    app.nameVulkanObject(app.framebuffers.postprocess[i], toStringz(format("[FRAMEBUFFER] Post-processing #%d", i)), VK_OBJECT_TYPE_FRAMEBUFFER);

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
    app.nameVulkanObject(app.framebuffers.imgui[i], toStringz(format("[FRAMEBUFFER] ImGui #%d", i)), VK_OBJECT_TYPE_FRAMEBUFFER);
  }

  if(app.verbose) SDL_Log("Shadow map framebuffer creation for %d lights", app.lights.length);
  app.framebuffers.shadow.length = app.lights.length;

  for(size_t l = 0; l < app.lights.length; l++) {
    VkImageView[] attachments = [ app.shadows.images[l].view ];

    VkFramebufferCreateInfo framebufferInfo = {
      sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
      renderPass: app.shadows.renderPass,
      attachmentCount: cast(uint)attachments.length,
      pAttachments: &attachments[0],
      width: app.shadows.dimension,
      height: app.shadows.dimension,
      layers: 1
    };
    enforceVK(vkCreateFramebuffer(app.device, &framebufferInfo, app.allocator, &app.framebuffers.shadow[l]));
    app.nameVulkanObject(app.framebuffers.shadow[l], toStringz(format("[FRAMEBUFFER] Shadow #%d", l)), VK_OBJECT_TYPE_FRAMEBUFFER);

    if(app.verbose) SDL_Log("Shadow map framebuffer created.");
  }

  if(app.verbose) {
    SDL_Log("%d Scene Framebuffers created", app.framebuffers.scene.length);
    SDL_Log("%d Shadow Framebuffers created", app.framebuffers.shadow.length);
    SDL_Log("%d Post-Process Framebuffers created", app.framebuffers.postprocess.length);
    SDL_Log("%d ImGui Framebuffers created", app.framebuffers.imgui.length);
  }

  app.swapDeletionQueue.add((){
    for (uint i = 0; i < app.imageCount; i++) {
      vkDestroyFramebuffer(app.device, app.framebuffers.scene[i], app.allocator);
      vkDestroyFramebuffer(app.device, app.framebuffers.postprocess[i], app.allocator);
      vkDestroyFramebuffer(app.device, app.framebuffers.imgui[i], app.allocator);
    }
    for(size_t l = 0; l < app.lights.length; l++) {
      vkDestroyFramebuffer(app.device, app.framebuffers.shadow[l], app.allocator); 
    }
  });
}

