import engine;

// Create a swapchain for IMGui
void createSwapChain(ref App app, VkSwapchainKHR oldChain = null) {
  VkSwapchainCreateInfoKHR swapchainCreateInfo = { // SwapChain CreateInfo
    sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
    surface: app.surface,
    minImageCount: app.camera.minImageCount,
    imageFormat: app.surfaceformats[0].format,
    imageColorSpace: app.surfaceformats[0].colorSpace,
    imageExtent: app.camera.currentExtent,
    imageArrayLayers: 1,
    imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    imageSharingMode: VK_SHARING_MODE_EXCLUSIVE,
    preTransform: app.camera.currentTransform,
    compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    presentMode: VK_PRESENT_MODE_FIFO_KHR,
    clipped: VK_TRUE,
    oldSwapchain: oldChain,
  };

  enforceVK(vkCreateSwapchainKHR(app.device, &swapchainCreateInfo, app.allocator, &app.swapChain));
  if(app.verbose) SDL_Log("Swapchain %p created, minImage:%d", app.swapChain, app.camera.minImageCount);
  if(oldChain) { vkDestroySwapchainKHR(app.device, oldChain, app.allocator); }
}

// Create an ImageView to a VkImage
VkImageView createImageView(App app, VkImage image, VkFormat format, VkImageAspectFlags aspectMask = VK_IMAGE_ASPECT_COLOR_BIT) {
  VkImageSubresourceRange subresourceRange = {
    aspectMask: aspectMask,
    baseMipLevel: 0,
    levelCount: 1,
    baseArrayLayer: 0,
    layerCount: 1,
  };

  VkImageViewCreateInfo viewInfo = {
    sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    image: image,
    viewType: VK_IMAGE_VIEW_TYPE_2D,
    format: format,
    subresourceRange: subresourceRange
  };
  VkImageView imageView;
  enforceVK(vkCreateImageView(app.device, &viewInfo, null, &imageView));
  if(app.verbose) SDL_Log("imageView %p to %p created", imageView, image);
  return imageView;
}

// Aquire swapchain images
void aquireSwapChainImages(ref App app) {
  uint imageCount;
  vkGetSwapchainImagesKHR(app.device, app.swapChain, &imageCount, null);
  app.swapChainImages.length = imageCount;
  vkGetSwapchainImagesKHR(app.device, app.swapChain, &imageCount, &app.swapChainImages[0]);
  if(app.verbose) SDL_Log("Swapchain images: %d", app.imageCount);

  VkComponentMapping components = {
    r: VK_COMPONENT_SWIZZLE_IDENTITY,
    g: VK_COMPONENT_SWIZZLE_IDENTITY,
    b: VK_COMPONENT_SWIZZLE_IDENTITY,
    a: VK_COMPONENT_SWIZZLE_IDENTITY,
  };
  
  VkImageSubresourceRange subresourceRange = {
    aspectMask: VK_IMAGE_ASPECT_COLOR_BIT, baseMipLevel: 0, levelCount: 1, baseArrayLayer: 0, layerCount: 1
  };

  // Allocate space for an imageview per image & create the imageviews
  app.swapChainImageViews.length = app.imageCount;
  for (uint i = 0; i < app.imageCount; i++) {
    app.swapChainImageViews[i] = app.createImageView(app.swapChainImages[i], app.surfaceformats[0].format);
  }
  if(app.verbose) SDL_Log("Swapchain image views: %d", app.swapChainImageViews.length);
}

