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

VkDeviceSize imageSize(SDL_Surface* surface){ return(surface.w * surface.h * (surface.format.BitsPerPixel / 8)); }

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

void writeHDRSampler(App app, ref VkWriteDescriptorSet[] write, Descriptor descriptor, VkDescriptorSet dst, ref VkDescriptorImageInfo[] imageInfos){
imageInfos ~= VkDescriptorImageInfo(
    imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    imageView: app.resolvedHDR.view,
    sampler: app.sampler
  );

  VkWriteDescriptorSet set = {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: dst,
    dstBinding: descriptor.binding,
    dstArrayElement: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount: cast(uint)1,
    pImageInfo: &imageInfos[($-1)]
  };
  write ~= set;
}

void createImage(ref App app, uint width, uint height, VkImage* image, VkDeviceMemory* imageMemory, 
                 VkFormat format = VK_FORMAT_R8G8B8A8_SRGB,
                 VkSampleCountFlagBits samples = VK_SAMPLE_COUNT_1_BIT,
                 VkImageTiling tiling = VK_IMAGE_TILING_OPTIMAL,
                 VkImageUsageFlags usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT, 
                 VkMemoryPropertyFlags properties = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {

  VkExtent3D extent = { width: width, height: height, depth: 1 };

  VkImageCreateInfo imageInfo = {
    sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
    imageType: VK_IMAGE_TYPE_2D,
    extent: extent,
    mipLevels: 1,
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

/** Transition Image Layout from old to new layout
 */
void transitionImageLayout(ref App app, VkCommandBuffer commandBuffer, VkImage image,
                           VkImageLayout oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, 
                           VkImageLayout newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                           VkFormat format = VK_FORMAT_R8G8B8A8_SRGB) {
  VkImageSubresourceRange subresourceRange = {
    aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
    baseMipLevel: 0,
    levelCount: 1,
    baseArrayLayer: 0,
    layerCount: 1,
  };

  if (newLayout == VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
    subresourceRange.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
    if(format.hasStencilComponent()) { subresourceRange.aspectMask |= VK_IMAGE_ASPECT_STENCIL_BIT; }
  } else {
    subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  }
  
  VkImageMemoryBarrier barrier = {
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    oldLayout: oldLayout,
    newLayout: newLayout,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: image,
    subresourceRange: subresourceRange,
  };

  VkPipelineStageFlags sourceStage;
  VkPipelineStageFlags destinationStage;

  if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && (newLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL || newLayout == VK_IMAGE_LAYOUT_GENERAL)) {
    barrier.srcAccessMask = VK_ACCESS_NONE;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

    sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    destinationStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
  } else if (oldLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    sourceStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
    destinationStage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
  } else if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && newLayout == VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
    barrier.srcAccessMask = VK_ACCESS_NONE;
    barrier.dstAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

    sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    destinationStage = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
  } else if (oldLayout == VK_IMAGE_LAYOUT_GENERAL && newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
    barrier.srcAccessMask = VK_ACCESS_NONE;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

    sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    destinationStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
  } else {
    SDL_Log("unsupported layout transition!");
  }

  vkCmdPipelineBarrier(commandBuffer, sourceStage, destinationStage, 0, 0, null, 0, null, 1, &barrier);
  if(app.trace) SDL_Log(" - transitionImageLayout finished for commandBuffer[%p]", commandBuffer);
}
