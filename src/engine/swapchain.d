/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import surface : isSupported;

// Create a swapchain for IMGui
void createSwapChain(ref App app, VkSwapchainKHR oldChain = null) {
  VkCompositeAlphaFlagBitsKHR compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  version (Android) {
    auto x = app.isSupported(VK_FORMAT_R5G6B5_UNORM_PACK16);
    if(x >= 0){ app.format = cast(uint)x; SDL_Log("Using format: %d", app.format); }
    compositeAlpha = VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
  }

  VkSwapchainCreateInfoKHR swapchainCreateInfo = { // SwapChain CreateInfo
    sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
    surface: app.surface,
    minImageCount: app.camera.minImageCount,
    imageFormat: app.surfaceformats[app.format].format,
    imageColorSpace: app.surfaceformats[app.format].colorSpace,
    imageExtent: app.camera.currentExtent,
    imageArrayLayers: 1,
    imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    imageSharingMode: VK_SHARING_MODE_EXCLUSIVE,
    preTransform: app.camera.currentTransform,
    compositeAlpha: compositeAlpha,
    presentMode: VK_PRESENT_MODE_FIFO_KHR, // VK_PRESENT_MODE_IMMEDIATE_KHR or VK_PRESENT_MODE_FIFO_KHR
    clipped: VK_TRUE,
    oldSwapchain: oldChain,
  };

  enforceVK(vkCreateSwapchainKHR(app.device, &swapchainCreateInfo, app.allocator, &app.swapChain));
  if(app.verbose) SDL_Log("Swapchain %p created, requested %d images", app.swapChain, app.camera.minImageCount);
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
  if(app.trace) SDL_Log("imageView %p to %p created", imageView, image);
  return imageView;
}

// Aquire swapchain images
void aquireSwapChainImages(ref App app) {
  uint imageCount;
  vkGetSwapchainImagesKHR(app.device, app.swapChain, &imageCount, null);
  app.swapChainImages.length = imageCount;
  vkGetSwapchainImagesKHR(app.device, app.swapChain, &imageCount, &app.swapChainImages[0]);
  if(app.verbose) SDL_Log("SwapChain images: %d, Frames in flight: %d", app.imageCount, app.framesInFlight);

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
    app.swapChainImageViews[i] = app.createImageView(app.swapChainImages[i], app.surfaceformats[app.format].format);
  }
  if(app.verbose) SDL_Log("Swapchain image views: %d", app.swapChainImageViews.length);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.imageCount; i++) {
      vkDestroyImageView(app.device, app.swapChainImageViews[i], app.allocator);
    }
  });
}

