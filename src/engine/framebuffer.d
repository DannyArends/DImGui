/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Create a framebuffer for each SwapChain ImageView with Color and Depth attachement
 */
void createFramebuffers(ref App app) {
  if(app.verbose) SDL_Log("createFramebuffers");
  app.swapChainFramebuffers.length = app.imageCount;

  for (size_t i = 0; i < app.imageCount; i++) {
    VkImageView[] attachments = [app. colorBuffer.colorImageView, app.depthBuffer.depthImageView, app.swapChainImageViews[i]];

    VkFramebufferCreateInfo framebufferInfo = {
      sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
      renderPass: app.renderpass,
      attachmentCount: cast(uint)attachments.length,
      pAttachments: &attachments[0],
      width: app.camera.width,
      height: app.camera.height,
      layers: 1
    };

    enforceVK(vkCreateFramebuffer(app.device, &framebufferInfo, null, &app.swapChainFramebuffers[i]));
  }
  if(app.verbose) SDL_Log("%d Framebuffers created", app.swapChainFramebuffers.length);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.imageCount; i++) {
      vkDestroyFramebuffer(app.device, app.swapChainFramebuffers[i], app.allocator);
    }
  });
}

