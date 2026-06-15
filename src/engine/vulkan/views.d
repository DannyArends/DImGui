/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Create one VK_IMAGE_VIEW_TYPE_2D view per array layer, populating buffer.view[]. */
void createLayerViews(ref App app, ref ImageBuffer buffer, VkFormat format, VkImageAspectFlags aspectMask, uint levelCount = 1) {
  buffer.view.length = buffer.arrayLayers;
  for(uint i = 0; i < buffer.arrayLayers; i++) {
    buffer.view[i] = app.createImageView(buffer.image, format, aspectMask, levelCount, i, 1, VK_IMAGE_VIEW_TYPE_2D);
  }
}

/** Create an ImageView to a VkImage */
VkImageView createImageView(App app, VkImage image, VkFormat format, VkImageAspectFlags aspectMask = VK_IMAGE_ASPECT_COLOR_BIT, 
                            uint levelCount = 1, uint baseLayer = 0, uint layerCount = 1, VkImageViewType viewType = VK_IMAGE_VIEW_TYPE_2D) {
  VkImageSubresourceRange subresourceRange = {
    aspectMask: aspectMask,
    baseMipLevel: 0,
    levelCount: levelCount, baseArrayLayer: baseLayer, layerCount: layerCount
  };

  VkImageViewCreateInfo viewInfo = {
    sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    image: image,
    viewType: viewType,
    format: format,
    subresourceRange: subresourceRange
  };
  VkImageView imageView;
  enforceVK(vkCreateImageView(app.device, &viewInfo, null, &imageView));
  if(app.trace) SDL_Log("imageView %p to %p created", imageView, image);
  return imageView;
}
