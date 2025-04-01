import includes;
import application : App;
import vkdebug : enforceVK;

// createImageView from swapchain images
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
  enforceVK(vkCreateImageView(app.dev, &viewInfo, null, &imageView));
  SDL_Log("imageView %p to %p created", imageView, image);
  return imageView;
}

