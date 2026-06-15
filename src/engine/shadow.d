/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import deletion : deAllocate;
import descriptor : updateDescriptorData;
import frustum : aabbInFrustum, extractFrustum;
import framebuffer : createFramebuffer, cleanup;
import geometry : bufferGeometries, draw;
import images : createImage, cleanup, nameImageBuffer, copyImageLayer;
import sampler : createShadowSampler;
import shaders : createStageInfo, loadShaders, Shader, ShaderDef;
import validation : popLabel, pushLabel;
import vector : xyz;
import views : createImageView, createLayerViews;

enum MAX_SHADOW_MAPS = isAndroid ? 8 : 32; // Maximum number of shadown maps, limits budget

struct ShadowMap {
  ImageBuffer[] images;

  VkSampler sampler;
  Shader[] shaders;
  CommandBuffer cmd;
  GraphicsPipeline pipeline;

  VkFormat format = VK_FORMAT_D32_SFLOAT;   /// Shadowmap format
  uint dimension = isAndroid ? 512 : 4096;  /// Shadowmap dimension
  uint budget = isAndroid ? 4 : 12;         /// Max lights casting shadows per frame (stage 1: first-K)
  float[2] bounds = [0.0f, 0.0f];           /// [height, radius] for shadow projection

  bool[] shadowDescriptorsDirty;
  bool[] staticDirty;

  uint staticRebuilds = 0;                  /// slots that re-rendered layer 0 this frame
  uint activeShadowMaps = 0;                /// slots rendered this frame
  uint staticShadowInstances = 0;           /// TODO: Static/dynamic shadow caching
  uint dynamicShadowInstances = 0;          /// TODO: Static/dynamic shadow caching
}

struct LightUbo {
  Matrix scene;
  uint nlights;
};

void createShadowMap(ref App app) {
  app.shadows.cmd.renderpass.length = 2;
  app.createShadowMapRenderPass(app.shadows.cmd.pass(0), VK_ATTACHMENT_LOAD_OP_CLEAR);
  app.createShadowMapRenderPass(app.shadows.cmd.pass(1), VK_ATTACHMENT_LOAD_OP_LOAD);
  app.initShadowPool();
  app.createShadowSampler();
  app.loadShaders(app.shadows.shaders, [ShaderDef("data/shaders/shadow.glsl", shaderc_glsl_vertex_shader)]);
}

/** Shadow map resolution for a light: full dimension for the directional sun, quarter for point/spot. */
@nogc uint shadowResolution(ref App app, ref Light light) nothrow {
  return light.directional ? app.shadows.dimension : app.shadows.dimension / 4;
}

void initShadowPool(ref App app) {
  if(app.shadows.images.length == MAX_SHADOW_MAPS) return;
  app.shadows.images.length = app.shadows.staticDirty.length = MAX_SHADOW_MAPS;
  app.shadows.cmd.pass(0).framebuffers.length = app.shadows.cmd.pass(1).framebuffers.length = MAX_SHADOW_MAPS;
  for(size_t s = 0; s < MAX_SHADOW_MAPS; s++) app.makeShadowMap(app.shadows, s, 32);

  app.mainDeletionQueue.add((){
    foreach(fb; app.shadows.cmd.pass(0).framebuffers) { app.cleanup(fb); }
    foreach(fb; app.shadows.cmd.pass(1).framebuffers) { app.cleanup(fb); }
    foreach(ref img; app.shadows.images) { app.cleanup(img); }
  });
}

/** Create shadow image+view+framebuffer for slot l at the given square size. */
void makeShadowMap(ref App app, ref ShadowMap map, size_t s, uint size) {
  app.createImage(map.images[s], size, size, map.format, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL,
                  VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT 
                  | VK_IMAGE_USAGE_TRANSFER_DST_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 1, 2);
  app.createLayerViews(map.images[s], map.format, VK_IMAGE_ASPECT_DEPTH_BIT);
  app.nameImageBuffer(map.images[s], format("ShadowImage #%d", s));
  map.cmd.pass(0).framebuffers[s] = app.createFramebuffer(map.cmd.pass(0), [map.images[s].view(0)], size, size, "Static Shadow", s);
  map.cmd.pass(1).framebuffers[s] = app.createFramebuffer(map.cmd.pass(1), [map.images[s].view(1)], size, size, "Dynamic Shadow", s);
}

/** Resize shadow map s to `size`; defers old resources, re-points the descriptor next safe frame. */
void resizeShadowMap(ref App app, size_t s, uint size) {
  if(app.shadows.images[s].extent.width == size) return;
  app.deAllocate(app.shadows.cmd.pass(0).framebuffers[s]);
  app.deAllocate(app.shadows.cmd.pass(1).framebuffers[s]);
  app.deAllocate(app.shadows.images[s]);
  app.makeShadowMap(app.shadows, s, size);
  app.shadows.shadowDescriptorsDirty[] = true;
}

/** Shadow map render pass creation */
void createShadowMapRenderPass(ref App app, ref RenderPass pass, VkAttachmentLoadOp loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR) {
  VkAttachmentReference depthRef = { attachment: 0, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL };
  bool load = (loadOp == VK_ATTACHMENT_LOAD_OP_LOAD);

  RenderPassInfo info = {
    attachments: [{
      format:        app.shadows.format,
      samples:       VK_SAMPLE_COUNT_1_BIT,
      loadOp:        loadOp,
      storeOp:       VK_ATTACHMENT_STORE_OP_STORE,
      stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE, stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
      initialLayout: (load? VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_UNDEFINED),
      finalLayout:   VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
    }],
    subpasses: [{
      pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount: 0,
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
  pass.create(app, info, (load? "Dynamic Shadows" : "Static Shadows"), app.mainDeletionQueue);
}

/** Record shadow casters for light l into cmd; staticPhase selects static vs dynamic casters. */
void recordCasters(ref App app, VkCommandBuffer cmd, ref RenderPass pass, size_t s, uint l, Plane[6] lFrustum, VkExtent3D ext, bool staticPhase) {
  VkClearValue clearDepth = { depthStencil: { depth: 1.0f, stencil: 0 } };

  VkRenderPassBeginInfo rp = {
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass: pass, framebuffer: pass.framebuffers[s],
    renderArea: { extent: { width: ext.width, height: ext.height } },
    clearValueCount: staticPhase ? 1 : 0,
    pClearValues:    staticPhase ? &clearDepth : null,
  };
  vkCmdBeginRenderPass(cmd, &rp, VK_SUBPASS_CONTENTS_INLINE);
  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.shadows.pipeline.pipeline);

  VkViewport vp = { minDepth: 0.0f, maxDepth: 1.0f, width: cast(float)ext.width, height: cast(float)ext.height };
  VkRect2D   sc = { extent: { width: ext.width, height: ext.height } };
  vkCmdSetViewport(cmd, 0, 1, &vp);
  vkCmdSetScissor(cmd, 0, 1, &sc);
  vkCmdPushConstants(cmd, app.shadows.pipeline.layout, VK_SHADER_STAGE_VERTEX_BIT, 0, uint.sizeof, &l);

  foreach(obj; app.objects) {
    if(!obj.isVisible || !obj.castShadow || obj.topology != VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST) continue;
    if(obj.box !is null) {
      if(obj.box.distanceSq(app.lights[l].position.xyz) > app.lights[l].cull[0] * app.lights[l].cull[0]) continue;
      if(!lFrustum.aabbInFrustum(obj.box.wmin, obj.box.wmax)) continue;
    }
    if(obj.isStatic != staticPhase) continue;
    ((obj.isStatic)?app.shadows.staticShadowInstances : app.shadows.dynamicShadowInstances) += obj.instances.length;
    app.draw(obj, cmd);
  }
  vkCmdEndRenderPass(cmd);
}

/** Create the shadow mapping pipeline */
void createShadowMapGraphicsPipeline(ref App app) {
  if(app.verbose) SDL_Log("Shadow map graphics pipeline creation");
  app.buffers.descriptorsDirty.length = app.shadows.shadowDescriptorsDirty.length = app.framesInFlight;   // per-syncIndex
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
    renderPass: app.shadows.cmd.pass(0),
    subpass: 0
  };
  app.shadows.pipeline.create(app, pipelineInfo, "Shadows", app.swapDeletionQueue);
}

/** Update the shadow mapping UBO */
void updateShadowMapUBO(ref App app, Descriptor d, uint syncIndex) {
  LightUbo ubo = { scene : Matrix.init, nlights : cast(uint)app.lights.length };
  memcpy(app.ubos[d.base][syncIndex].data, &ubo, d.bytes);
}

/** Record the draw calls in the shadow command buffer */
void recordShadowCommandBuffer(ref App app, uint syncIndex) {
  auto cmd = app.shadows.cmd.begin(app, syncIndex, "Shadow");

  if(app.trace) SDL_Log("Beginning shadow map render pass");

  VkClearValue clearDepth = { depthStencil: { depth: 1.0f, stencil: 0 } };

  pushLabel(cmd, "Objects Buffering", Colors.lightgray);
  app.bufferGeometries(cmd);
  popLabel(cmd);

  pushLabel(cmd, "SSBO Buffering", Colors.lightgray);
  app.updateDescriptorData(app.shadows.shaders, app.shadows.cmd.commands, syncIndex);
  popLabel(cmd);

  pushLabel(cmd, "Shadow Loop", Colors.lightgray);
  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.shadows.pipeline.layout, 0, 1, &app.sets[Stage.SHADOWS][syncIndex], 0, null);

  app.shadows.staticShadowInstances = app.shadows.dynamicShadowInstances = 0;
  app.shadows.staticRebuilds = app.shadows.activeShadowMaps = 0;
  for(uint l = 0; l < app.lights.length; l++) {
    int s = cast(int)app.lights[l].cull[1];
    if(!app.lights[l].enabled || s < 0) continue;
    app.shadows.activeShadowMaps++;

    auto lFrustum = extractFrustum(app.lights[l].lightSpaceMatrix);
    pushLabel(cmd, toStringz(format("Shadow RenderPass: %d", l)), Colors.lightgray);
    if(app.shadows.staticDirty[s]) {
      // Static -> layer 0
      app.recordCasters(cmd, app.shadows.cmd.pass(0), s, l, lFrustum, app.shadows.images[s].extent, true);
      app.shadows.staticDirty[s] = false;
      app.shadows.staticRebuilds++;
    }
    // Copy
    app.copyImageLayer(cmd, app.shadows.images[s].image, 0, 1, app.shadows.images[s].extent, app.shadows.format);
    // Dynamic -> layer 1
    app.recordCasters(cmd, app.shadows.cmd.pass(1), s, l, lFrustum, app.shadows.images[s].extent, false);
    popLabel(cmd);
  }
  popLabel(cmd);
  app.shadows.cmd.end(syncIndex);
}

