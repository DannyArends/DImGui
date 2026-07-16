/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import devices : getMSAASamples;
import images : cleanup, createNamedImage, ImageBuffer;
import shaders : createStageInfo;

struct WBOIT {
  ImageBuffer accumulation;                                   /// Accumulation target (RGBA16F, single-sample)
  ImageBuffer revealage;                                      /// Revealage target (R16F, single-sample)
  ImageBuffer opaqueDummy;                                    /// Dummy loc-1 sink for opaque pipeline (never read)
  Shader[] shaders;                                           /// Resolve shader (fullscreen composite)
  GraphicsPipeline resolvePipeline;                           /// Resolve/composite pipeline (subpass 2)
  VkFormat accumulationFormat = VK_FORMAT_R16G16B16A16_SFLOAT;
  VkFormat revealageFormat = VK_FORMAT_R16_SFLOAT;
  alias shaders this;
}

ShaderDef[] WBOITShaders = [
  ShaderDef("data/shaders/wboit.vertex.glsl", shaderc_glsl_vertex_shader),
  ShaderDef("data/shaders/wboit.fragment.glsl", shaderc_glsl_fragment_shader),
];

/** Allocate the single-sample WBOIT accumulation targets (input attachments for the resolve subpass) */
void createWBOITResources(ref App app) {
  app.createNamedImage(app.wboit.accumulation, app.camera.width, app.camera.height, app.wboit.accumulationFormat,
                       VK_IMAGE_ASPECT_COLOR_BIT, "WBOIT Accumulation", app.getMSAASamples(), VK_IMAGE_TILING_OPTIMAL,
                       VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT);
  app.createNamedImage(app.wboit.revealage, app.camera.width, app.camera.height, app.wboit.revealageFormat,
                       VK_IMAGE_ASPECT_COLOR_BIT, "WBOIT Revealage", app.getMSAASamples(), VK_IMAGE_TILING_OPTIMAL,
                       VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT);
  app.createNamedImage(app.wboit.opaqueDummy, app.camera.width, app.camera.height, app.wboit.revealageFormat,
                       VK_IMAGE_ASPECT_COLOR_BIT, "WBOIT Opaque Dummy", app.getMSAASamples(), VK_IMAGE_TILING_OPTIMAL,
                       VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT);
  app.swapDeletionQueue.add((){ 
    app.cleanup(app.wboit.accumulation);
    app.cleanup(app.wboit.revealage);
    app.cleanup(app.wboit.opaqueDummy);
  });
}

/** Record the fullscreen resolve draw (scene subpass 2) */
void drawWBOITResolve(ref App app, VkCommandBuffer cmd) {
  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.wboit.resolvePipeline.pipeline());
  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.wboit.resolvePipeline.layout, 0, 1, &app.sets[Stage.RESOLVE][app.syncIndex], 0, null);
  vkCmdDraw(cmd, 3, 1, 0, 0);
}

/** Resolve pipeline: fullscreen composite of accum/revealage over the resolved HDR (scene subpass 2) */
void createWBOITResolvePipeline(ref App app) {
  app.wboit.resolvePipeline = GraphicsPipeline();

  VkPipelineVertexInputStateCreateInfo vertexInputInfo = { sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
  VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
  };
  VkViewport viewport = { minDepth: 0.0f, maxDepth: 1.0f, width: cast(float)app.camera.width, height: cast(float)app.camera.height };
  VkRect2D scissor = { offset: {0, 0}, extent: app.camera.currentExtent };
  VkPipelineViewportStateCreateInfo viewportState = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    viewportCount: 1, pViewports: &viewport, scissorCount: 1, pScissors: &scissor
  };
  VkPipelineRasterizationStateCreateInfo rasterizer = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    polygonMode: VK_POLYGON_MODE_FILL, lineWidth: 1.0f, cullMode: VK_CULL_MODE_NONE, frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE
  };
  VkPipelineMultisampleStateCreateInfo multisampling = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    rasterizationSamples: VK_SAMPLE_COUNT_1_BIT, minSampleShading: 1.0f
  };
  // Composite transparent over opaque: src-alpha over
  VkPipelineColorBlendAttachmentState colorBlendAttachment = {
    colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    blendEnable: VK_TRUE,
    srcColorBlendFactor: VK_BLEND_FACTOR_SRC_ALPHA, dstColorBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, colorBlendOp: VK_BLEND_OP_ADD,
    srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE, dstAlphaBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, alphaBlendOp: VK_BLEND_OP_ADD
  };
  VkPipelineColorBlendStateCreateInfo colorBlending = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    attachmentCount: 1, pAttachments: &colorBlendAttachment
  };

  VkPipelineLayoutCreateInfo layoutInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    setLayoutCount: 1, pSetLayouts: &app.layouts[Stage.RESOLVE]
  };
  app.wboit.resolvePipeline.createLayout(app, layoutInfo, app.swapDeletionQueue);

  auto stages = createStageInfo(app.wboit.shaders);

  int samples = cast(int)app.getMSAASamples();
  VkSpecializationMapEntry sampleEntry = { constantID: 0, offset: 0, size: int.sizeof };
  VkSpecializationInfo specInfo = { mapEntryCount: 1, pMapEntries: &sampleEntry, dataSize: int.sizeof, pData: &samples };
  foreach(ref st; stages) if(st.stage == VK_SHADER_STAGE_FRAGMENT_BIT){ st.pSpecializationInfo = &specInfo; }
  VkGraphicsPipelineCreateInfo pipelineInfo = {
    sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    stageCount: cast(uint)stages.length, pStages: &stages[0],
    pVertexInputState: &vertexInputInfo, pInputAssemblyState: &inputAssembly,
    pViewportState: &viewportState, pRasterizationState: &rasterizer,
    pMultisampleState: &multisampling, pColorBlendState: &colorBlending,
    layout: app.wboit.resolvePipeline.layout,
    renderPass: app.sceneCmd.pass,
    subpass: 2u
  };
  app.wboit.resolvePipeline.create(app, pipelineInfo, "WBOIT Resolve", app.swapDeletionQueue);
}
