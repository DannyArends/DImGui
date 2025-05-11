/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import depthbuffer : findDepthFormat;
import devices : getSampleCount;

VkRenderPass createRenderPass(ref App app, VkImageLayout initialLayout = VK_IMAGE_LAYOUT_UNDEFINED, 
                                           VkAttachmentLoadOp loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR) {
  if(app.verbose) SDL_Log("Creating renderpass");

  VkAttachmentDescription colorAttachment = {
    format : app.surfaceformats[0].format,
    samples : app.getSampleCount(),
    loadOp : loadOp,
    storeOp : VK_ATTACHMENT_STORE_OP_STORE,
    initialLayout : initialLayout,
    finalLayout : VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
  };

  VkAttachmentDescription colorAttachmentResolve = {
    format : app.surfaceformats[0].format,
    samples : VK_SAMPLE_COUNT_1_BIT,
    loadOp : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    storeOp : VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp : VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout : VK_IMAGE_LAYOUT_UNDEFINED,
    finalLayout :VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
  };

  VkAttachmentReference colorAttachmentRef = {
    attachment : 0,
    layout : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
  };

  VkAttachmentReference colorAttachmentResolveRef = {
    attachment : 2,
    layout : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
  };

  VkAttachmentDescription depthAttachment = {
    format: app.findDepthFormat(),
    samples: app.getSampleCount(),
    loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
    storeOp: VK_ATTACHMENT_STORE_OP_STORE,
    initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
    finalLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
  };

  VkAttachmentReference depthAttachmentRef = { attachment: 1, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL };

  VkSubpassDescription subpassDescription = {
    pipelineBindPoint : VK_PIPELINE_BIND_POINT_GRAPHICS,
    colorAttachmentCount : 1,
    pColorAttachments : &colorAttachmentRef,
    pDepthStencilAttachment: &depthAttachmentRef,
    pResolveAttachments: &colorAttachmentResolveRef
  };

  VkSubpassDependency subpassDependency = {
    srcSubpass : VK_SUBPASS_EXTERNAL,
    dstSubpass : 0,
    srcStageMask : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    dstStageMask : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    srcAccessMask : 0,
    dstAccessMask : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
  };

  VkAttachmentDescription[3] attachments = [colorAttachment, depthAttachment, colorAttachmentResolve];

  VkRenderPassCreateInfo createInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    attachmentCount : attachments.length,
    pAttachments : &attachments[0],
    subpassCount : 1,
    pSubpasses : &subpassDescription,
    dependencyCount : 1,
    pDependencies : &subpassDependency,
  };
  VkRenderPass renderpass;
  enforceVK(vkCreateRenderPass(app.device, &createInfo, null, &renderpass));
  app.frameDeletionQueue.add((){ vkDestroyRenderPass(app.device, renderpass, app.allocator); });

  return(renderpass);
}
