// Copyright Danny Arends 2025
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

import engine;

void createFramebuffers(ref App app) {
  app.swapChainFramebuffers.length = app.imageCount;

  for (size_t i = 0; i < app.imageCount; i++) {
    VkImageView[] attachments = [app.swapChainImageViews[i], app.depthBuffer.depthImageView];

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
}

