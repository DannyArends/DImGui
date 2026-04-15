/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import depthbuffer : findDepthFormat;
import devices : getMSAASamples;
import validation : nameVulkanObject;

struct RenderPassInfo {
  VkAttachmentDescription[] attachments;
  VkSubpassDescription[] subpasses;
  VkSubpassDependency[] dependencies;
}

struct RenderPass {
  VkRenderPass pass;
  alias pass this;
  VkFramebuffer[] framebuffers;
  VkCommandBuffer[] commands;

  void create(ref App app, RenderPassInfo info, string label, ref DeletionQueue queue) {
    VkRenderPassCreateInfo createInfo = {
      sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
      attachmentCount: cast(uint)info.attachments.length, pAttachments: info.attachments.ptr,
      subpassCount: cast(uint)info.subpasses.length,      pSubpasses: info.subpasses.ptr,
      dependencyCount: cast(uint)info.dependencies.length, pDependencies: info.dependencies.ptr,
    };
    enforceVK(vkCreateRenderPass(app.device, &createInfo, app.allocator, &pass));
    app.nameVulkanObject(pass, toStringz("[RENDERPASS] " ~ label), VK_OBJECT_TYPE_RENDER_PASS);
    if(app.verbose) SDL_Log(toStringz(label ~ " RenderPass created"));
    queue.add((){ vkDestroyRenderPass(app.device, pass, app.allocator); });
  }

  void begin(VkCommandBuffer cmd, uint frameIdx, VkExtent2D extent, VkClearValue[] clears) {
    VkRenderPassBeginInfo info = {
      sType:           VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      renderPass:      pass,
      framebuffer:     framebuffers[frameIdx],
      renderArea:      { extent: extent },
      clearValueCount: cast(uint)clears.length,
      pClearValues:    &clears[0]
    };
    vkCmdBeginRenderPass(cmd, &info, VK_SUBPASS_CONTENTS_INLINE);
  }

  void end(VkCommandBuffer cmd) { vkCmdEndRenderPass(cmd); }
}

/** Create a Scene RenderPass object
 * This VkRenderPass setups an image with a: Color, Depth and MSAA ColorResolve attachment
 */
void createSceneRenderPass(ref App app) {
  VkAttachmentReference colorRef   = { attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
  VkAttachmentReference resolveRef = { attachment: 1, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
  VkAttachmentReference depthRef   = { attachment: 2, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL };

  RenderPassInfo info = {
    attachments: [
      { format: app.colorFormat,       samples: app.getMSAASamples(),  loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
        storeOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
        finalLayout:   VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL },
      { format: app.colorFormat,       samples: VK_SAMPLE_COUNT_1_BIT, loadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        storeOp: VK_ATTACHMENT_STORE_OP_STORE,
        stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE, stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
        finalLayout:   VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
      { format: app.findDepthFormat(), samples: app.getMSAASamples(),  loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
        storeOp: VK_ATTACHMENT_STORE_OP_STORE,
        initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
        finalLayout:   VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL },
    ],
    subpasses: [{
      pipelineBindPoint:       VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount:    1,
      pColorAttachments:       &colorRef,
      pDepthStencilAttachment: &depthRef,
      pResolveAttachments:     &resolveRef
    }],
    dependencies: [{
      srcSubpass:   VK_SUBPASS_EXTERNAL,
      srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
    }],
  };
  app.scenePass.create(app, info, "Scene", app.swapDeletionQueue);
}

/** Create the Post-Processing RenderPass 
 * This VkRenderPass samples the HDR texture, renders and to the SwapChain image
 */
void createPostProcessRenderPass(ref App app) {
  VkAttachmentReference colorRef = { attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };

  RenderPassInfo info = {
    attachments: [{
      format:        app.surfaceformats[app.format].format,
      samples:       VK_SAMPLE_COUNT_1_BIT,
      loadOp:        VK_ATTACHMENT_LOAD_OP_DONT_CARE,
      storeOp:       VK_ATTACHMENT_STORE_OP_STORE,
      stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE, stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
      initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
      finalLayout:   VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    }],
    subpasses: [{
      pipelineBindPoint:    VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount: 1,
      pColorAttachments:    &colorRef,
    }],
    dependencies: [
      { srcSubpass: VK_SUBPASS_EXTERNAL, dstSubpass: 0,
        srcStageMask: VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        srcAccessMask: VK_ACCESS_NONE, dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT },
      { srcSubpass: 0, dstSubpass: VK_SUBPASS_EXTERNAL,
        srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        dstStageMask: VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        srcAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        dstAccessMask: VK_ACCESS_MEMORY_READ_BIT },
    ],
  };
  app.postPass.create(app, info, "Post-process", app.swapDeletionQueue);
}

/** Create the ImGui RenderPass
 * This VkRenderPass loads the contents of the swapchain image and overlays ImGui.
 */
void createImGuiRenderPass(ref App app) {
  VkAttachmentReference colorRef = { attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };

  RenderPassInfo info = {
    attachments: [{
      format:        app.surfaceformats[app.format].format,
      samples:       VK_SAMPLE_COUNT_1_BIT,
      loadOp:        VK_ATTACHMENT_LOAD_OP_LOAD,
      storeOp:       VK_ATTACHMENT_STORE_OP_STORE,
      stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE, stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
      initialLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
      finalLayout:   VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    }],
    subpasses: [{
      pipelineBindPoint:    VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount: 1,
      pColorAttachments:    &colorRef,
    }],
    dependencies: [{
      srcSubpass:    VK_SUBPASS_EXTERNAL,     dstSubpass:    0,
      srcStageMask:  VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      dstStageMask:  VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      srcAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
    }],
  };
  app.imguiPass.create(app, info, "ImGui", app.swapDeletionQueue);
}

