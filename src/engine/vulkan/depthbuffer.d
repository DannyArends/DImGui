/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import commands : beginSingleTimeCommands, endSingleTimeCommands;
import devices : getMSAASamples;
import images : cleanup, transitionImageLayout, createNamedImage;

alias ImageBuffer DepthBuffer;

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
  VkFormat fmt = app.findDepthFormat();
  if(app.verbose) SDL_Log(" - depthFormat: %d", fmt);
  app.createNamedImage(app.depthBuffer, app.camera.width, app.camera.height, fmt, VK_IMAGE_ASPECT_DEPTH_BIT, "DepthBuffer",
                       app.getMSAASamples(), VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT);
  if(app.verbose) SDL_Log(" - image created: %p", app.depthBuffer.image);

  auto cmd = app.beginSingleTimeCommands(app.commandPool);
  app.transitionImageLayout(cmd, app.depthBuffer.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL, fmt);
  app.endSingleTimeCommands(cmd, app.queue);
  if(app.verbose) SDL_Log("Depth resources created");
  app.swapDeletionQueue.add((){ app.cleanup(app.depthBuffer); });
}

