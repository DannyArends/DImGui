import includes;
import application : App;
import vkdebug : enforceVK;
import uniformbuffer : UniformBufferObject;

struct Descriptor {
  VkDescriptorPool descriptorPool;
  VkDescriptorSet[] descriptorSets;
  VkDescriptorSetLayout descriptorSetLayout;
  VkDescriptorSetLayout[] layouts;
}

void createDescriptorSets(ref App app) {
  if(app.textureArray.length == 0){
    SDL_Log("No texture, skipping DescriptorSet creation");
    return;
  }
  app.descriptor.layouts.length = app.textureArray.length;
  for (size_t i = 0; i < app.textureArray.length; i++) {
     app.descriptor.layouts[i] = app.descriptor.descriptorSetLayout;
  }
  VkDescriptorSetAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    descriptorPool: app.descriptor.descriptorPool,
    descriptorSetCount: cast(uint)(app.textureArray.length),
    pSetLayouts: &app.descriptor.layouts[0]
  };
  
  app.descriptor.descriptorSets.length = app.textureArray.length;
  enforceVK(vkAllocateDescriptorSets(app.dev, &allocInfo, &app.descriptor.descriptorSets[0]));

  VkDescriptorBufferInfo bufferInfo = {
    buffer: app.uniform.uniformBuffers[0],
    offset: 0,
    range: UniformBufferObject.sizeof
  };

  for (size_t i = 0; i < app.textureArray.length; i++) {
    VkDescriptorImageInfo img = {
      imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      imageView: app.textureArray[i].textureImageView, // Texture 0 is reserved for font
      sampler: app.textureSampler
    };
    SDL_Log("wrote textures %d", app.textureArray.length);

    VkWriteDescriptorSet[2] descriptorWrites = [
      {
        sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        dstSet: app.descriptor.descriptorSets[i],
        dstBinding: 0,
        dstArrayElement: 0,
        descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        descriptorCount: 1,
        pBufferInfo: &bufferInfo,
        pImageInfo: null,
        pTexelBufferView: null
      },
      {
        sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        dstSet: app.descriptor.descriptorSets[i],
        dstBinding: 1,
        dstArrayElement: 0,
        descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        descriptorCount: 1,
        pImageInfo: &img
      }
    ];
    vkUpdateDescriptorSets(app.dev, descriptorWrites.length, &descriptorWrites[0], 0, null);
    SDL_Log("wrote descriptor %d", i);
  }
  SDL_Log("createDescriptorSets");
}

void createDescriptorSetLayout(ref App app) {
  SDL_Log("creating DescriptorSetLayout");
  VkDescriptorSetLayoutBinding uboLayoutBinding = {
    binding: 0,
    descriptorCount: 1,
    descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    pImmutableSamplers: null,
    stageFlags: VK_SHADER_STAGE_VERTEX_BIT
  };

  VkDescriptorSetLayoutBinding samplerLayoutBinding = {
    binding: 1,
    descriptorCount: 1,
    descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    pImmutableSamplers: null,
    stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT
  };
  
  VkDescriptorSetLayoutBinding[2] bindings = [uboLayoutBinding, samplerLayoutBinding];

  VkDescriptorSetLayoutCreateInfo layoutInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    bindingCount: bindings.length,
    pBindings: &bindings[0]
  };
  enforceVK(vkCreateDescriptorSetLayout(app.dev, &layoutInfo, null, &app.descriptor.descriptorSetLayout));
  SDL_Log("created DescriptorSetLayout");
}


void createDescriptorPool(ref App app) {
  if(app.textureArray.length == 0){
    SDL_Log("No texture, skipping DescriptorPool creation");
    return;
  }
  VkDescriptorPoolSize[2] poolSizes = [
    { type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: cast(uint)(app.textureArray.length) },
    { type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, descriptorCount: cast(uint)(app.textureArray.length) },
  ];

  VkDescriptorPoolCreateInfo poolInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    poolSizeCount: poolSizes.length,
    pPoolSizes: &poolSizes[0],
    maxSets: cast(uint)(app.textureArray.length)
  };
  
  enforceVK(vkCreateDescriptorPool(app.dev, &poolInfo, null, &app.descriptor.descriptorPool));
  SDL_Log("created DescriptorPool");
}

