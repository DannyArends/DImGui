/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import validation : nameVulkanObject;

/** Create a TextureSampler for sampling from a texture
 */
void createSampler(ref App app) {
  if(app.verbose) SDL_Log("createSampler");
  VkPhysicalDeviceProperties properties = {};
  VkPhysicalDeviceFeatures supportedFeatures = {};

  vkGetPhysicalDeviceProperties(app.physicalDevice, &properties);
  vkGetPhysicalDeviceFeatures(app.physicalDevice, &supportedFeatures);

  VkSamplerCreateInfo samplerInfo = {
    sType: VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
    magFilter: VK_FILTER_LINEAR,
    minFilter: VK_FILTER_LINEAR,
    addressModeU: VK_SAMPLER_ADDRESS_MODE_REPEAT,
    addressModeV: VK_SAMPLER_ADDRESS_MODE_REPEAT,
    addressModeW: VK_SAMPLER_ADDRESS_MODE_REPEAT,
    anisotropyEnable: ((supportedFeatures.samplerAnisotropy) ? VK_FALSE : VK_TRUE),
    maxAnisotropy: properties.limits.maxSamplerAnisotropy,
    borderColor: VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE,
    unnormalizedCoordinates: VK_FALSE,
    compareEnable: VK_TRUE,
    compareOp: VK_COMPARE_OP_LESS_OR_EQUAL,
    mipmapMode: VK_SAMPLER_MIPMAP_MODE_LINEAR,
  };

  enforceVK(vkCreateSampler(app.device, &samplerInfo, null, &app.sampler));
  app.nameVulkanObject(app.sampler, toStringz("[SAMPLER] Render"), VK_OBJECT_TYPE_SAMPLER);

  app.mainDeletionQueue.add((){ vkDestroySampler(app.device, app.sampler, null); });

  if(app.verbose) SDL_Log("Created TextureSampler: %p", app.sampler);
}

void writeTextureSampler(ref App app, ref VkWriteDescriptorSet[] write, Descriptor descriptor, VkDescriptorSet dst, ref VkDescriptorImageInfo[] imageInfos){
  size_t startIndex = imageInfos.length;

  for (size_t i = 0; i < app.textures.length; i++) {
    VkDescriptorImageInfo textureImage = {
      imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      imageView: app.textures[i].view,
      sampler: app.sampler
    };
    imageInfos ~= textureImage;
  }
  VkWriteDescriptorSet set = {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: dst,
    dstBinding: descriptor.binding,
    dstArrayElement: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount: cast(uint)app.textures.length,
    pImageInfo: &imageInfos[startIndex]
  };
  write ~= set;
}
