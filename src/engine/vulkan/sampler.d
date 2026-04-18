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
    anisotropyEnable: supportedFeatures.samplerAnisotropy,
    maxAnisotropy: properties.limits.maxSamplerAnisotropy,
    borderColor: VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE,
    unnormalizedCoordinates: VK_FALSE,
    compareEnable: VK_TRUE,
    compareOp: VK_COMPARE_OP_LESS_OR_EQUAL,
    mipmapMode: VK_SAMPLER_MIPMAP_MODE_LINEAR,
    maxLod: VK_LOD_CLAMP_NONE
  };

  enforceVK(vkCreateSampler(app.device, &samplerInfo, null, &app.sampler));
  app.nameVulkanObject(app.sampler, toStringz("[SAMPLER] Render"), VK_OBJECT_TYPE_SAMPLER);

  app.mainDeletionQueue.add((){ vkDestroySampler(app.device, app.sampler, null); });

  if(app.verbose) SDL_Log("Created TextureSampler: %p", app.sampler);
}


