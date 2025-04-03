import includes;
import application : App;
import images : createImageView;
import vkdebug : enforceVK;

struct SwapChain {
  VkImage[] swapChainImages;
  VkImageView[] swapChainImageViews;

  VkSwapchainKHR swapChain;
  alias swapChain this;

  VkRenderPass renderpass;
  VkCommandPool commandPool;

  VkImage depthImage;
  VkDeviceMemory depthImageMemory;
  VkImageView depthImageView;

  VkFramebuffer[] swapChainFramebuffers;

  SwapChain* oldChain;
}

// Create a swapchain for IMGui (Currently not used)
void createSwapChain(ref App app, SwapChain* oldChain = null) {
  SwapChain swapchain = { oldChain: oldChain };

  //SwapChain creation
  VkSwapchainCreateInfoKHR swapchainCreateInfo = {
    sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
    surface: app.surface,
    minImageCount: app.surface.capabilities.minImageCount,
    imageFormat: app.surface.surfaceformats[0].format,
    imageColorSpace: app.surface.surfaceformats[0].colorSpace,
    imageExtent: app.surface.capabilities.currentExtent,
    imageArrayLayers: 1,
    imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    imageSharingMode: VK_SHARING_MODE_EXCLUSIVE,
    preTransform: app.surface.capabilities.currentTransform,
    compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    presentMode: VK_PRESENT_MODE_FIFO_KHR,
    clipped: VK_TRUE,
    oldSwapchain: null,
  };

  enforceVK(vkCreateSwapchainKHR(app.dev, &swapchainCreateInfo, app.allocator, &swapchain.swapChain));
  SDL_Log("Swapchain created, minImage:%d", app.surface.capabilities.minImageCount);
  app.swapchain = swapchain;
}

// Aquire swapchain images
void aquireSwapChainImages(ref App app) {
  uint imageCount;
  vkGetSwapchainImagesKHR(app.dev, app.swapchain.swapChain, &imageCount, null);
  app.swapchain.swapChainImages.length = imageCount;
  vkGetSwapchainImagesKHR(app.dev, app.swapchain.swapChain, &imageCount, &app.swapchain.swapChainImages[0]);
  SDL_Log("Swapchain images: %d", imageCount);

  // Allocate space for an imageview per image
  app.swapchain.swapChainImageViews.length = app.swapchain.swapChainImages.length;

  VkComponentMapping components = {
    r: VK_COMPONENT_SWIZZLE_IDENTITY,
    g: VK_COMPONENT_SWIZZLE_IDENTITY,
    b: VK_COMPONENT_SWIZZLE_IDENTITY,
    a: VK_COMPONENT_SWIZZLE_IDENTITY,
  };
  
  VkImageSubresourceRange subresourceRange = {
    aspectMask: VK_IMAGE_ASPECT_COLOR_BIT, baseMipLevel: 0, levelCount: 1, baseArrayLayer: 0, layerCount: 1
  };

  for (size_t i = 0; i < app.swapchain.swapChainImages.length; i++) {
    app.swapchain.swapChainImageViews[i] = app.createImageView(app.swapchain.swapChainImages[i], app.surface.surfaceformats[0].format);
  }
  SDL_Log("Swapchain image views: %d", app.swapchain.swapChainImageViews.length);
}

