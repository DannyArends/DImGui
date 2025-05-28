/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import shaders : createStageInfo;
import devices : getMSAASamples;
import vertex : Vertex;

/** GraphicsPipeline
 */
struct GraphicsPipeline {
  VkPipelineLayout pipelineLayout;
  VkPipeline graphicsPipeline;
}

/** Create a GraphicsPipeline object for a specified topology
 */
void createGraphicsPipeline(ref App app, VkPrimitiveTopology topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST) {
  app.pipelines[topology] = GraphicsPipeline();
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
    topology: topology,
    primitiveRestartEnable: VK_FALSE
  };

  // Viewport
  VkViewport viewport = { x: 0.0f, y: 0.0f,
    width: cast(float) app.camera.width,
    height: cast(float) app.camera.height,
    minDepth: 0.0f,
    maxDepth: 1.0f
  };

  VkRect2D scissor = { offset: {0, 0}, extent: app.camera.currentExtent };

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
    rasterizationSamples: app.getMSAASamples(),
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
    setLayoutCount: 1, // Optional
    pSetLayouts: &app.descriptorSetLayout, // Optional
  };
  enforceVK(vkCreatePipelineLayout(app.device, &pipelineLayoutInfo, null, &app.pipelines[topology].pipelineLayout));
  
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
    pDepthStencilState: &depthStencil,                        // Optional
    pColorBlendState: &colorBlending,
    pDynamicState: null,                             // Optional
    layout: app.pipelines[topology].pipelineLayout,
    renderPass: app.renderpass,
    subpass: 0,
    basePipelineHandle: null,                                 // Optional
  };

  enforceVK(vkCreateGraphicsPipelines(app.device, null, 1, &pipelineInfo, null, &app.pipelines[topology].graphicsPipeline));
  app.frameDeletionQueue.add((){
    vkDestroyPipelineLayout(app.device, app.pipelines[topology].pipelineLayout, app.allocator);
    vkDestroyPipeline(app.device, app.pipelines[topology].graphicsPipeline, app.allocator);
  });
}
