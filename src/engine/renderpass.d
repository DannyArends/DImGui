/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import depthbuffer : findDepthFormat;
import devices : getMSAASamples;

/** Create a RenderPass object using a specified initial Layout and loadOp
 */
VkRenderPass createSceneRenderPass(ref App app) {
  if(app.verbose) SDL_Log("Creating RenderPass");

  VkAttachmentDescription colorAttachment = {
    format : app.colorFormat,
    samples : app.getMSAASamples(),
    loadOp : VK_ATTACHMENT_LOAD_OP_CLEAR,
    storeOp : VK_ATTACHMENT_STORE_OP_STORE,
    initialLayout : VK_IMAGE_LAYOUT_UNDEFINED,
    finalLayout : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
  };

  VkAttachmentDescription colorAttachmentResolve = {
    format : app.colorFormat,
    samples : VK_SAMPLE_COUNT_1_BIT,
    loadOp : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    storeOp : VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp : VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout : VK_IMAGE_LAYOUT_UNDEFINED,
    finalLayout :VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
  };

  VkAttachmentDescription depthAttachment = {
    format: app.findDepthFormat(),
    samples: app.getMSAASamples(),
    loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
    storeOp: VK_ATTACHMENT_STORE_OP_STORE,
    initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
    finalLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
  };

  VkAttachmentReference colorAttachmentRef = { attachment : 0, layout : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
  VkAttachmentReference colorAttachmentResolveRef = { attachment : 1, layout : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
  VkAttachmentReference depthAttachmentRef = { attachment: 2, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL };

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

  VkAttachmentDescription[] attachments = [colorAttachment, colorAttachmentResolve, depthAttachment];

  VkRenderPassCreateInfo createInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    attachmentCount : cast(uint)(attachments.length),
    pAttachments : &attachments[0],
    subpassCount : 1,
    pSubpasses : &subpassDescription,
    dependencyCount : 1,
    pDependencies : &subpassDependency,
  };

  VkRenderPass renderpass;
  enforceVK(vkCreateRenderPass(app.device, &createInfo, null, &renderpass));
  if(app.verbose) SDL_Log("RenderPass created");
  app.frameDeletionQueue.add((){ vkDestroyRenderPass(app.device, renderpass, app.allocator); });
  return(renderpass);
}

/** Create the Post-Processing RenderPass (samples HDR texture, renders to swapchain)
 */
VkRenderPass createPostProcessRenderPass(ref App app) {
  if(app.verbose) SDL_Log("Creating Post-Process RenderPass");

  // This attachment is the swapchain image itself (LDR)
  VkAttachmentDescription colorAttachment = {
    format : app.surfaceformats[app.format].format, // Use swapchain format
    samples : VK_SAMPLE_COUNT_1_BIT,                // No MSAA for the final output
    loadOp : VK_ATTACHMENT_LOAD_OP_DONT_CARE,       // We will fully overwrite this
    storeOp : VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp : VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout : VK_IMAGE_LAYOUT_UNDEFINED,      // Will be transitioned by acquireNextImageKHR
    finalLayout : VK_IMAGE_LAYOUT_PRESENT_SRC_KHR   // Ready for presentation
  };

  VkAttachmentReference colorAttachmentRef = { attachment : 0, layout : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
    
  VkSubpassDescription subpassDescription = {
    pipelineBindPoint : VK_PIPELINE_BIND_POINT_GRAPHICS,
    colorAttachmentCount : 1,
    pColorAttachments : &colorAttachmentRef,
  };

  // Dependencies for this pass
  VkSubpassDependency[2] dependencies = [
    {// Dependency 0: External -> Subpass 0. Ensures swapchain image is ready for write after acquire.
      srcSubpass : VK_SUBPASS_EXTERNAL,
      dstSubpass : 0,
      srcStageMask : VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
      dstStageMask : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      srcAccessMask : VK_ACCESS_NONE,
      dstAccessMask : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      dependencyFlags : 0 
    },
    {// Dependency 1: Subpass 0 -> External. Ensures rendering is complete before presentation.
    srcSubpass : 0,
    dstSubpass : VK_SUBPASS_EXTERNAL,
    srcStageMask : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, // This pass finished writing
    dstStageMask : VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,         // For presentation (or VK_PIPELINE_STAGE_HOST_BIT)
    srcAccessMask : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    dstAccessMask : VK_ACCESS_MEMORY_READ_BIT, // Presentation engine will read
    dependencyFlags : 0
  }];

  VkAttachmentDescription[] attachments = [colorAttachment];

  VkRenderPassCreateInfo createInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    attachmentCount : cast(uint)(attachments.length),
    pAttachments : &attachments[0],
    subpassCount : 1,
    pSubpasses : &subpassDescription,
    dependencyCount : cast(uint)(dependencies.length),
    pDependencies : &dependencies[0],
  };

  VkRenderPass renderpass;
  enforceVK(vkCreateRenderPass(app.device, &createInfo, null, &renderpass));
  if(app.verbose) SDL_Log("Post-Process RenderPass created");
  app.frameDeletionQueue.add((){ vkDestroyRenderPass(app.device, renderpass, app.allocator); });
  return(renderpass);
}

/** Create the ImGui RenderPass
 * This pass typically loads the contents of the swapchain image and overlays ImGui.
 */
VkRenderPass createImGuiRenderPass(ref App app) {
  if(app.verbose) SDL_Log("Creating ImGui RenderPass");

  VkAttachmentDescription colorAttachment = {
    format : app.surfaceformats[app.format].format,     // Swapchain format
    samples : VK_SAMPLE_COUNT_1_BIT,
    loadOp : VK_ATTACHMENT_LOAD_OP_LOAD,                // Load existing content (from post-process pass)
    storeOp : VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp : VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout : VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    finalLayout : VK_IMAGE_LAYOUT_PRESENT_SRC_KHR       // Final layout for presentation
  };

  VkAttachmentReference colorAttachmentRef = { attachment : 0, layout : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
    
  VkSubpassDescription subpassDescription = {
    pipelineBindPoint : VK_PIPELINE_BIND_POINT_GRAPHICS,
    colorAttachmentCount : 1,
    pColorAttachments : &colorAttachmentRef
  };

  // Dependency from the Post-Process Pass to ImGui Pass
  VkSubpassDependency dependency = {
    srcSubpass : VK_SUBPASS_EXTERNAL,
    dstSubpass : 0,
    srcStageMask : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    dstStageMask : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    srcAccessMask : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, // Post-process wrote to it
    dstAccessMask : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, // ImGui will write to it
    dependencyFlags : 0
  };

  VkAttachmentDescription[] attachments = [colorAttachment];

  VkRenderPassCreateInfo createInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    attachmentCount : cast(uint)(attachments.length),
    pAttachments : &attachments[0],
    subpassCount : 1,
    pSubpasses : &subpassDescription,
    dependencyCount : 1,
    pDependencies : &dependency,
  };

  VkRenderPass renderpass;
  enforceVK(vkCreateRenderPass(app.device, &createInfo, null, &renderpass));
  if(app.verbose) SDL_Log("ImGui RenderPass created");
  app.frameDeletionQueue.add((){ vkDestroyRenderPass(app.device, renderpass, app.allocator); });
  return(renderpass);
}
