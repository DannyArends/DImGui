/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : findMemoryType, hasStencilComponent;
import commands : beginSingleTimeCommands, endSingleTimeCommands;
import devices : getMSAASamples;
import framebuffer : createHDRImage;
import validation : nameVulkanObject;

VkDeviceSize imageSize(SDL_Surface* surface){ return(surface.w * surface.h * SDL_GetPixelFormatDetails(surface.format).bits_per_pixel / 8); }

struct ImageBuffer {
  VkImage image = null;             /// Image
  VkImageView view = null;          /// View
  VkDeviceMemory memory = null;     /// Memory
}

void nameImageBuffer(ref App app, ImageBuffer buffer, string path){
  app.nameVulkanObject(buffer.image, toStringz("[IMAGE] " ~ baseName(path)), VK_OBJECT_TYPE_IMAGE);
  app.nameVulkanObject(buffer.memory, toStringz("[MEMORY] " ~ baseName(path)), VK_OBJECT_TYPE_DEVICE_MEMORY);
  app.nameVulkanObject(buffer.view, toStringz("[VIEW] " ~ baseName(path)), VK_OBJECT_TYPE_IMAGE_VIEW);
}

/** DeAllocate an ImageBuffer / Texture
 */
void deAllocate(App app, ImageBuffer buffer) {
  vkDestroyImageView(app.device, buffer.view, app.allocator);
  vkDestroyImage(app.device, buffer.image, app.allocator);
  vkFreeMemory(app.device, buffer.memory, app.allocator);
}

void createColorResources(ref App app) {
  app.createHDRImage(app.offscreenHDR, app.getMSAASamples(), VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT);
  app.createHDRImage(app.resolvedHDR, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
}

/** Create & bind an Image on GPU backed with memory
 */
void createImage(ref App app, uint width, uint height, VkImage* image, VkDeviceMemory* imageMemory, 
                 VkFormat format = VK_FORMAT_R8G8B8A8_SRGB,
                 VkSampleCountFlagBits samples = VK_SAMPLE_COUNT_1_BIT,
                 VkImageTiling tiling = VK_IMAGE_TILING_OPTIMAL,
                 VkImageUsageFlags usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT, 
                 VkMemoryPropertyFlags properties = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, uint mipLevels = 1) {

  VkExtent3D extent = { width: width, height: height, depth: 1 };

  VkImageCreateInfo imageInfo = {
    sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
    imageType: VK_IMAGE_TYPE_2D,
    extent: extent,
    mipLevels: mipLevels,
    arrayLayers: 1,
    format: format,
    tiling: tiling,
    initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
    usage: usage,
    sharingMode: VK_SHARING_MODE_EXCLUSIVE,
    samples: samples,
    flags: 0
  };
  enforceVK(vkCreateImage(app.device, &imageInfo, null, image));

  VkMemoryRequirements memoryRequirements;
  vkGetImageMemoryRequirements(app.device, (*image), &memoryRequirements);

  VkMemoryAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    allocationSize: memoryRequirements.size,
    memoryTypeIndex: app.physicalDevice.findMemoryType(memoryRequirements.memoryTypeBits, properties)

  };
  if(app.trace) SDL_Log("createImage: Allocating %d Bytes", memoryRequirements.size);

  enforceVK(vkAllocateMemory(app.device, &allocInfo, null, imageMemory));
  vkBindImageMemory(app.device, (*image), (*imageMemory), 0);
}

void imageBarrier(VkCommandBuffer cmd, VkImage image,
                  VkImageLayout oldLayout, VkImageLayout newLayout,
                  VkAccessFlags srcAccess, VkAccessFlags dstAccess,
                  VkPipelineStageFlags srcStage, VkPipelineStageFlags dstStage,
                  uint baseMipLevel = 0, uint levelCount = 1,
                  VkImageAspectFlags aspectMask = VK_IMAGE_ASPECT_COLOR_BIT) {
  VkImageMemoryBarrier b = {
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    image: image,
    oldLayout: oldLayout,
    newLayout: newLayout,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    srcAccessMask: srcAccess,
    dstAccessMask: dstAccess,
    subresourceRange: { aspectMask: aspectMask, baseMipLevel: baseMipLevel, levelCount: levelCount, baseArrayLayer: 0, layerCount: 1 }
  };
  vkCmdPipelineBarrier(cmd, srcStage, dstStage, 0, 0, null, 0, null, 1, &b);
}

/** generateMipmaps
 */
void generateMipmaps(ref App app, VkCommandBuffer cmd, VkImage image, int width, int height, uint mipLevels) {
  int mipW = width, mipH = height;
  for (uint i = 1; i < mipLevels; i++) {
    imageBarrier(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                             VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT,
                             VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, i - 1);

    VkImageBlit blit = {
      srcOffsets: [VkOffset3D(0,0,0), VkOffset3D(mipW, mipH, 1)],
      srcSubresource: { aspectMask: VK_IMAGE_ASPECT_COLOR_BIT, mipLevel: i-1, baseArrayLayer: 0, layerCount: 1 },
      dstOffsets: [VkOffset3D(0,0,0), VkOffset3D(mipW>1?mipW/2:1, mipH>1?mipH/2:1, 1)],
      dstSubresource: { aspectMask: VK_IMAGE_ASPECT_COLOR_BIT, mipLevel: i, baseArrayLayer: 0, layerCount: 1 },
    };
    vkCmdBlitImage(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);

    imageBarrier(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                             VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_SHADER_READ_BIT,
                             VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, i - 1);

    if (mipW > 1) mipW /= 2;
    if (mipH > 1) mipH /= 2;
  }
  imageBarrier(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                           VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT,
                           VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, mipLevels - 1);
}

/** Transition Image Layout from old to new layout
 */
void transitionImageLayout(ref App app, VkCommandBuffer commandBuffer, VkImage image,
                           VkImageLayout oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, 
                           VkImageLayout newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                           VkFormat format = VK_FORMAT_R8G8B8A8_SRGB, uint levelCount = 1) {
  VkImageAspectFlags aspect = VK_IMAGE_ASPECT_COLOR_BIT;
  if (newLayout == VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
    aspect = VK_IMAGE_ASPECT_DEPTH_BIT;
    if (format.hasStencilComponent()) aspect |= VK_IMAGE_ASPECT_STENCIL_BIT;
  }

  VkAccessFlags srcAccess, dstAccess;
  VkPipelineStageFlags srcStage, dstStage;

  if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && (newLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL || newLayout == VK_IMAGE_LAYOUT_GENERAL)) {
    srcAccess = VK_ACCESS_NONE; dstAccess = VK_ACCESS_TRANSFER_WRITE_BIT;
    srcStage  = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT; dstStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
  } else if (oldLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
    srcAccess = VK_ACCESS_TRANSFER_WRITE_BIT; dstAccess = VK_ACCESS_SHADER_READ_BIT;
    srcStage  = VK_PIPELINE_STAGE_TRANSFER_BIT; dstStage  = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
  } else if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && newLayout == VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
    srcAccess = VK_ACCESS_NONE; dstAccess = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
    srcStage  = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT; dstStage = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
  } else if (oldLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_GENERAL) {
    srcAccess = VK_ACCESS_SHADER_READ_BIT; dstAccess = VK_ACCESS_SHADER_WRITE_BIT;
    srcStage  = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT; dstStage = VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
  } else if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
    srcAccess = VK_ACCESS_NONE; dstAccess = VK_ACCESS_SHADER_READ_BIT;
    srcStage  = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT; dstStage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
  } else if (oldLayout == VK_IMAGE_LAYOUT_GENERAL && newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
    srcAccess = VK_ACCESS_SHADER_WRITE_BIT; dstAccess = VK_ACCESS_SHADER_READ_BIT;
    srcStage  = VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT; dstStage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
  } else if (oldLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR && newLayout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL) {
    srcAccess = VK_ACCESS_MEMORY_READ_BIT; dstAccess = VK_ACCESS_TRANSFER_READ_BIT;
    srcStage  = VK_PIPELINE_STAGE_TRANSFER_BIT; dstStage  = VK_PIPELINE_STAGE_TRANSFER_BIT;
  } else if (oldLayout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) {
    srcAccess = VK_ACCESS_TRANSFER_READ_BIT; dstAccess = VK_ACCESS_MEMORY_READ_BIT;
    srcStage  = VK_PIPELINE_STAGE_TRANSFER_BIT; dstStage  = VK_PIPELINE_STAGE_TRANSFER_BIT;
  } else {
    SDL_Log("unsupported layout transition!");
    return;
  }

  imageBarrier(commandBuffer, image, oldLayout, newLayout, srcAccess, dstAccess, srcStage, dstStage, 0, levelCount, aspect);
  if (app.trace) SDL_Log(" - transitionImageLayout finished for commandBuffer[%p]", commandBuffer);
}