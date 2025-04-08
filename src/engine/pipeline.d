import engine;

import shaders : createShaderModule, createShaderStageInfo;
import vertex : Vertex;

void destroyPipeline(ref App app) {
  vkDestroyPipelineLayout(app.device, app.pipeline.pipelineLayout, app.allocator);
  vkDestroyPipeline(app.device, app.pipeline.graphicsPipeline, app.allocator);
}

GraphicsPipeline createGraphicsPipeline(ref App app, const(char)* vertPath = "assets/shaders/vert.spv", const(char)* fragPath = "assets/shaders/frag.spv") {
  GraphicsPipeline pipeline;

  auto vShader = app.createShaderModule(vertPath);
  auto fShader = app.createShaderModule(fragPath);

  VkPipelineShaderStageCreateInfo vInfo = createShaderStageInfo(VK_SHADER_STAGE_VERTEX_BIT, vShader);
  VkPipelineShaderStageCreateInfo fInfo = createShaderStageInfo(VK_SHADER_STAGE_FRAGMENT_BIT, fShader);
  VkPipelineShaderStageCreateInfo[] shaderStages = [ vInfo, fInfo ];

  auto bindingDescription = Vertex.getBindingDescription();
  auto attributeDescriptions = Vertex.getAttributeDescriptions();

  // Vertex input
  VkPipelineVertexInputStateCreateInfo vertexInputInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    vertexBindingDescriptionCount: bindingDescription.length,
    pVertexBindingDescriptions: &bindingDescription[0],     // Vertex Description
    vertexAttributeDescriptionCount: attributeDescriptions.length,
    pVertexAttributeDescriptions: &attributeDescriptions[0] // Vertex Attributes
  };

  // Input Assembly
  VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    primitiveRestartEnable: VK_FALSE
  };

  // Viewport
  VkViewport viewport = { x: 0.0f, y: 0.0f,
    width: cast(float) app.capabilities.currentExtent.width,
    height: cast(float) app.capabilities.currentExtent.height,
    minDepth: 0.0f,
    maxDepth: 1.0f
  };

  VkRect2D scissor = { offset: {0, 0}, extent: app.capabilities.currentExtent };

  VkPipelineViewportStateCreateInfo viewportState = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    viewportCount: 1,
    pViewports: &viewport,
    scissorCount: 1,
    pScissors: &scissor
  };

  // Rasterizer (Point, Line, Fill)
  VkPipelineRasterizationStateCreateInfo rasterizer = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    depthClampEnable: VK_FALSE,
    rasterizerDiscardEnable: VK_FALSE,
    polygonMode: VK_POLYGON_MODE_FILL,                        // Point/Line/Fill
    lineWidth: 1.0f,
    cullMode: VK_CULL_MODE_NONE,                              //VK_CULL_MODE_BACK_BIT,
    frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE,
    depthBiasEnable: VK_FALSE,
    depthBiasConstantFactor: 0.0f,                            // Optional
    depthBiasClamp: 0.0f,                                     // Optional
    depthBiasSlopeFactor: 0.0f                                // Optional
  };

  VkPipelineMultisampleStateCreateInfo multisampling = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    sampleShadingEnable: VK_FALSE,
    rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
    minSampleShading: 1.0f,                                   // Optional
    pSampleMask: null,                                        // Optional
    alphaToCoverageEnable: VK_FALSE,                          // Optional
    alphaToOneEnable: VK_FALSE                                // Optional
  };

  VkPipelineColorBlendAttachmentState colorBlendAttachment = {
    colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    blendEnable: VK_TRUE,
    srcColorBlendFactor: VK_BLEND_FACTOR_ONE,                 // Optional
    dstColorBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, // Optional
    colorBlendOp: VK_BLEND_OP_ADD,                            // Optional
    srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE,                 // Optional
    dstAlphaBlendFactor: VK_BLEND_FACTOR_ONE,                 // Optional
    alphaBlendOp: VK_BLEND_OP_ADD                             // Optional
  };

  VkPipelineColorBlendStateCreateInfo colorBlending = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    logicOpEnable: VK_FALSE,
    logicOp: VK_LOGIC_OP_COPY,                                // Optional
    attachmentCount: 1,
    pAttachments: &colorBlendAttachment,
    blendConstants: [0.0f, 0.0f, 0.0f, 0.0f]
  };
  
  VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
  };
  enforceVK(vkCreatePipelineLayout(app.device, &pipelineLayoutInfo, null, &pipeline.pipelineLayout));

  VkPipelineDepthStencilStateCreateInfo depthStencil = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    depthTestEnable: VK_TRUE,
    depthWriteEnable: VK_TRUE,
    depthCompareOp: VK_COMPARE_OP_LESS,
    depthBoundsTestEnable: VK_FALSE,
    minDepthBounds: 0.0f,                                     // Optional
    maxDepthBounds: 1.0f,                                     // Optional
    stencilTestEnable: VK_FALSE,
    front: {},                                                // Optional
    back: {}                                                  // Optional
  };

  VkGraphicsPipelineCreateInfo pipelineInfo = {
    sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    stageCount: 2,
    pStages: &shaderStages[0],
    pVertexInputState: &vertexInputInfo,
    pInputAssemblyState: &inputAssembly,
    pViewportState: &viewportState,
    pRasterizationState: &rasterizer,
    pMultisampleState: &multisampling,
    pDepthStencilState: &depthStencil,                        // Optional
    pColorBlendState: &colorBlending,
    pDynamicState: null,                             // Optional
    layout: pipeline.pipelineLayout,
    renderPass: app.renderpass,
    subpass: 0,
    basePipelineHandle: null,                                 // Optional
  };

  enforceVK(vkCreateGraphicsPipelines(app.device, null, 1, &pipelineInfo, null, &pipeline.graphicsPipeline));
  vkDestroyShaderModule(app.device, vShader, app.allocator);
  vkDestroyShaderModule(app.device, fShader, app.allocator);
  return(pipeline);
}

