import engine;

import images : createImage,transitionImageLayout;
import swapchain : createImageView;

struct DepthBuffer {
  VkImage depthImage;
  VkDeviceMemory depthImageMemory;
  VkImageView depthImageView;
}

void destroyDepthBuffer(ref App app) {
  vkFreeMemory(app.device, app.depthbuffer.depthImageMemory, app.allocator);
  vkDestroyImageView(app.device, app.depthbuffer.depthImageView, app.allocator);
  vkDestroyImage(app.device, app.depthbuffer.depthImage, app.allocator);
}

VkFormat findSupportedFormat(ref App app, const VkFormat[] candidates, VkImageTiling tiling, VkFormatFeatureFlags features) {
  foreach(VkFormat format; candidates) {
    VkFormatProperties props;
    vkGetPhysicalDeviceFormatProperties(app.physicalDevice, format, &props);
    if (tiling == VK_IMAGE_TILING_LINEAR && (props.linearTilingFeatures & features) == features) {
      return format;
    } else if (tiling == VK_IMAGE_TILING_OPTIMAL && (props.optimalTilingFeatures & features) == features) {
      return format;
    }
  }
  assert(0, "failed to find supported format!");
}

VkFormat findDepthFormat(ref App app) {
  return app.findSupportedFormat(
    [VK_FORMAT_D32_SFLOAT, VK_FORMAT_D32_SFLOAT_S8_UINT, VK_FORMAT_D24_UNORM_S8_UINT],
    VK_IMAGE_TILING_OPTIMAL,
    VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT
  );
}

void createDepthResources(ref App app) {
  SDL_Log("Depth resources creation");
  VkFormat depthFormat = app.findDepthFormat();
  SDL_Log(" - depthFormat: %d", depthFormat);
  app.createImage(app.width, app.height, &app.depthbuffer.depthImage, &app.depthbuffer.depthImageMemory, 
                  depthFormat, VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, 
                  VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
  SDL_Log(" - image created: %p", app.depthbuffer.depthImage);
  app.depthbuffer.depthImageView = app.createImageView(app.depthbuffer.depthImage, depthFormat, VK_IMAGE_ASPECT_DEPTH_BIT);
  SDL_Log(" - image view created: %p", app.depthbuffer.depthImageView);
  app.transitionImageLayout(app.depthbuffer.depthImage, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL, depthFormat);
  SDL_Log("Depth resources created");
}

