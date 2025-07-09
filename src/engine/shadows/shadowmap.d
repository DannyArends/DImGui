/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import bone : getBoneOffsets;
import color : Colors;
import descriptor : Descriptor, createDescriptorSetLayout, createDescriptorSet, updateDescriptorSet;
import images : createImage, transitionImageLayout;
import lights : Light;
import matrix : Matrix, orthogonal, perspective, multiply, lookAt;
import pipeline : GraphicsPipeline;
import geometry : shadow, Instance;
import reflection : reflectShaders, createResources;
import ssbo : updateSSBO;
import shaders : Shader, createStageInfo, createShaderModule;
import swapchain : createImageView;
import validation : pushLabel, popLabel;
import vector : normalize, vAdd;
import vertex : Vertex, VERTEX, INSTANCE;

struct ShadowMap {
  VkImage image;
  VkImageView imageView;
  VkDeviceMemory memory;
  VkSampler sampler;
  VkRenderPass renderPass;
  VkFramebuffer framebuffer;
  Shader[] shaders;
  GraphicsPipeline pipeline;

  VkFormat format = VK_FORMAT_D32_SFLOAT;
  uint dimension = 2048; // Or 1024, 4096, etc. - resolution of your shadow map
}

struct LightUbo {
  Matrix lightSpaceMatrix;
  Matrix scene;
  uint nlights;
};

void createShadowMap(ref App app) {
  app.createShadowMapResources();
  app.createShadowMapRenderPass();
  app.createShadowMapFramebuffer();
  app.createShadowShader();
}

/** 
 * Shadow map resource creation
 */
void createShadowMapResources(ref App app) {
  if(app.verbose) SDL_Log("Shadow map resources creation");

  app.createImage(app.shadows.dimension, app.shadows.dimension,
                  &app.shadows.image, &app.shadows.memory,
                  app.shadows.format, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL,
                  VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
  if(app.verbose) SDL_Log(" - shadow map image created: %p", app.shadows.image);

  app.shadows.imageView = app.createImageView(app.shadows.image, app.shadows.format, VK_IMAGE_ASPECT_DEPTH_BIT);
  if(app.verbose) SDL_Log(" - shadow map image view created: %p", app.shadows.imageView);

  VkSamplerCreateInfo samplerInfo = {
    sType: VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
    magFilter: VK_FILTER_LINEAR, // For soft edges with PCF
    minFilter: VK_FILTER_LINEAR,
    addressModeU: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
    addressModeV: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
    addressModeW: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
    borderColor: VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE, // Important: white means 'outside shadow'
    unnormalizedCoordinates: VK_FALSE,
    compareEnable: VK_TRUE, // Enable hardware depth comparison
    compareOp: VK_COMPARE_OP_LESS_OR_EQUAL, // For shadow mapping
    mipmapMode: VK_SAMPLER_MIPMAP_MODE_NEAREST, // No mipmaps for single depth map
    mipLodBias: 0.0f,
    minLod: 0.0f,
    maxLod: 0.0f,
    anisotropyEnable: VK_FALSE, // Not typically used for depth maps
    maxAnisotropy: 1.0f
  };

  enforceVK(vkCreateSampler(app.device, &samplerInfo, app.allocator, &app.shadows.sampler));
  if(app.verbose) SDL_Log(" - shadow map sampler created: %p", app.shadows.sampler);

  app.mainDeletionQueue.add((){
      vkDestroySampler(app.device, app.shadows.sampler, app.allocator);
      vkFreeMemory(app.device, app.shadows.memory, app.allocator);
      vkDestroyImageView(app.device, app.shadows.imageView, app.allocator);
      vkDestroyImage(app.device, app.shadows.image, app.allocator);
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

  VkAttachmentReference depthAttachmentRef = {
    attachment: 0,
    layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
  };

  VkSubpassDescription subpass = {
    pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
    colorAttachmentCount: 0,
    pDepthStencilAttachment: &depthAttachmentRef
  };

  VkSubpassDependency dependency = {
    srcSubpass: VK_SUBPASS_EXTERNAL,
    dstSubpass: 0,
    srcStageMask: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
    dstStageMask: VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
    srcAccessMask: VK_ACCESS_SHADER_READ_BIT,
    dstAccessMask: VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
    dependencyFlags: 0
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

/** 
 * Shadow map framebuffer creation
 */
void createShadowMapFramebuffer(ref App app) {
  if(app.verbose) SDL_Log("Shadow map framebuffer creation");

  VkImageView[] attachments = [ app.shadows.imageView ];

  VkFramebufferCreateInfo framebufferInfo = {
    sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
    renderPass: app.shadows.renderPass,
    attachmentCount: cast(uint)attachments.length,
    pAttachments: &attachments[0],
    width: app.shadows.dimension,
    height: app.shadows.dimension,
    layers: 1
  };

  enforceVK(vkCreateFramebuffer(app.device, &framebufferInfo, app.allocator, &app.shadows.framebuffer));
  if(app.verbose) SDL_Log("Shadow map framebuffer created.");

  app.mainDeletionQueue.add((){ vkDestroyFramebuffer(app.device, app.shadows.framebuffer, app.allocator); });
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

  VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    setLayoutCount: 1,
    pSetLayouts: &app.layouts[SHADOWS],
  };

  enforceVK(vkCreatePipelineLayout(app.device, &pipelineLayoutInfo, app.allocator, &app.shadows.pipeline.layout));
  if(app.verbose) SDL_Log(" - shadow map pipeline layout created: %p", app.shadows.pipeline.layout);

  auto stages = createStageInfo(app.shadows.shaders);

  VkVertexInputBindingDescription[] bindingDescription = [
    {binding: VERTEX, stride: cast(uint) Vertex.sizeof, inputRate: VK_VERTEX_INPUT_RATE_VERTEX },
    {binding: INSTANCE, stride: Instance.sizeof, inputRate: VK_VERTEX_INPUT_RATE_INSTANCE }
  ];

  VkVertexInputAttributeDescription[]  attributeDescriptions= [ 
    {binding: VERTEX, location: 0, format: VK_FORMAT_R32G32B32_SFLOAT, offset: Vertex.position.offsetof },
    {binding: VERTEX, location: 1, format: VK_FORMAT_R32G32B32A32_UINT, offset: Vertex.bones.offsetof },
    {binding: VERTEX, location: 2, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Vertex.weights.offsetof },

    {binding: INSTANCE, location: 3, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof },
    {binding: INSTANCE, location: 4, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof + 4 * float.sizeof },
    {binding: INSTANCE, location: 5, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof + 8 * float.sizeof },
    {binding: INSTANCE, location: 6, format: VK_FORMAT_R32G32B32A32_SFLOAT, offset: Instance.matrix.offsetof + 12 * float.sizeof }
  ];

  VkPipelineVertexInputStateCreateInfo vertexInputInfo = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    vertexBindingDescriptionCount: cast(uint)bindingDescription.length,
    pVertexBindingDescriptions: &bindingDescription[0],
    vertexAttributeDescriptionCount: cast(uint)attributeDescriptions.length,
    pVertexAttributeDescriptions: attributeDescriptions.ptr,
  };

  VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    primitiveRestartEnable: VK_FALSE,
  };

  VkViewport viewport = {
    x: 0.0f, y: 0.0f,
    width: cast(float)app.shadows.dimension,
    height: cast(float)app.shadows.dimension,
    minDepth: 0.0f, maxDepth: 1.0f,
  };

  VkRect2D scissor = {
    offset: { x: 0, y: 0 },
    extent: { width: app.shadows.dimension, height: app.shadows.dimension },
  };

  VkPipelineViewportStateCreateInfo viewportState = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    viewportCount: 1,
    pViewports: &viewport,
    scissorCount: 1,
    pScissors: &scissor
  };

  VkPipelineRasterizationStateCreateInfo rasterizer = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    depthClampEnable: VK_FALSE,
    polygonMode: VK_POLYGON_MODE_FILL,
    lineWidth: 1.0f,
    cullMode: VK_CULL_MODE_NONE,
    frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE,
    depthBiasEnable: VK_TRUE,
    depthBiasConstantFactor: 1.25f,
    depthBiasClamp: 0.0f,
    depthBiasSlopeFactor: 1.75f
  };

  VkPipelineMultisampleStateCreateInfo multisampling = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    sampleShadingEnable: VK_FALSE,
    rasterizationSamples: VK_SAMPLE_COUNT_1_BIT
  };

  VkPipelineDepthStencilStateCreateInfo depthStencil = {
    sType: VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    depthTestEnable: VK_TRUE,
    depthWriteEnable: VK_TRUE,
    depthCompareOp: VK_COMPARE_OP_LESS_OR_EQUAL,
    depthBoundsTestEnable: VK_FALSE,
    stencilTestEnable: VK_FALSE
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

LightUbo computeLightSpace(ref App app, Light light){
  float[3] lightPos = light.position[0 .. 3];
  float[3] lightDir = light.direction[0 .. 3].normalize();
  float[3] lightTarget = lightPos.vAdd(lightDir);
  float[3] upVector = [0.0f, 1.0f, 0.0f];

  Matrix lightView = lookAt(lightPos, lightTarget, upVector);

  float fovY = 2 * light.properties[2];
  float nearPlane = 10.0f;
  float farPlane = 100.0f;
  Matrix lightProjection = perspective(fovY, 1.0f, nearPlane, farPlane);
  LightUbo ubo = {
    lightSpaceMatrix : lightProjection.multiply(lightView),
    scene : Matrix.init,
    nlights : cast(uint)app.lights.length
  };
  return(ubo);
}

void updateShadowMapUBO(ref App app, Light light, uint syncIndex) {
  auto ubo = app.computeLightSpace(light);

  for(uint s = 0; s < app.shadows.shaders.length; s++) {
    auto shader = app.shadows.shaders[s];
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
        memcpy(app.ubos[shader.descriptors[d].base].data[syncIndex], &ubo, shader.descriptors[d].bytes);
      }
    }
  }
  if(app.verbose) SDL_Log("Light space matrix updated for frame %d", app.totalFramesRendered);
}

void writeShadowMap(App app, ref VkWriteDescriptorSet[] write, Descriptor descriptor, VkDescriptorSet dst, ref VkDescriptorImageInfo[] imageInfos){
  imageInfos ~= VkDescriptorImageInfo( // Assign directly to the single info struct
    imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    imageView: app.shadows.imageView, // Use the shadow map's image view
    sampler: app.shadows.sampler     // Use the shadow map's sampler
  );
  VkWriteDescriptorSet set = {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: dst,
    dstBinding: descriptor.binding,
    dstArrayElement: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount: 1, // Crucial: Only 1 descriptor for the single shadow map
    pImageInfo: &imageInfos[($-1)] // Point to the single info struct
  }; 
  write ~= set;
}

void createShadowMapCommandBuffers(ref App app) {
  SDL_Log("Creating %d shadow map command buffers", app.framesInFlight);
  app.shadowBuffers.length = app.framesInFlight;
  VkCommandBufferAllocateInfo allocInfo = {
      sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      commandPool: app.commandPool, // Use your main graphics command pool
      level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      commandBufferCount: app.framesInFlight,
  };

  enforceVK(vkAllocateCommandBuffers(app.device, &allocInfo, &app.shadowBuffers[0]));
  if(app.verbose) SDL_Log(" - shadow map command buffers allocated.");

  // Add to main deletion queue for cleanup
  app.frameDeletionQueue.add((){
    vkFreeCommandBuffers(app.device, app.commandPool, cast(uint)app.shadowBuffers.length, &app.shadowBuffers[0]);
  });
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

  VkRenderPassBeginInfo renderPassInfo = {
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass: app.shadows.renderPass,
    framebuffer: app.shadows.framebuffer,
    renderArea: {
        offset: { x: 0, y: 0 },
        extent: { width: app.shadows.dimension, height: app.shadows.dimension }
    },
    clearValueCount: 1,
    pClearValues: &clearDepth,
  };

  pushLabel(app.shadowBuffers[app.syncIndex], "SSBO Buffering", Colors.lightgray);
  VkBuffer dst;
  uint size;
  foreach(shader; app.shadows.shaders){
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
        if(SDL_strstr(shader.descriptors[d].base, "BoneMatrices") != null) { 
          dst = app.buffers[shader.descriptors[d].base].buffers[syncIndex];
          Matrix[] offsets = app.getBoneOffsets();
          app.updateSSBO!Matrix(app.shadowBuffers[syncIndex], offsets, shader.descriptors[d], syncIndex);
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

  pushLabel(app.shadowBuffers[app.syncIndex], "Shadow RenderPass", Colors.lightgray);
  vkCmdBeginRenderPass(app.shadowBuffers[app.syncIndex], &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
  vkCmdBindPipeline(app.shadowBuffers[app.syncIndex], VK_PIPELINE_BIND_POINT_GRAPHICS, app.shadows.pipeline.pipeline);
  for(size_t x = 0; x < app.objects.length; x++) {
    if(app.objects[x].isVisible && app.objects[x].topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST){
      app.shadow(app.objects[x], syncIndex);
    }
  }
  vkCmdEndRenderPass(app.shadowBuffers[app.syncIndex]);
  popLabel(app.shadowBuffers[app.syncIndex]);

  enforceVK(vkEndCommandBuffer(app.shadowBuffers[app.syncIndex])); // End recording for shadow map buffer
}

