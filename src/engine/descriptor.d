import engine;

import uniforms : UniformBufferObject;

void createImGuiDescriptorPool(ref App app){
  if(app.verbose) SDL_Log("create ImGui DescriptorPool");
  VkDescriptorPoolSize[] poolSizes = [
    {
      type : VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      descriptorCount : IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE
    }
  ];

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : 1,
    poolSizeCount : cast(uint32_t)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.imguiPool));
}

void createDescriptorPool(ref App app){
  if(app.verbose) SDL_Log("create Render DescriptorPool, images: %d", app.imageCount);
  VkDescriptorPoolSize[] poolSizes = [
    { type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: cast(uint)(app.imageCount) },
  ];

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : app.imageCount,
    poolSizeCount : cast(uint32_t)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.descriptorPool));
}

void createDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating DescriptorSetLayout");
  VkDescriptorSetLayoutBinding uboLayoutBinding = {
    binding: 0,
    descriptorCount: 1,
    descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    pImmutableSamplers: null,
    stageFlags: VK_SHADER_STAGE_VERTEX_BIT
  };

  VkDescriptorSetLayoutBinding[1] bindings = [uboLayoutBinding];

  VkDescriptorSetLayoutCreateInfo layoutInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    bindingCount: bindings.length,
    pBindings: &bindings[0]
  };
  enforceVK(vkCreateDescriptorSetLayout(app.device, &layoutInfo, null, &app.descriptorSetLayout));
}

void createDescriptorSet(ref App app) {
  if(app.verbose) SDL_Log("creating DescriptorSets, copy layout");
  VkDescriptorSetLayout[] layouts;
  layouts.length = app.imageCount;
  for (size_t i = 0; i < app.imageCount; i++) {
     layouts[i] = app.descriptorSetLayout;
  }

  app.descriptorSets.length = app.imageCount;

  VkDescriptorSetAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    descriptorPool: app.descriptorPool,
    descriptorSetCount: app.imageCount,
    pSetLayouts: &layouts[0]
  };
  if(app.verbose) SDL_Log("Allocating %d DescriptorSets", app.imageCount);
  enforceVK(vkAllocateDescriptorSets(app.device, &allocInfo, &app.descriptorSets[0]));

  if(app.verbose) SDL_Log("Update %d DescriptorSets", app.imageCount);
  for (size_t i = 0; i <  app.imageCount; i++) {
    VkDescriptorBufferInfo bufferInfo = {
      buffer: app.uniform.uniformBuffers[0],
      offset: 0,
      range: UniformBufferObject.sizeof
    };

    VkWriteDescriptorSet[1] descriptorWrites = [
      {
        sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        dstSet: app.descriptorSets[i],
        dstBinding: 0,
        dstArrayElement: 0,
        descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        descriptorCount: 1,
        pBufferInfo: &bufferInfo,
        pImageInfo: null,
        pTexelBufferView: null
      },
    ];
    vkUpdateDescriptorSets(app.device, descriptorWrites.length, &descriptorWrites[0], 0, null);
  }
}

