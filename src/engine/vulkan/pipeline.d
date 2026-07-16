/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import shaders : createStageInfo;
import devices : getMSAASamples;
import validation : nameVulkanObject;

/** GraphicsPipeline */
struct GraphicsPipeline {
  VkPipelineLayout layout;
  VkPrimitiveTopology topology;
  VkPipeline[Specialization] variants;

  /** Default stored variant (compute / externally-set pipelines). No building. */
  @property VkPipeline pipeline(Specialization s = Specialization.init) { return variants[s]; }

  /** Lazy: return the variant, building + caching on first request */
  VkPipeline get(ref App app, Specialization s = Specialization.init) {
    if(auto p = s in variants) return *p;
    return app.buildVariant(topology, layout, s);
  }

  /** Store an externally-created pipeline (e.g. compute, which builds outside create) */
  void set(VkPipeline p, Specialization s = Specialization.init) { variants[s] = p; }

  void create(ref App app, VkGraphicsPipelineCreateInfo info, string label, ref DeletionQueue queue, Specialization spec = Specialization.init) {
    VkPipeline p; enforceVK(vkCreateGraphicsPipelines(app.device, null, 1, &info, app.allocator, &p)); variants[spec] = p;
    app.nameVulkanObject(layout, cstr("[LAYOUT] %s", label), VK_OBJECT_TYPE_PIPELINE_LAYOUT);
    app.nameVulkanObject(p, cstr("[PIPELINE] %s", label), VK_OBJECT_TYPE_PIPELINE);
    queue.add((){ vkDestroyPipeline(app.device, p, app.allocator); });
  }

  void createLayout(ref App app, VkPipelineLayoutCreateInfo info, ref DeletionQueue queue) {
    enforceVK(vkCreatePipelineLayout(app.device, &info, app.allocator, &layout));
    queue.add((){ vkDestroyPipelineLayout(app.device, layout, app.allocator); });
  }
}

/** Set up the GraphicsPipeline (layout + topology); variants build lazily on first use */
void createGraphicsPipeline(ref App app, VkPrimitiveTopology topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST) {
  app.pipelines[topology] = GraphicsPipeline();
  app.pipelines[topology].topology = topology;

  VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    setLayoutCount: 1,
    pSetLayouts: &app.layouts[Stage.RENDER],
  };
  if(app.pipelines[topology].layout is null) app.pipelines[topology].createLayout(app, pipelineLayoutInfo, app.swapDeletionQueue);
}

/** Build (and cache) one pipeline variant. All create-state is local: valid for the synchronous
 *  vkCreateGraphicsPipelines call, then discarded. Rebuilt from scratch on swapchain resize. */
VkPipeline buildVariant(ref App app, VkPrimitiveTopology topology, VkPipelineLayout layout, Specialization s) {
  auto bindingDescription = Vertex.getBindingDescription();
  auto attributeDescriptions = Vertex.getRenderDescriptions();

  VkPipelineVertexInputStateCreateInfo vertexInputInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    vertexBindingDescriptionCount: bindingDescription.length,
    pVertexBindingDescriptions: &bindingDescription[0],
    vertexAttributeDescriptionCount: attributeDescriptions.length,
    pVertexAttributeDescriptions: &attributeDescriptions[0]
  };

  VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    topology: topology
  };

  VkViewport viewport = {
    minDepth: 0.0f, maxDepth: 1.0f,
    width: cast(float) app.camera.width,
    height: cast(float) app.camera.height,
  };
  VkRect2D scissor = { offset: {0, 0}, extent: app.camera.currentExtent };
  VkPipelineViewportStateCreateInfo viewportState = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    viewportCount: 1, pViewports: &viewport,
    scissorCount: 1, pScissors: &scissor
  };

  VkPipelineRasterizationStateCreateInfo rasterizer = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    polygonMode: VK_POLYGON_MODE_FILL, lineWidth: 1.0f,
    cullMode: VK_CULL_MODE_NONE,
    frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE,
  };

  VkPipelineMultisampleStateCreateInfo multisampling = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    sampleShadingEnable: VK_FALSE,
    rasterizationSamples: app.getMSAASamples(),
    minSampleShading: 1.0f
  };

  VkPipelineColorBlendAttachmentState colorBlendAttachment = {
    colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    blendEnable: VK_TRUE,
    srcColorBlendFactor: VK_BLEND_FACTOR_ONE, dstColorBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
    colorBlendOp: VK_BLEND_OP_ADD,
    srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE, dstAlphaBlendFactor: VK_BLEND_FACTOR_ONE,
    alphaBlendOp: VK_BLEND_OP_ADD
  };

  VkPipelineColorBlendAttachmentState[2] opaqueBlendAttachments = [colorBlendAttachment, colorBlendAttachment];
  VkPipelineColorBlendStateCreateInfo colorBlending = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    logicOpEnable: VK_FALSE, logicOp: VK_LOGIC_OP_COPY,
    attachmentCount: 2, pAttachments: opaqueBlendAttachments.ptr,
    blendConstants: [0.0f, 0.0f, 0.0f, 0.0f]
  };

  // WBOIT dual-target blend: accum = additive (ONE,ONE); revealage = multiplicative (ZERO, ONE_MINUS_SRC_COLOR)
  VkPipelineColorBlendAttachmentState[2] wboitAttachments = [
    { // 0: accumulation
      colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
      blendEnable: VK_TRUE,
      srcColorBlendFactor: VK_BLEND_FACTOR_ONE, dstColorBlendFactor: VK_BLEND_FACTOR_ONE, colorBlendOp: VK_BLEND_OP_ADD,
      srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE, dstAlphaBlendFactor: VK_BLEND_FACTOR_ONE, alphaBlendOp: VK_BLEND_OP_ADD
    },
    { // 1: revealage
      colorWriteMask: VK_COLOR_COMPONENT_R_BIT,
      blendEnable: VK_TRUE,
      srcColorBlendFactor: VK_BLEND_FACTOR_ZERO, dstColorBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR, colorBlendOp: VK_BLEND_OP_ADD,
      srcAlphaBlendFactor: VK_BLEND_FACTOR_ZERO, dstAlphaBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, alphaBlendOp: VK_BLEND_OP_ADD
    }
  ];
  VkPipelineColorBlendStateCreateInfo wboitBlending = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    logicOpEnable: VK_FALSE, logicOp: VK_LOGIC_OP_COPY,
    attachmentCount: 2, pAttachments: wboitAttachments.ptr,
    blendConstants: [0.0f, 0.0f, 0.0f, 0.0f]
  };

  VkPipelineDepthStencilStateCreateInfo depthStencil = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    depthTestEnable: VK_TRUE,
    depthWriteEnable: s.depthPass ? VK_TRUE : VK_FALSE,
    depthCompareOp: s.depthPass ? VK_COMPARE_OP_LESS : VK_COMPARE_OP_LESS_OR_EQUAL,
  };

  ShaderStage stages = createStageInfo(app.shaders, topology, s);

  VkGraphicsPipelineCreateInfo pipelineInfo = {
    sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    stageCount: cast(uint)stages.info.length,
    pStages: &stages.info[0],
    pVertexInputState: &vertexInputInfo,
    pInputAssemblyState: &inputAssembly,
    pViewportState: &viewportState,
    pRasterizationState: &rasterizer,
    pMultisampleState: &multisampling,
    pDepthStencilState: &depthStencil,
    pColorBlendState: s.depthPass ? null : (s.wboit ? &wboitBlending : &colorBlending),
    layout: layout,
    renderPass: s.depthPass ? app.depthCmd.pass : app.sceneCmd.pass,
    subpass: s.wboit ? 1u : 0u
  };

  VkPipeline p;
  enforceVK(vkCreateGraphicsPipelines(app.device, null, 1, &pipelineInfo, app.allocator, &p));
  app.nameVulkanObject(p, cstr("[PIPELINE] %s A%d I%d S%d D%d An%d W%d", 
                               topology, s.alpha, s.instanced, s.sdf, s.depthPass, s.animated, s.wboit), VK_OBJECT_TYPE_PIPELINE);
  app.swapDeletionQueue.add((){ vkDestroyPipeline(app.device, p, app.allocator); });
  app.pipelines[topology].variants[s] = p;
  return p;
}

/** Create a GraphicsPipeline object for Post-process */
void createPostProcessGraphicsPipeline(ref App app) {
  app.postProcessPipeline = GraphicsPipeline();

  VkPipelineVertexInputStateCreateInfo vertexInputInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
  };

  // Input Assembly: Triangle list for a quad
  VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    primitiveRestartEnable: VK_FALSE
  };

  // Viewport and Scissor will match swapchain extent
  VkViewport viewport = {
    minDepth: 0.0f, maxDepth: 1.0f,
    width: cast(float) app.camera.width,
    height: cast(float) app.camera.height,
  };

  VkRect2D scissor = { offset: {0, 0}, extent: app.camera.currentExtent };

  VkPipelineViewportStateCreateInfo viewportState = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    viewportCount: 1, pViewports: &viewport,
    scissorCount: 1, pScissors: &scissor
  };

  // Rasterizer: No culling needed for fullscreen quad
  VkPipelineRasterizationStateCreateInfo rasterizer = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    depthClampEnable: VK_FALSE,
    rasterizerDiscardEnable: VK_FALSE,
    polygonMode: VK_POLYGON_MODE_FILL,
    lineWidth: 1.0f,
    cullMode: VK_CULL_MODE_NONE, // No culling
    frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE,
  };

  // Multisamping: Always 1 sample for post-process (output to swapchain)
  VkPipelineMultisampleStateCreateInfo multisampling = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    sampleShadingEnable: VK_FALSE,
    rasterizationSamples: VK_SAMPLE_COUNT_1_BIT, // Single sample
    minSampleShading: 1.0f,
    pSampleMask: null,
  };

  VkPipelineColorBlendAttachmentState colorBlendAttachment = {
    colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT
  };

  VkPipelineColorBlendStateCreateInfo colorBlending = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    logicOpEnable: VK_FALSE,
    attachmentCount: 1,
    pAttachments: &colorBlendAttachment
  };

  // Pipeline Layout: Needs a descriptor set for the sampled HDR texture
  VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    setLayoutCount: 1,
    pSetLayouts: &app.layouts[Stage.POST]
  };
  app.postProcessPipeline.createLayout(app, pipelineLayoutInfo, app.swapDeletionQueue);

  // Shaders for post-processing (vertex shader for quad, fragment shader for tonemapping/sampling)
  auto stages = createStageInfo(app.postProcess);
  VkGraphicsPipelineCreateInfo pipelineInfo = {
    sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    stageCount: cast(uint)stages.length,
    pStages: &stages[0],
    pVertexInputState: &vertexInputInfo,
    pInputAssemblyState: &inputAssembly,
    pViewportState: &viewportState,
    pRasterizationState: &rasterizer,
    pMultisampleState: &multisampling,
    pColorBlendState: &colorBlending,
    layout: app.postProcessPipeline.layout,
    renderPass: app.postCmd.pass
  };
  app.postProcessPipeline.create(app, pipelineInfo, "Post-process", app.swapDeletionQueue);
}

