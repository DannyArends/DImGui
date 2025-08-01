/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : Colors;
import descriptor : Descriptor, updateDescriptorData, createDescriptorSetLayout, createDescriptorSet, updateDescriptorSet;
import images : createImage, deAllocate, transitionImageLayout, nameImageBuffer;
import matrix : Matrix;
import pipeline : GraphicsPipeline;
import geometry : shadow, Instance, bufferGeometries;
import reflection : reflectShaders, createResources;
import shaders : Shader, ShaderDef, loadShaders, createStageInfo;
import swapchain : createImageView;
import validation : pushLabel, popLabel, nameVulkanObject;
import vertex : Vertex, VERTEX, INSTANCE;

struct ShadowMap {
  ImageBuffer[] images;

  Shader[] shaders;
  VkRenderPass renderPass;
  GraphicsPipeline pipeline;

  VkFormat format = VK_FORMAT_D32_SFLOAT;   /// Shadowmap format
  version (Android) {
    uint dimension = 512;                   /// Shadowmap resolution
  }else{
    uint dimension = 2048;                  /// Shadowmap resolution
  }
}

struct LightUbo {
  Matrix scene;
  uint nlights;
};

void createShadowMap(ref App app) {
  app.createShadowMapResources();
  app.createShadowMapRenderPass();
  app.loadShaders(app.shadows.shaders, [ShaderDef("data/shaders/shadow.glsl", shaderc_glsl_vertex_shader)]);
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
    app.nameImageBuffer(app.shadows.images[x], format("ShadowImage #%d", x));
    if(app.verbose) SDL_Log(" - shadow map image view created: %p", app.shadows.images[x].view);
  }

  app.mainDeletionQueue.add((){
    for(size_t x = 0; x < app.lights.length; x++) { app.deAllocate(app.shadows.images[x]); }
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
  app.nameVulkanObject(app.shadows.renderPass, toStringz("[RENDERPASS] Shadows"), VK_OBJECT_TYPE_RENDER_PASS);

  if(app.verbose) SDL_Log("Shadow map render pass created.");

  app.mainDeletionQueue.add((){ vkDestroyRenderPass(app.device, app.shadows.renderPass, app.allocator); });
}

/** Create the shadow mapping pipeline
 */
void createShadowMapGraphicsPipeline(ref App app) {
  if(app.verbose) SDL_Log("Shadow map graphics pipeline creation");
  VkPushConstantRange pushConstantRange = { stageFlags: VK_SHADER_STAGE_VERTEX_BIT, offset: 0, size: uint.sizeof };

  VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    setLayoutCount: 1,
    pSetLayouts: &app.layouts[Stage.SHADOWS],
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
  app.nameVulkanObject(app.shadows.pipeline.layout, toStringz("[LAYOUT] Shadows"), VK_OBJECT_TYPE_PIPELINE_LAYOUT);
  app.nameVulkanObject(app.shadows.pipeline.pipeline, toStringz("[PIPELINE] Shadows"), VK_OBJECT_TYPE_PIPELINE);

  if(app.verbose) SDL_Log("Shadow map graphics pipeline created: %p", app.shadows.pipeline.pipeline);

  app.swapDeletionQueue.add((){
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
  if(app.verbose) SDL_Log("writeShadowMap");
  size_t startIndex = imageInfos.length;

  for (size_t i = 0; i < app.lights.length; i++) {
    imageInfos ~= VkDescriptorImageInfo( // Assign directly to the single info struct
      imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      imageView: app.shadows.images[i].view, // Use the shadow map's image view
      sampler: app.sampler     // Use the shadow map's sampler
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
  vkResetCommandBuffer(app.shadowBuffers[syncIndex], 0); // Reset for recording

  VkCommandBufferBeginInfo beginInfo = {
      sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      pInheritanceInfo: null
  };
  enforceVK(vkBeginCommandBuffer(app.shadowBuffers[syncIndex], &beginInfo));
  app.nameVulkanObject(app.shadowBuffers[syncIndex], toStringz(format("[COMMANDBUFFER] Shadow %d", syncIndex)), VK_OBJECT_TYPE_COMMAND_BUFFER);

  if(app.trace) SDL_Log("Beginning shadow map render pass");

  VkClearValue clearDepth = { depthStencil: { depth: 1.0f, stencil: 0 } };

  pushLabel(app.shadowBuffers[syncIndex], "SSBO Buffering", Colors.lightgray);
  app.updateDescriptorData(app.shadows.shaders, app.shadowBuffers, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, syncIndex);
  popLabel(app.shadowBuffers[syncIndex]);

  pushLabel(app.shadowBuffers[syncIndex], "Objects Buffering", Colors.lightgray);
  app.bufferGeometries(app.shadowBuffers[syncIndex]);
  popLabel(app.shadowBuffers[syncIndex]);

  pushLabel(app.shadowBuffers[syncIndex], "Shadow Loop", Colors.lightgray);
  vkCmdBindDescriptorSets(app.shadowBuffers[syncIndex], VK_PIPELINE_BIND_POINT_GRAPHICS, 
                          app.shadows.pipeline.layout, 0, 1, &app.sets[Stage.SHADOWS][syncIndex], 0, null);

  for(size_t l = 0; l < app.lights.length; l++) {
    pushLabel(app.shadowBuffers[syncIndex], toStringz(format("Shadow RenderPass: %d", l)), Colors.lightgray);
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
    vkCmdBeginRenderPass(app.shadowBuffers[syncIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdBindPipeline(app.shadowBuffers[syncIndex], VK_PIPELINE_BIND_POINT_GRAPHICS, app.shadows.pipeline.pipeline);
    uint currentLightIndex = cast(uint)l;
    vkCmdPushConstants(app.shadowBuffers[syncIndex], app.shadows.pipeline.layout,
                       VK_SHADER_STAGE_VERTEX_BIT, 0, uint.sizeof, &currentLightIndex);
    for(size_t x = 0; x < app.objects.length; x++) {
      if(app.objects[x].isVisible && app.objects[x].topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST) {
        app.shadow(app.objects[x], syncIndex);
      }
    }
    vkCmdEndRenderPass(app.shadowBuffers[syncIndex]);
    popLabel(app.shadowBuffers[syncIndex]);
  }
  popLabel(app.shadowBuffers[syncIndex]);
  enforceVK(vkEndCommandBuffer(app.shadowBuffers[syncIndex])); // End recording for shadow map buffer
}

