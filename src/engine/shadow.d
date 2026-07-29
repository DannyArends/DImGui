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
import lights : computeLightSpace, computeRadius;
import images : cleanup, copyImageLayer, createNamedImage;
import sampler : createShadowSampler;
import shaders : createStageInfo, loadShaders, Shader, ShaderDef;
import validation : popLabel, pushLabel;
import vector : xyz, vSub, dot;

enum MAX_SHADOW_MAPS = isAndroid ? 8 : 32;                /// Maximum number of shadown maps, limits budget
enum float SHADOW_DEPTH_BIAS = 2.0f;     /// Constant depth bias
enum float SHADOW_SLOPE_BIAS = 10.0f;    /// Slope-scaled bias (dominant term for grazing faces)
enum uint NUM_CASCADES = 3;                               /// Number of shadow map cascades
enum float[3] CASCADE_RADIUS = [ 64.0f, 256.0f, 0.0f];    /// Near cascades 2x split, last radius is camera-derived
enum float[3] CASCADE_SPLIT  = [ 32.0f, 128.0f, 1e9f];    /// Cascade selection thresholds (shadowDistances, radial from lookat)

struct ShadowMap {
  ImageBuffer[] images;                     /// Per-slot shadow map images (layer 0 static, layer 1 static+dynamic composite)

  VkSampler sampler;                        /// Comparison sampler for depth lookups
  Shader[] shaders;                         /// Shadow depth-only shader(s)
  CommandBuffer!2 cmd;                      /// Two-pass command buffer: static (0), dynamic (1)
  GraphicsPipeline pipeline;                /// Shadow depth-only pipeline

  VkFormat format = VK_FORMAT_D32_SFLOAT;   /// Shadowmap format
  uint dimension = isAndroid ? 1024 : 4096; /// Shadowmap dimension
  uint budget = isAndroid ? 4 : 24;         /// Max lights casting shadows per frame (stage 1: first-K)
  float[2] bounds = [0.0f, 0.0f];           /// [height, radius] for shadow projection

  bool[] shadowDescriptorsDirty;            /// Per-frame flag: shadow sampler descriptors need rewriting
  bool[] staticDirty;                       /// Per-slot flag: rebuild layer 0 this frame
  Matrix[] slotStaticMatrix;                /// lightSpaceMatrix the slot's static layer (layer 0) was rendered with
  Matrix[MAX_SHADOW_MAPS] slotVP;           /// Per-slot desired light-space matrix this frame (pre-commit)

  uint staticCursor = 0;                    /// round-robin cursor over pending static rebuilds
  uint staticRebuilds = 0;                  /// slots that re-rendered layer 0 this frame
  uint activeShadowMaps = 0;                /// slots rendered this frame
  uint staticShadowInstances = 0;           /// Static shadow instances count
  uint dynamicShadowInstances = 0;          /// Dynamic shadow instances count
}

struct LightUbo {
  Matrix scene;                       /// Scene root transform
  float[4] cascadeSplit;              /// per-cascade shadowDistance splits (x,y,z used)
  Matrix[MAX_SHADOW_MAPS] slotVP;     /// per-slot view-proj
  uint nlights;                       /// Active light count
}

void createShadowMap(ref App app) {
  app.createShadowMapRenderPass(app.shadows.cmd.pass(0), VK_ATTACHMENT_LOAD_OP_CLEAR);
  app.createShadowMapRenderPass(app.shadows.cmd.pass(1), VK_ATTACHMENT_LOAD_OP_LOAD);
  app.initShadowPool();
  app.createShadowSampler();
  app.loadShaders(app.shadows.shaders, [ShaderDef("data/shaders/vertex.shadow.glsl", shaderc_glsl_vertex_shader)]);
}

/** Shadow importance: brighter & nearer scores higher; <=0 means ineligible. */
@nogc float shadowScore(ref Light light, float[3] eye) nothrow {
  if(light.directional || !light.enabled) return -1.0f;
  float[3] d = vSub(light.position.xyz, eye);
  return max(light.intensity[0], light.intensity[1], light.intensity[2]) / (dot(d, d) + 1.0f);
}

/** Shadow map resolution for a light: full dimension for the directional sun, quarter for point/spot. */
@nogc uint shadowResolution(ref App app, ref Light light) nothrow {
  return light.directional ? app.shadows.dimension : app.shadows.dimension / 2;
}

void initShadowPool(ref App app) {
  if(app.shadows.images.length == MAX_SHADOW_MAPS) return;
  app.shadows.images.length = app.shadows.staticDirty.length = app.shadows.slotStaticMatrix.length = MAX_SHADOW_MAPS;
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
  VkImageUsageFlags usage;
  usage |= VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
  usage |= VK_IMAGE_USAGE_SAMPLED_BIT;
  usage |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  usage |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;

  app.createNamedImage(map.images[s], size, size, map.format, VK_IMAGE_ASPECT_DEPTH_BIT, format("ShadowImage #%d", s),
                       VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL, usage, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 1, 2);
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


/** Assign shadow-map slots: directional cascades first, then the top-K point/spot lights by score. */
void assignShadowSlots(ref App app) {
  if(app.lights.scoreBuf.length < app.lights.length) app.lights.scoreBuf.length = app.lights.length;
  assert(app.lights.scoreBuf.length >= app.lights.length, "scoreBuf not sized for light count");
  auto score = app.lights.scoreBuf[0 .. app.lights.length];
  float slot = 0.0f;
  foreach(i, ref light; app.lights) {
    light.computeCone();
    if(light.directional && light.enabled && slot + NUM_CASCADES <= MAX_SHADOW_MAPS) {
      light.cull[1 .. 2] = [slot]; slot += NUM_CASCADES; score[i] = -1.0f;
    } else {
      light.cull[1] = -1.0f; score[i] = light.shadowScore(app.camera.position);
    }
  }
  for(uint picked = 0; picked < app.shadows.budget && slot < MAX_SHADOW_MAPS; picked++) {
    size_t best = size_t.max;
    foreach(i; 0 .. app.lights.length) { if(score[i] > 0.0f && (best == size_t.max || score[i] > score[best])) best = i; }
    if(best == size_t.max) break;
    app.lights[best].cull[1] = slot++; score[best] = -1.0f;
  }
}

/** Compute each active slot's light-space matrix and resize its map; a resize forces a static rebuild. */
void updateShadowSlotMatrices(ref App app) {
  foreach(ref light; app.lights) {
    light.computeRadius();
    int first = cast(int)light.cull[1];
    if(first < 0) continue;
    uint count = light.directional ? NUM_CASCADES : 1u;
    uint resolution = app.shadowResolution(light);
    foreach(c; 0 .. count) {
      int s = first + cast(int)c;
      float radius = (count > 1) ? ((c == count - 1) ? app.camera.visibleRadius : CASCADE_RADIUS[c]) : 0.0f;
      app.shadows.slotVP[s] = app.camera.computeLightSpace(light, app.shadows.bounds, resolution, radius);
      uint before = app.shadows.images[s].extent.width;
      app.resizeShadowMap(s, resolution);
      if(app.shadows.images[s].extent.width != before) app.shadows.staticDirty[s] = true;  // reallocated: rebuild now
    }
  }
}

/** Pick at most one drifted cascade per frame (round-robin), then commit the matrix of every slot rebuilding this frame. */
@nogc nothrow void selectStaticRebuilds(ref App app) {
  foreach(step; 0 .. MAX_SHADOW_MAPS) {
    uint s = cast(uint)((app.shadows.staticCursor + step) % MAX_SHADOW_MAPS);
    if(!app.shadows.staticDirty[s] && (app.shadows.slotVP[s] != app.shadows.slotStaticMatrix[s])) {
      app.shadows.staticDirty[s] = true;
      app.shadows.staticCursor = (s + 1) % MAX_SHADOW_MAPS; break;
    }
  }
  foreach(s; 0 .. MAX_SHADOW_MAPS) if(app.shadows.staticDirty[s]) app.shadows.slotStaticMatrix[s] = app.shadows.slotVP[s];
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
void recordCasters(ref App app, VkCommandBuffer cmd, ref RenderPass pass, size_t s, Plane[6] lFrustum, VkExtent3D ext, bool staticPhase) {
  VkClearValue clearDepth = { depthStencil: { depth: 1.0f, stencil: 0 } };
  VkRect2D sc = { extent: { width: ext.width, height: ext.height } };

  VkRenderPassBeginInfo rp = {
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass: pass, framebuffer: pass.framebuffers[s],
    renderArea: sc,
    clearValueCount: staticPhase ? 1 : 0,
    pClearValues: staticPhase ? &clearDepth : null,
  };
  vkCmdBeginRenderPass(cmd, &rp, VK_SUBPASS_CONTENTS_INLINE);
  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.shadows.pipeline.pipeline);

  VkViewport vp = { minDepth: 0.0f, maxDepth: 1.0f, width: cast(float)ext.width, height: cast(float)ext.height };
  vkCmdSetViewport(cmd, 0, 1, &vp);
  vkCmdSetScissor(cmd, 0, 1, &sc);
  uint slot = cast(uint)s;
  vkCmdPushConstants(cmd, app.shadows.pipeline.layout, VK_SHADER_STAGE_VERTEX_BIT, 0, uint.sizeof, &slot);

  float slotRadius = (s < NUM_CASCADES) ? CASCADE_RADIUS[s] : CASCADE_RADIUS[0];
  if(slotRadius <= 0.0f) slotRadius = app.camera.visibleRadius;   // far cascade
  float scale = CASCADE_RADIUS[0] / slotRadius;                    // 1.0 for cascade 0, smaller for wider cascades
  vkCmdSetDepthBias(cmd, SHADOW_DEPTH_BIAS * scale, 0.0f, SHADOW_SLOPE_BIAS * scale);

  foreach(obj; app.objects) {
    if(!obj.isVisible || !obj.castShadow || obj.topology != VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST) continue;
    if(obj.box !is null) {
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
    setLayoutCount: 1, pSetLayouts: &app.layouts[Stage.SHADOWS],
    pushConstantRangeCount: 1, pPushConstantRanges: &pushConstantRange,
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

  VkDynamicState[3] dynamicStates = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR, VK_DYNAMIC_STATE_DEPTH_BIAS];

  VkPipelineDynamicStateCreateInfo dynamicState = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    dynamicStateCount: 3, pDynamicStates: dynamicStates.ptr
  };

  VkPipelineRasterizationStateCreateInfo rasterizer = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    depthClampEnable: VK_FALSE,
    polygonMode: VK_POLYGON_MODE_FILL,
    lineWidth: 1.0f,
    cullMode: VK_CULL_MODE_NONE,
    frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE,
    depthBiasEnable: VK_TRUE,
    depthBiasConstantFactor: 0.0f,
    depthBiasSlopeFactor: 0.0f,
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
  LightUbo ubo = { scene: Matrix.init, nlights: cast(uint)app.lights.length };
  ubo.slotVP[] = app.shadows.slotStaticMatrix[];
  ubo.cascadeSplit = [CASCADE_SPLIT[0], CASCADE_SPLIT[1], CASCADE_SPLIT[2], cast(float)NUM_CASCADES];
  memcpy(app.ubos[d.base][syncIndex].data, &ubo, d.bytes);
}

/** Record the draw calls in the shadow command buffer */
void recordShadowCommandBuffer(ref App app, uint syncIndex) {
  auto cmd = app.shadows.cmd.begin(app, syncIndex, "Shadow");
  pushLabel(cmd, "Shadows", Colors.lightgray);

  pushLabel(cmd, "Shadows Descriptors & SSBO", Colors.lightgray);
  app.updateDescriptorData(app.shadows.shaders, app.shadows.cmd.commands, syncIndex);
  popLabel(cmd);

  vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, app.shadows.pipeline.layout, 0, 1, &app.sets[Stage.SHADOWS][syncIndex], 0, null);

  app.shadows.staticShadowInstances = app.shadows.dynamicShadowInstances = app.shadows.staticRebuilds = app.shadows.activeShadowMaps = 0;
  for(uint l = 0; l < app.lights.length; l++) {
    int first = cast(int)app.lights[l].cull[1];
    if(!app.lights[l].enabled || first < 0) continue;
    uint count = app.lights[l].directional ? NUM_CASCADES : 1u;
    for(uint c = 0; c < count; c++) {
      uint s = cast(uint)first + c;
      app.shadows.activeShadowMaps++;
      auto lFrustum = extractFrustum(app.shadows.slotStaticMatrix[s]);
      pushLabel(cmd, cstr("Shadow RenderPass: slot %d", s), Colors.lightgray);
      if(app.shadows.staticDirty[s]) {
        app.recordCasters(cmd, app.shadows.cmd.pass(0), s, lFrustum, app.shadows.images[s].extent, true);
        app.shadows.staticDirty[s] = false;
        app.shadows.staticRebuilds++;
      }
      app.copyImageLayer(cmd, app.shadows.images[s].image, 0, 1, app.shadows.images[s].extent, app.shadows.format);
      app.recordCasters(cmd, app.shadows.cmd.pass(1), s, lFrustum, app.shadows.images[s].extent, false);
      popLabel(cmd);
    }
  }
  popLabel(cmd);
  app.shadows.cmd.end(syncIndex);
}

