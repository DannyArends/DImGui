/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import deletion : deAllocate;
import descriptor : updateDescriptorData;
import frustum : aabbInFrustum, extractFrustum;
import framebuffer : createFramebuffer;
import geometry : bufferGeometries, draw;
import images : createImage, cleanup, nameImageBuffer;
import renderpass : beginRecording, endRecording;
import sampler : createShadowSampler;
import shaders : createStageInfo, loadShaders, Shader, ShaderDef;
import swapchain : createImageView;
import uniforms : forEachUBO;
import validation : popLabel, pushLabel;

struct ShadowMap {
  ImageBuffer[] images;

  VkSampler sampler;
  Shader[] shaders;
  RenderPass renderPass;
  GraphicsPipeline pipeline;

  VkFormat format = VK_FORMAT_D32_SFLOAT;   /// Shadowmap format
  uint dimension = isAndroid ? 512 : 4096;  /// Shadowmap dimension
  uint budget = 8;                          /// Max lights casting shadows per frame (stage 1: first-K)
  float[2] bounds = [0.0f, 0.0f];           /// [height, radius] for shadow projection

  bool[] shadowDescriptorsDirty;

  uint lastShadowInstances = 0;
  uint totalShadowInstances = 0;
}

struct LightUbo {
  Matrix scene;
  uint nlights;
};

void createShadowMap(ref App app) {
  app.createShadowMapResources();
  app.createShadowMapRenderPass();
  app.createShadowSampler();
  app.loadShaders(app.shadows.shaders, [ShaderDef("data/shaders/shadow.glsl", shaderc_glsl_vertex_shader)]);
}

void addShadowMap(ref App app) {
  if(app.shadows.images.length >= 64) return;
  size_t l = app.shadows.images.length;
  app.shadows.images ~= ImageBuffer();
  app.createImage(app.shadows.images[l], 32, 32, app.shadows.format, VK_SAMPLE_COUNT_1_BIT,
                  VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
  app.shadows.images[l].view = app.createImageView(app.shadows.images[l].image, app.shadows.format, VK_IMAGE_ASPECT_DEPTH_BIT);
  app.shadows.renderPass.framebuffers ~= app.createFramebuffer(app.shadows.renderPass, [app.shadows.images[l].view], 32, 32, "Shadow", l);
  app.shadows.shadowDescriptorsDirty[] = true;
}

/** Resize light l's shadow map to `size`; defers old resources, re-points the descriptor next safe frame. */
void resizeShadowMap(ref App app, size_t l, uint size) {
  if(app.shadows.images[l].extent.width == size) return;

  // defer-destroy the old image+view and framebuffer (fence-gated, by value)
  app.deAllocate(app.shadows.images[l]);
  app.deAllocate(app.shadows.renderPass.framebuffers[l]);

  // create new image+view at the new size
  app.createImage(app.shadows.images[l], size, size, app.shadows.format, VK_SAMPLE_COUNT_1_BIT,
                  VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
  app.shadows.images[l].view = app.createImageView(app.shadows.images[l].image, app.shadows.format, VK_IMAGE_ASPECT_DEPTH_BIT);
  app.nameImageBuffer(app.shadows.images[l], format("ShadowImage #%d", l));

  // new framebuffer bound to the new view at the new size
  app.shadows.renderPass.framebuffers[l] = app.createFramebuffer(app.shadows.renderPass, [app.shadows.images[l].view], size, size, "Shadow", l);

  app.shadows.shadowDescriptorsDirty[] = true;
}

/** Shadow map resource creation */
void createShadowMapResources(ref App app) {
  if(app.verbose) SDL_Log("Shadow map resources creation");
  app.shadows.images.length = app.lights.length;

  for(size_t x = 0; x < app.lights.length; x++) {
    app.createImage(app.shadows.images[x], app.shadows.dimension, app.shadows.dimension,
                    app.shadows.format, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL,
                    VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
    if(app.verbose) SDL_Log(" - shadow map image created: %p", app.shadows.images[x].image);

    app.shadows.images[x].view = app.createImageView(app.shadows.images[x].image, app.shadows.format, VK_IMAGE_ASPECT_DEPTH_BIT);
    app.nameImageBuffer(app.shadows.images[x], format("ShadowImage #%d", x));
    if(app.verbose) SDL_Log(" - shadow map image view created: %p", app.shadows.images[x].view);
  }

  app.mainDeletionQueue.add((){
    for(size_t x = 0; x < app.lights.length; x++) { app.cleanup(app.shadows.images[x]); }
  });
}

/** Shadow map render pass creation */
void createShadowMapRenderPass(ref App app) {
  VkAttachmentReference depthRef = { attachment: 0, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL };

  RenderPassInfo info = {
    attachments: [{
      format:        app.shadows.format,
      samples:       VK_SAMPLE_COUNT_1_BIT,
      loadOp:        VK_ATTACHMENT_LOAD_OP_CLEAR,
      storeOp:       VK_ATTACHMENT_STORE_OP_STORE,
      stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE, stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
      initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
      finalLayout:   VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
    }],
    subpasses: [{
      pipelineBindPoint:       VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount:    0,
      pDepthStencilAttachment: &depthRef
    }],
    dependencies: [{ //  Write-after-Read
      srcSubpass:    VK_SUBPASS_EXTERNAL,
      srcStageMask:  VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
      dstStageMask:  VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
      srcAccessMask: VK_ACCESS_SHADER_READ_BIT,
      dstAccessMask: VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT
    },{ // Read-after-Write
      dstSubpass: VK_SUBPASS_EXTERNAL,
      srcStageMask:  VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
      dstStageMask:  VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      srcAccessMask: VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
      dstAccessMask: VK_ACCESS_SHADER_READ_BIT,
      dependencyFlags: VK_DEPENDENCY_BY_REGION_BIT
    }],
  };
  app.shadows.renderPass.create(app, info, "Shadows", app.mainDeletionQueue);
}

/** Create the shadow mapping pipeline */
void createShadowMapGraphicsPipeline(ref App app) {
  if(app.verbose) SDL_Log("Shadow map graphics pipeline creation");
  app.shadows.shadowDescriptorsDirty.length = app.framesInFlight;   // per-syncIndex
  app.shadows.shadowDescriptorsDirty[] = true; // force initial descriptor write

  VkPushConstantRange pushConstantRange = { stageFlags: VK_SHADER_STAGE_VERTEX_BIT, offset: 0, size: uint.sizeof };

  VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    setLayoutCount: 1,
    pSetLayouts: &app.layouts[Stage.SHADOWS],
    pushConstantRangeCount: 1,
    pPushConstantRanges: &pushConstantRange,
  };
  app.shadows.pipeline.createLayout(app, pipelineLayoutInfo, app.swapDeletionQueue);
  if(app.verbose) SDL_Log(" - shadow map pipeline layout created: %p", app.shadows.pipeline.layout);

  auto stages = createStageInfo(app.shadows.shaders);

  VkVertexInputBindingDescription[2] bindingDescription = Vertex.getBindingDescription();
  VkVertexInputAttributeDescription[7]  attributeDescriptions= Vertex.getShadowDescriptions();

  VkPipelineVertexInputStateCreateInfo vertexInputInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    vertexBindingDescriptionCount: cast(uint)bindingDescription.length,
    pVertexBindingDescriptions: &bindingDescription[0],
    vertexAttributeDescriptionCount: cast(uint)attributeDescriptions.length,
    pVertexAttributeDescriptions: attributeDescriptions.ptr,
  };

  VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
  };

  VkPipelineViewportStateCreateInfo viewportState = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    viewportCount: 1, scissorCount: 1
  };

  VkDynamicState[2] dynamicStates = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR];

  VkPipelineDynamicStateCreateInfo dynamicState = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    dynamicStateCount: 2,
    pDynamicStates: dynamicStates.ptr
  };

  VkPipelineRasterizationStateCreateInfo rasterizer = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    depthClampEnable: VK_FALSE,
    polygonMode: VK_POLYGON_MODE_FILL,
    lineWidth: 1.0f,
    cullMode: VK_CULL_MODE_NONE,
    frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE,
    depthBiasEnable: VK_TRUE,
    depthBiasConstantFactor: 3.0f,
    depthBiasSlopeFactor: 4.5f,
  };

  VkPipelineMultisampleStateCreateInfo multisampling = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    rasterizationSamples: VK_SAMPLE_COUNT_1_BIT
  };

  VkPipelineDepthStencilStateCreateInfo depthStencil = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    depthTestEnable: VK_TRUE,
    depthWriteEnable: VK_TRUE,
    depthCompareOp: VK_COMPARE_OP_LESS_OR_EQUAL
  };

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
    pDynamicState: &dynamicState,
    layout: app.shadows.pipeline.layout,
    renderPass: app.shadows.renderPass,
    subpass: 0
  };
  app.shadows.pipeline.create(app, pipelineInfo, "Shadows", app.swapDeletionQueue);
}

/** Update the shadow mapping UBO */
void updateShadowMapUBO(ref App app, Shader[] shaders, uint syncIndex) {
  LightUbo ubo = {
    scene : Matrix.init,
    nlights : cast(uint)app.lights.length
  };

  shaders.forEachUBO((d) { memcpy(app.ubos[d.base].data[syncIndex], &ubo, d.bytes); });
  if(app.trace) SDL_Log("Light space matrix updated for frame %d", app.totalFramesRendered);
}

/** Record the draw calls in the shadow command buffer */
void recordShadowCommandBuffer(ref App app, uint syncIndex) {
  auto cmd = app.shadows.renderPass.beginRecording(app, syncIndex, "Shadow");

  if(app.trace) SDL_Log("Beginning shadow map render pass");

  VkClearValue clearDepth = { depthStencil: { depth: 1.0f, stencil: 0 } };

  pushLabel(cmd, "Objects Buffering", Colors.lightgray);
  app.bufferGeometries(cmd);
  popLabel(cmd);

  pushLabel(cmd, "SSBO Buffering", Colors.lightgray);
  app.updateDescriptorData(app.shadows.shaders, app.shadows.renderPass.commands, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, syncIndex);
  popLabel(cmd);

  pushLabel(cmd, "Shadow Loop", Colors.lightgray);
  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.shadows.pipeline.layout, 0, 1, &app.sets[Stage.SHADOWS][syncIndex], 0, null);

  app.shadows.lastShadowInstances = app.shadows.totalShadowInstances = 0;
  for(uint l = 0; l < app.lights.length; l++) {
    if(!app.lights[l].enabled || app.lights[l].cull[1] < 0.0f) continue;   // not enabled or selected to cast this frame

    pushLabel(cmd, toStringz(format("Shadow RenderPass: %d", l)), Colors.lightgray);

    auto lFrustum = extractFrustum(app.lights[l].lightSpaceMatrix);

    VkRenderPassBeginInfo renderPassInfo = {
      sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      renderPass: app.shadows.renderPass,
      framebuffer: app.shadows.renderPass.framebuffers[l],
      renderArea: { extent: { width: app.shadows.images[l].extent.width, height: app.shadows.images[l].extent.height } },
      clearValueCount: 1,
      pClearValues: &clearDepth,
    };
    vkCmdBeginRenderPass(cmd, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.shadows.pipeline.pipeline);

    auto ext = app.shadows.images[l].extent;
    VkViewport vp = { minDepth: 0.0f, maxDepth: 1.0f, width: cast(float)ext.width, height: cast(float)ext.height };
    VkRect2D   sc = { extent: { width: ext.width, height: ext.height } };
    vkCmdSetViewport(cmd, 0, 1, &vp);
    vkCmdSetScissor(cmd, 0, 1, &sc);

    vkCmdPushConstants(cmd, app.shadows.pipeline.layout, VK_SHADER_STAGE_VERTEX_BIT, 0, uint.sizeof, &l);
    foreach(obj; app.objects) {
      if(!obj.isVisible || !obj.castShadow || obj.topology != VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST) continue;
      app.shadows.totalShadowInstances += obj.instances.length;
      if(obj.box !is null && !lFrustum.aabbInFrustum(obj.box.wmin, obj.box.wmax)) continue;
      app.shadows.lastShadowInstances += obj.instances.length;
      app.draw(obj, cmd);
    }
    vkCmdEndRenderPass(cmd);
    popLabel(cmd);
  }
  popLabel(cmd);
  app.shadows.renderPass.endRecording(syncIndex);
}

