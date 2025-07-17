/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : Colors;
import descriptor : Descriptor, createDescriptorSetLayout, createDescriptorSet, updateDescriptorSet;
import images : createImage, deAllocate, transitionImageLayout;
import lights : updateLighting;
import matrix : Matrix;
import pipeline : GraphicsPipeline;
import geometry : shadow, Instance;
import reflection : reflectShaders, createResources;
import ssbo : updateSSBO;
import shaders : Shader, createStageInfo, createShaderModule;
import swapchain : createImageView;
import validation : pushLabel, popLabel;
import vertex : Vertex, VERTEX, INSTANCE;

struct ShadowMap {
  ImageBuffer[] images;

  VkSampler sampler;
  Shader[] shaders;
  VkRenderPass renderPass;
  GraphicsPipeline pipeline;

  VkFormat format = VK_FORMAT_D32_SFLOAT;   /// Shadowmap format
  uint dimension = 2048;                    /// Shadowmap resolution
}

struct LightUbo {
  Matrix scene;
  uint nlights;
};

void createShadowMap(ref App app) {
  app.createShadowMapResources();
  app.createShadowMapRenderPass();
  app.createShadowShader();
}

/** 
 * Shadow map resource creation
 */
void createShadowMapResources(ref App app) {
  if(app.verbose) SDL_Log("Shadow map resources creation");
  app.shadows.images.length = app.lights.length;

  for(size_t x = 0; x < app.lights.length; x++) {
    app.createImage(app.shadows.dimension, app.shadows.dimension,
                    &app.shadows.images[x].image, &app.shadows.images[x].memory,
                    app.shadows.format, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL,
                    VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
    if(app.verbose) SDL_Log(" - shadow map image created: %p", app.shadows.images[x].image);

    app.shadows.images[x].view = app.createImageView(app.shadows.images[x].image, app.shadows.format, VK_IMAGE_ASPECT_DEPTH_BIT);
    if(app.verbose) SDL_Log(" - shadow map image view created: %p", app.shadows.images[x].view);
  }

  VkSamplerCreateInfo samplerInfo = {
    sType: VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
    magFilter: VK_FILTER_LINEAR,                            // For soft edges with PCF
    minFilter: VK_FILTER_LINEAR,                            // For soft edges with PCF
    addressModeU: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
    addressModeV: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
    addressModeW: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
    borderColor: VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE,
    compareEnable: VK_TRUE,                                 // Enable hardware depth comparison
    compareOp: VK_COMPARE_OP_LESS_OR_EQUAL,                 // For shadow mapping
    mipmapMode: VK_SAMPLER_MIPMAP_MODE_NEAREST,             // No mipmaps for single depth map
  };

  enforceVK(vkCreateSampler(app.device, &samplerInfo, app.allocator, &app.shadows.sampler));
  if(app.verbose) SDL_Log(" - shadow map sampler created: %p", app.shadows.sampler);

  app.mainDeletionQueue.add((){
    for(size_t x = 0; x < app.lights.length; x++) { app.deAllocate(app.shadows.images[x]); }
    vkDestroySampler(app.device, app.shadows.sampler, app.allocator);
  });
}

/** 
 * Shadow map render pass  creation
 */
void createShadowMapRenderPass(ref App app) {
  if(app.verbose) SDL_Log("Shadow map render pass creation");

  VkAttachmentDescription depthAttachment = {
    format: app.shadows.format,
    samples: VK_SAMPLE_COUNT_1_BIT,
    loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
    storeOp: VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
    finalLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
  };

  VkAttachmentReference depthAttachmentRef = { attachment: 0, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL };

  VkSubpassDescription subpass = {
    pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
    colorAttachmentCount: 0,
    pDepthStencilAttachment: &depthAttachmentRef
  };

  VkSubpassDependency dependency = {
    srcSubpass: VK_SUBPASS_EXTERNAL,
    srcStageMask: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
    dstStageMask: VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
    srcAccessMask: VK_ACCESS_SHADER_READ_BIT,
    dstAccessMask: VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT
  };

  VkRenderPassCreateInfo renderPassInfo = {
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    attachmentCount: 1,
    pAttachments: &depthAttachment,
    subpassCount: 1,
    pSubpasses: &subpass,
    dependencyCount: 1,
    pDependencies: &dependency
  };

  enforceVK(vkCreateRenderPass(app.device, &renderPassInfo, app.allocator, &app.shadows.renderPass));
  if(app.verbose) SDL_Log("Shadow map render pass created.");

  app.mainDeletionQueue.add((){ vkDestroyRenderPass(app.device, app.shadows.renderPass, app.allocator); });
}

/** Load vertex shadow shader
 */
void createShadowShader(ref App app, const(char)* vertPath = "data/shaders/shadow.glsl") {
  auto vShader = app.createShaderModule(vertPath, shaderc_glsl_vertex_shader);

  app.shadows.shaders = [ vShader ];

  app.mainDeletionQueue.add(() {
    for(uint i = 0; i < app.shadows.shaders.length; i++) {
      vkDestroyShaderModule(app.device, app.shadows.shaders[i], app.allocator);
    }
  });
}

/** Create the shadow mapping pipeline
 */
void createShadowMapGraphicsPipeline(ref App app) {
  if(app.verbose) SDL_Log("Shadow map graphics pipeline creation");
  app.layouts[SHADOWS] = app.createDescriptorSetLayout(app.shadows.shaders);
  app.sets[SHADOWS] = createDescriptorSet(app.device, app.pools[SHADOWS], app.layouts[SHADOWS], app.framesInFlight);

  VkPushConstantRange pushConstantRange = { stageFlags: VK_SHADER_STAGE_VERTEX_BIT, offset: 0, size: uint.sizeof };

  VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    setLayoutCount: 1,
    pSetLayouts: &app.layouts[SHADOWS],
    pushConstantRangeCount: 1,
    pPushConstantRanges: &pushConstantRange,
  };

  enforceVK(vkCreatePipelineLayout(app.device, &pipelineLayoutInfo, app.allocator, &app.shadows.pipeline.layout));
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

  VkViewport viewport = {
    minDepth: 0.0f, maxDepth: 1.0f,
    width: cast(float)app.shadows.dimension,
    height: cast(float)app.shadows.dimension,
  };

  VkRect2D scissor = { extent: { width: app.shadows.dimension, height: app.shadows.dimension } };

  VkPipelineViewportStateCreateInfo viewportState = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    viewportCount: 1, pViewports: &viewport,
    scissorCount: 1, pScissors: &scissor
  };

  VkPipelineRasterizationStateCreateInfo rasterizer = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    depthClampEnable: VK_FALSE,
    polygonMode: VK_POLYGON_MODE_FILL,
    lineWidth: 1.0f,
    cullMode: VK_CULL_MODE_BACK_BIT,
    frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE,
    depthBiasEnable: VK_TRUE,
    depthBiasConstantFactor: 1.25f,
    depthBiasSlopeFactor: 1.75f
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
    layout: app.shadows.pipeline.layout,
    renderPass: app.shadows.renderPass,
    subpass: 0
  };

  enforceVK(vkCreateGraphicsPipelines(app.device, null, 1, &pipelineInfo, app.allocator, &app.shadows.pipeline.pipeline));
  if(app.verbose) SDL_Log("Shadow map graphics pipeline created: %p", app.shadows.pipeline.pipeline);

  app.frameDeletionQueue.add((){
    vkDestroyDescriptorSetLayout(app.device, app.layouts[SHADOWS], app.allocator);
    vkDestroyPipelineLayout(app.device, app.shadows.pipeline.layout, app.allocator);
    vkDestroyPipeline(app.device, app.shadows.pipeline.pipeline, app.allocator);
  });
}

void updateShadowMapUBO(ref App app, Shader[] shaders, uint syncIndex) {
  LightUbo ubo = {
    scene : Matrix.init,
    nlights : cast(uint)app.lights.length
  };

  for(uint s = 0; s < shaders.length; s++) {
    auto shader = shaders[s];
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
        memcpy(app.ubos[shader.descriptors[d].base].data[syncIndex], &ubo, shader.descriptors[d].bytes);
      }
    }
  }
  if(app.trace) SDL_Log("Light space matrix updated for frame %d", app.totalFramesRendered);
}

void writeShadowMap(App app, ref VkWriteDescriptorSet[] write, Descriptor descriptor, VkDescriptorSet dst, ref VkDescriptorImageInfo[] imageInfos){
  size_t startIndex = imageInfos.length;

  for (size_t i = 0; i < app.lights.length; i++) {
    imageInfos ~= VkDescriptorImageInfo( // Assign directly to the single info struct
      imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      imageView: app.shadows.images[i].view, // Use the shadow map's image view
      sampler: app.shadows.sampler     // Use the shadow map's sampler
    );
  }
  VkWriteDescriptorSet set = {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: dst,
    dstBinding: descriptor.binding,
    dstArrayElement: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount: cast(uint)app.lights.length,
    pImageInfo: &imageInfos[startIndex]
  }; 
  write ~= set;
}

void recordShadowCommandBuffer(ref App app, uint syncIndex) {
  vkResetCommandBuffer(app.shadowBuffers[app.syncIndex], 0); // Reset for recording

  VkCommandBufferBeginInfo beginInfo = {
      sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      pInheritanceInfo: null
  };
  enforceVK(vkBeginCommandBuffer(app.shadowBuffers[app.syncIndex], &beginInfo));

  if(app.verbose) SDL_Log("Beginning shadow map render pass");

  VkClearValue clearDepth = { depthStencil: { depth: 1.0f, stencil: 0 } };

  pushLabel(app.shadowBuffers[app.syncIndex], "SSBO Buffering", Colors.lightgray);

  foreach(shader; app.shadows.shaders){
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
        if(SDL_strstr(shader.descriptors[d].base, "BoneMatrices") != null) { 
          app.updateSSBO!Matrix(app.shadowBuffers[syncIndex], app.boneOffsets, shader.descriptors[d], syncIndex);
        }
        if(SDL_strstr(shader.descriptors[d].base, "LightMatrices") != null) {
          app.updateLighting(app.shadowBuffers[app.syncIndex], shader.descriptors[d]);
        }
      }
    }
  }
  popLabel(app.shadowBuffers[app.syncIndex]);

  pushLabel(app.shadowBuffers[app.syncIndex], "Objects Buffering", Colors.lightgray);
  for(size_t x = 0; x < app.objects.length; x++) {
    if(!app.objects[x].isBuffered) {
      if(app.trace) SDL_Log("Buffer object: %d %p", x, app.objects[x]);
      app.objects[x].buffer(app, app.shadowBuffers[syncIndex]);
    }
  }
  popLabel(app.shadowBuffers[app.syncIndex]);

  pushLabel(app.shadowBuffers[app.syncIndex], "Shadow Loop", Colors.lightgray);
  vkCmdBindDescriptorSets(app.shadowBuffers[syncIndex], VK_PIPELINE_BIND_POINT_GRAPHICS, 
                          app.shadows.pipeline.layout, 0, 1, &app.sets[SHADOWS][syncIndex], 0, null);

  for(size_t l = 0; l < app.lights.length; l++) {
    pushLabel(app.shadowBuffers[app.syncIndex], toStringz(format("Shadow RenderPass: %d", l)), Colors.lightgray);
    VkRenderPassBeginInfo renderPassInfo = {
      sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      renderPass: app.shadows.renderPass,
      framebuffer: app.framebuffers.shadow[l],
      renderArea: {
          offset: { x: 0, y: 0 },
          extent: { width: app.shadows.dimension, height: app.shadows.dimension }
      },
      clearValueCount: 1,
      pClearValues: &clearDepth,
    };
    app.updateShadowMapUBO(app.shadows.shaders, app.syncIndex);

    vkCmdBeginRenderPass(app.shadowBuffers[app.syncIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdBindPipeline(app.shadowBuffers[app.syncIndex], VK_PIPELINE_BIND_POINT_GRAPHICS, app.shadows.pipeline.pipeline);
    uint currentLightIndex = cast(uint)l;
    vkCmdPushConstants(app.shadowBuffers[app.syncIndex], app.shadows.pipeline.layout,
                       VK_SHADER_STAGE_VERTEX_BIT, 0, uint.sizeof, &currentLightIndex);
    for(size_t x = 0; x < app.objects.length; x++) {
      if(app.objects[x].isVisible && app.objects[x].topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST) {
        app.shadow(app.objects[x], syncIndex);
      }
    }
    vkCmdEndRenderPass(app.shadowBuffers[app.syncIndex]);
    popLabel(app.shadowBuffers[app.syncIndex]);
  }
  popLabel(app.shadowBuffers[app.syncIndex]);
  enforceVK(vkEndCommandBuffer(app.shadowBuffers[app.syncIndex])); // End recording for shadow map buffer
}

