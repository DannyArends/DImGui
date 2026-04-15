/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import images : createImage, nameImageBuffer, deAllocate, ImageBuffer;
import swapchain : createImageView;
import validation : nameVulkanObject;

/** Function to create an HDR color image and its view (MSAA if enabled)
 */
void createHDRImage(ref App app, ref ImageBuffer buffer, VkSampleCountFlagBits flag, VkMemoryPropertyFlags properties) {
  if(app.verbose) SDL_Log("Creating Offscreen HDR Image");

  app.createImage(app.camera.width, app.camera.height, &buffer.image, &buffer.memory, app.colorFormat, flag, VK_IMAGE_TILING_OPTIMAL, properties);
  buffer.view = app.createImageView(buffer.image, app.colorFormat, VK_IMAGE_ASPECT_COLOR_BIT);
  app.nameImageBuffer(buffer, "Offscreen HDR Image");

  app.swapDeletionQueue.add((){ app.deAllocate(buffer); });
}

void create(ref App app, ref RenderPass pass, VkImageView[][] attachmentSets, uint width, uint height, string label, ref DeletionQueue queue) {
  pass.framebuffers.length = attachmentSets.length;
  foreach(i, views; attachmentSets) {
    VkFramebufferCreateInfo info = {
      sType:           VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
      renderPass:      pass,
      attachmentCount: cast(uint)views.length,
      pAttachments:    views.ptr,
      width:           width,
      height:          height,
      layers:          1
    };
    enforceVK(vkCreateFramebuffer(app.device, &info, app.allocator, &pass.framebuffers[i]));
    app.nameVulkanObject(pass.framebuffers[i], toStringz(format("[FRAMEBUFFER] %s #%d", label, i)), VK_OBJECT_TYPE_FRAMEBUFFER);
  }
  queue.add((){ foreach(fb; pass.framebuffers) vkDestroyFramebuffer(app.device, fb, app.allocator); });
}

/** Create framebuffers for Rendering, Post-processing, and ImGui, for each SwapChain ImageView 
 * with appropriate Color and Depth attachements
 */
void createFramebuffers(ref App app) {
  auto sceneViews  = iota(app.imageCount).map!(i => [app.offscreenHDR.view, app.resolvedHDR.view, app.depthBuffer.view]).array;
  auto postViews   = iota(app.imageCount).map!(i => [app.swapChainImageViews[i]]).array;
  auto imguiViews  = iota(app.imageCount).map!(i => [app.swapChainImageViews[i]]).array;
  auto shadowViews = iota(app.lights.length).map!(i => [app.shadows.images[i].view]).array;

  app.create(app.scenePass, sceneViews, app.camera.width, app.camera.height, "Render", app.swapDeletionQueue);
  app.create(app.postPass, postViews, app.camera.width, app.camera.height, "Post-process", app.swapDeletionQueue);
  app.create(app.imguiPass, imguiViews, app.camera.width, app.camera.height, "ImGui", app.swapDeletionQueue);
  app.create(app.shadows.renderPass, shadowViews, app.shadows.dimension, app.shadows.dimension, "Shadow", app.mainDeletionQueue);
}

