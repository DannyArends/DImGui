// Copyright Danny Arends 2025
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

import engine;

import images : createImage,transitionImageLayout;
import swapchain : createImageView;

struct DepthBuffer {
  VkImage depthImage;
  VkDeviceMemory depthImageMemory;
  VkImageView depthImageView;
}

void destroyDepthBuffer(ref App app) {
  vkFreeMemory(app.device, app.depthBuffer.depthImageMemory, app.allocator);
  vkDestroyImageView(app.device, app.depthBuffer.depthImageView, app.allocator);
  vkDestroyImage(app.device, app.depthBuffer.depthImage, app.allocator);
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
  if(app.verbose) SDL_Log("Depth resources creation");
  VkFormat depthFormat = app.findDepthFormat();
  if(app.verbose) SDL_Log(" - depthFormat: %d", depthFormat);
  app.createImage(app.camera.width, app.camera.height, &app.depthBuffer.depthImage, &app.depthBuffer.depthImageMemory, 
                  depthFormat, VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT);
  if(app.verbose) SDL_Log(" - image created: %p", app.depthBuffer.depthImage);
  app.depthBuffer.depthImageView = app.createImageView(app.depthBuffer.depthImage, depthFormat, VK_IMAGE_ASPECT_DEPTH_BIT);
  if(app.verbose) SDL_Log(" - image view created: %p", app.depthBuffer.depthImageView);
  app.transitionImageLayout(app.depthBuffer.depthImage, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL, depthFormat);
  if(app.verbose) SDL_Log("Depth resources created");
}

