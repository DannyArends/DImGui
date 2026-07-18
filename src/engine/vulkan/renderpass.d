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
 * This VkRenderPass setups an image with a: Color, Depth and MSAA ColorResolve attachment */
void createSceneRenderPass(ref App app) {
  // Subpass 0 (opaque): MSAA color(0) + VK_ATTACHMENT_UNUSED
  VkAttachmentReference[2] colorRefs = [
    { attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL },
    { attachment: VK_ATTACHMENT_UNUSED, layout: VK_IMAGE_LAYOUT_UNDEFINED },
  ];
  VkAttachmentReference[2] resolveRefs = [ // MSAA: Resolve + VK_ATTACHMENT_UNUSED
    { attachment: 1, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL },
    { attachment: VK_ATTACHMENT_UNUSED, layout: VK_IMAGE_LAYOUT_UNDEFINED },
  ]; // Depth Attachement
  VkAttachmentReference depthRef = { attachment: 2, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL };

  // Subpass 1 (transparent WBOIT accumulation): write accum(3) + revealage(4), test depth
  VkAttachmentReference[2] oitColorRefs = [
    { attachment: 3, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL },
    { attachment: 4, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL },
  ];

  // Subpass 2 (resolve): read accum(3) + revealage(4) as input, composite into resolved(1)
  VkAttachmentReference[2] oitInputRefs = [
    { attachment: 3, layout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
    { attachment: 4, layout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
  ];
  VkAttachmentReference resolveColorRef = { attachment: 1, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };

  RenderPassInfo info = {
    attachments: [
      // 0: MSAA: Offscreen buffer
      { format: app.offscreen.format, samples: app.getMSAASamples(), loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
        storeOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout: VK_IMAGE_LAYOUT_UNDEFINED, finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL },
      // 1: MSAA: Resolve
      { format: app.offscreen.format, samples: VK_SAMPLE_COUNT_1_BIT, loadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        storeOp: VK_ATTACHMENT_STORE_OP_STORE,
        stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE, stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout: VK_IMAGE_LAYOUT_UNDEFINED, finalLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
      // 2: Depth attachement
      { format: app.findDepthFormat(), samples: app.getMSAASamples(), loadOp: VK_ATTACHMENT_LOAD_OP_LOAD,
        storeOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
        finalLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL },
      // 3: WBOIT: accumulation
      { format: app.wboit.accumulationFormat, samples: app.getMSAASamples(), loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
        storeOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE, stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout: VK_IMAGE_LAYOUT_UNDEFINED, finalLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
      // 4: WBOIT: revealage
      { format: app.wboit.revealageFormat, samples: app.getMSAASamples(), loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
        storeOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE, stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout: VK_IMAGE_LAYOUT_UNDEFINED, finalLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
    ],
    subpasses: [
      { // 0: opaque -> MSAA color(0), depth(2). NO resolve (moved to SP2 so the chain stays on-chip / merges).
        pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
        colorAttachmentCount: 2, pColorAttachments: colorRefs.ptr,
        pDepthStencilAttachment: &depthRef
      },
      { // 1: transparent WBOIT accumulation -> accum(3)+revealage(4), depth-test vs (2)
        pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
        colorAttachmentCount: 2, pColorAttachments: oitColorRefs.ptr,
        pDepthStencilAttachment: &depthRef
      },
      { // 2: composite WBOIT over MSAA opaque(0), then RESOLVE to 1x (1) at pass end
        pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
        inputAttachmentCount: 2, pInputAttachments: oitInputRefs.ptr,
        colorAttachmentCount: 2, pColorAttachments: colorRefs.ptr,   // write MSAA color(0) + UNUSED, blend over opaque
        pResolveAttachments: resolveRefs.ptr                          // resolve (0)->(1) here, at the end
      },
    ],
    dependencies: [
      { srcSubpass: VK_SUBPASS_EXTERNAL, dstSubpass: 0,
        srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
      }, { // 0 -> 1
        srcSubpass: 0, dstSubpass: 1,
        srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        srcAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
        dependencyFlags: VK_DEPENDENCY_BY_REGION_BIT
      }, { // 1 -> 2: composite reads accum/revealage as input attachments
        srcSubpass: 1, dstSubpass: 2,
        srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        dstStageMask: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        srcAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        dstAccessMask: VK_ACCESS_INPUT_ATTACHMENT_READ_BIT,
        dependencyFlags: VK_DEPENDENCY_BY_REGION_BIT
      },
    ],
  };
  app.sceneCmd.pass.create(app, info, "Scene", app.swapDeletionQueue);
}

/** Create the Post-Processing RenderPass 
 * This VkRenderPass samples the HDR texture, renders and to the SwapChain image
 */
void createPostProcessRenderPass(ref App app) {
  VkAttachmentReference colorRef = { attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };

  RenderPassInfo info = {
    attachments: [{
      format: app.present.format,
      samples: VK_SAMPLE_COUNT_1_BIT,
      loadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
      storeOp: VK_ATTACHMENT_STORE_OP_STORE,
      stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE, stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
      initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
      finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    }],
    subpasses: [{
      pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount: 1,
      pColorAttachments: &colorRef,
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
  app.postCmd.pass.create(app, info, "Post-process", app.swapDeletionQueue);
}

/** Create the ImGui RenderPass
 * This VkRenderPass loads the contents of the swapchain image and overlays ImGui.
 */
void createImGuiRenderPass(ref App app) {
  VkAttachmentReference colorRef = { attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };

  RenderPassInfo info = {
    attachments: [{
      format: app.present.format,
      samples: VK_SAMPLE_COUNT_1_BIT,
      loadOp: VK_ATTACHMENT_LOAD_OP_LOAD,
      storeOp: VK_ATTACHMENT_STORE_OP_STORE,
      stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE, stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
      initialLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
      finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    }],
    subpasses: [{
      pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount: 1,
      pColorAttachments: &colorRef,
    }],
    dependencies: [{
      srcSubpass:    VK_SUBPASS_EXTERNAL,     dstSubpass:    0,
      srcStageMask:  VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      dstStageMask:  VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      srcAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
    }],
  };
  app.imguiCmd.pass.create(app, info, "ImGui", app.swapDeletionQueue);
}

