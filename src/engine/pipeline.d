/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import shaders : createStageInfo;
import devices : getMSAASamples;
import vertex : Vertex;
import validation : nameVulkanObject;

/** GraphicsPipeline
 */
struct GraphicsPipeline {
  VkPipelineLayout layout;
  VkPipeline pipeline;
}

/** Create a GraphicsPipeline object for a specified topology
 */
void createGraphicsPipeline(ref App app, VkPrimitiveTopology topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST) {
  app.pipelines[topology] = GraphicsPipeline();
  auto bindingDescription = Vertex.getBindingDescription();
  auto attributeDescriptions = Vertex.getRenderDescriptions();

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
    topology: topology
  };

  // Viewport
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

  // Rasterizer (Point, Line, Fill)
  VkPipelineRasterizationStateCreateInfo rasterizer = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    polygonMode: VK_POLYGON_MODE_FILL,                        // Point/Line/Fill
    lineWidth: 1.0f,
    cullMode: VK_CULL_MODE_NONE,                              //VK_CULL_MODE_BACK_BIT,
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
    setLayoutCount: 1,
    pSetLayouts: &app.layouts[Stage.RENDER],
  };
  enforceVK(vkCreatePipelineLayout(app.device, &pipelineLayoutInfo, null, &app.pipelines[topology].layout));
  
  VkPipelineDepthStencilStateCreateInfo depthStencil = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    depthTestEnable: VK_TRUE,
    depthWriteEnable: VK_TRUE,
    depthCompareOp: VK_COMPARE_OP_LESS,
  };

  auto stages = createStageInfo(app.shaders);
  VkGraphicsPipelineCreateInfo pipelineInfo = {
    sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    stageCount: cast(uint)stages.length,
    pStages: &stages[0],
    pVertexInputState: &vertexInputInfo,
    pInputAssemblyState: &inputAssembly,
    pViewportState: &viewportState,
    pRasterizationState: &rasterizer,
    pMultisampleState: &multisampling,
    pDepthStencilState: &depthStencil,
    pColorBlendState: &colorBlending,
    layout: app.pipelines[topology].layout,
    renderPass: app.scene
  };

  enforceVK(vkCreateGraphicsPipelines(app.device, null, 1, &pipelineInfo, null, &app.pipelines[topology].pipeline));

  app.nameVulkanObject(app.pipelines[topology].layout, toStringz(format("[LAYOUT] Render %s", topology)), VK_OBJECT_TYPE_PIPELINE_LAYOUT);
  app.nameVulkanObject(app.pipelines[topology].pipeline, toStringz(format("[PIPELINE] Render %s", topology)), VK_OBJECT_TYPE_PIPELINE);

  app.swapDeletionQueue.add((){
    vkDestroyPipelineLayout(app.device, app.pipelines[topology].layout, app.allocator);
    vkDestroyPipeline(app.device, app.pipelines[topology].pipeline, app.allocator);
  });
}

/** Create a GraphicsPipeline object for Post-process
 */
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
  enforceVK(vkCreatePipelineLayout(app.device, &pipelineLayoutInfo, null, &app.postProcessPipeline.layout));
  
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
    renderPass: app.postprocess
  };

  enforceVK(vkCreateGraphicsPipelines(app.device, null, 1, &pipelineInfo, null, &app.postProcessPipeline.pipeline));

  app.nameVulkanObject(app.postProcessPipeline.layout, toStringz("[LAYOUT] Post-process"), VK_OBJECT_TYPE_PIPELINE_LAYOUT);
  app.nameVulkanObject(app.postProcessPipeline.pipeline, toStringz("[PIPELINE] Post-process"), VK_OBJECT_TYPE_PIPELINE);

  app.swapDeletionQueue.add((){
    vkDestroyPipelineLayout(app.device, app.postProcessPipeline.layout, app.allocator);
    vkDestroyPipeline(app.device, app.postProcessPipeline.pipeline, app.allocator);
  });
}
