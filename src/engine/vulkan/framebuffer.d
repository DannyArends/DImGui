/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import images : createImage, nameImageBuffer, cleanup, ImageBuffer;
import views : createImageView;
import validation : nameVulkanObject;

@nogc void cleanup(ref App app, VkFramebuffer fb) nothrow { vkDestroyFramebuffer(app.device, fb, app.allocator); }

/** Function to create an HDR color image and its view (MSAA if enabled) */
void createHDRImage(ref App app, ref ImageBuffer buffer, VkSampleCountFlagBits flag, VkMemoryPropertyFlags properties) {
  if(app.verbose) SDL_Log("Creating Offscreen HDR Image");

  app.createImage(buffer, app.camera.width, app.camera.height, app.offscreen.format, flag, VK_IMAGE_TILING_OPTIMAL, properties);
  buffer.view = app.createImageView(buffer.image, app.offscreen.format, VK_IMAGE_ASPECT_COLOR_BIT);
  app.nameImageBuffer(buffer, "Offscreen HDR Image");

  app.swapDeletionQueue.add((){ app.cleanup(buffer); });
}

VkFramebuffer createFramebuffer(ref App app, ref RenderPass pass, VkImageView[] views, uint width, uint height, string label, size_t idx = 0) {
  VkFramebufferCreateInfo info = {
    sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
    renderPass: pass,
    attachmentCount: cast(uint)views.length,
    pAttachments: views.ptr,
    width: width, height: height, layers: 1
  };
  VkFramebuffer fb;
  enforceVK(vkCreateFramebuffer(app.device, &info, app.allocator, &fb));
  app.nameVulkanObject(fb, toStringz(format("[FRAMEBUFFER] %s #%d", label, idx)), VK_OBJECT_TYPE_FRAMEBUFFER);
  return fb;
}

void create(ref App app, ref RenderPass pass, VkImageView[][] attachmentSets, uint width, uint height, string label, ref DeletionQueue queue) {
  pass.framebuffers.length = attachmentSets.length;
  foreach(i, views; attachmentSets) { pass.framebuffers[i] = app.createFramebuffer(pass, views, width, height, label, i); }
  queue.add((){ foreach(fb; pass.framebuffers){ vkDestroyFramebuffer(app.device, fb, app.allocator); } });
}

/** Create framebuffers for Rendering, Post-processing, and ImGui, for each SwapChain ImageView 
 * with appropriate Color and Depth attachements */
void createFramebuffers(ref App app) {
  auto sceneViews  = iota(app.imageCount).map!(i => [app.offscreenHDR.view, app.resolvedHDR.view, app.depthBuffer.view]).array;
  auto postViews   = iota(app.imageCount).map!(i => [app.swapChainImageViews[i]]).array;
  auto imguiViews  = iota(app.imageCount).map!(i => [app.swapChainImageViews[i]]).array;

  app.create(app.scenePass, sceneViews, app.camera.width, app.camera.height, "Render", app.swapDeletionQueue);
  app.create(app.postPass, postViews, app.camera.width, app.camera.height, "Post-process", app.swapDeletionQueue);
  app.create(app.imguiPass, imguiViews, app.camera.width, app.camera.height, "ImGui", app.swapDeletionQueue);
}

