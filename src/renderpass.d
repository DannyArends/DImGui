import engine;

void createRenderPass(ref App app) {
  VkAttachmentDescription attachmentDescription = {
    format : app.surfaceformats[0].format,
    samples : VK_SAMPLE_COUNT_1_BIT,
    loadOp : VK_ATTACHMENT_LOAD_OP_CLEAR,
    storeOp : VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp : VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout : VK_IMAGE_LAYOUT_UNDEFINED,
    finalLayout : VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
  };

  VkAttachmentReference colorAttachment = {
    attachment : 0,
    layout : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
  };

  VkSubpassDescription subpassDescription = {
    pipelineBindPoint : VK_PIPELINE_BIND_POINT_GRAPHICS,
    colorAttachmentCount : 1,
    pColorAttachments : &colorAttachment
  };

  VkSubpassDependency subpassDependency = {
    srcSubpass : VK_SUBPASS_EXTERNAL,
    dstSubpass : 0,
    srcStageMask : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    dstStageMask : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    srcAccessMask : 0,
    dstAccessMask : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
  };

  VkRenderPassCreateInfo createInfo = {
    sType : VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    attachmentCount : 1,
    pAttachments : &attachmentDescription,
    subpassCount : 1,
    pSubpasses : &subpassDescription,
    dependencyCount : 1,
    pDependencies : &subpassDependency,
  };
  enforceVK(vkCreateRenderPass(app.device, &createInfo, null, &app.renderpass));
}
