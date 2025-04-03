import includes;
import application : App;
import physicaldevice : pickPhysicalDevice;
import instance : createInstance, loadInstanceExtensions, addExtension, loadExtensionProperties, isExtensionAvailable;
import vkdebug : enforceVK, createDebugCallback;
import surface : createSurface, loadSurfaceCapabilities;
import logicaldevice : createLogicalDevice;

import swapchain : createSwapChain, aquireSwapChainImages;
import renderpass : createRenderPass;
import descriptorset : createDescriptorSetLayout, createDescriptorSets, createDescriptorPool;
import pipeline : createGraphicsPipeline;
import commands : createCommandPool, createCommandBuffers;
import depthbuffer : createDepthResources;
import framebuffer : createFramebuffers;
import uniformbuffer: createUniformBuffers;

void setupVulkan(ref App app, string vertPath = "data/shaders/vert.spv", string fragPath = "data/shaders/frag.spv") {
  app.loadInstanceExtensions();
  app.loadExtensionProperties();
  app.createInstance();
  app.createDebugCallback();
  app.pickPhysicalDevice();
  app.createSurface();
  app.loadSurfaceCapabilities();
  app.createLogicalDevice();

/*
  app.createSwapChain();
  app.aquireSwapChainImages();
  app.createRenderPass();
  app.createDescriptorSetLayout();
  app.createGraphicsPipeline(vertPath, fragPath);
  app.createCommandPool();
  app.createDepthResources();
  app.createFramebuffers();

  // Create objects

  app.createUniformBuffers();
  app.createDescriptorPool();
  app.createDescriptorSets();
  app.createCommandBuffers();
//  app.createSyncObjects();
*/

  // Create Descriptor Pool
  VkDescriptorPoolSize[] pool_sizes = [ { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE } ];
  uint maxSets = 0;
  for(int i = 0; i < pool_sizes.length; i++){
      VkDescriptorPoolSize pool_size = pool_sizes[i];
      maxSets += pool_size.descriptorCount;
  }

  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : maxSets,
    poolSizeCount : cast(uint32_t)pool_sizes.length,
    pPoolSizes : &pool_sizes[0]
  };
  vkCreateDescriptorPool(app.dev, &createPool, app.allocator, &app.descriptorPool);
  SDL_Log("Done with setupVulkan");
}

