/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : dir;
import buffer : createBuffer, copyBufferToImage;
import images : imageSize, createImage, transitionImageLayout;
import swapchain : createImageView;
import descriptor : createDescriptorSet;

struct Texture {
  const(char)* path;
  uint width = 0;
  uint height = 0;
  SDL_Surface* surface;

  VkDescriptorSet imID;
  VkImage image;
  VkImageView view;
  VkDeviceMemory memory;

  alias surface this;
}

// Convert an SDL-Surface to RGBA32 format
void toRGBA(ref SDL_Surface* surface, uint verbose = 0) {
  SDL_PixelFormat *fmt = SDL_AllocFormat(SDL_PIXELFORMAT_RGBA32);
  fmt.BitsPerPixel = 32;
  SDL_Surface* adapted = SDL_ConvertSurface(surface, fmt, 0);
  SDL_FreeFormat(fmt); // Free the SDL_PixelFormat
  if (adapted) {
    SDL_FreeSurface(surface); // Free the SDL_Surface
    surface = adapted;
    if(verbose > 1) SDL_Log("surface adapted: %p [%dx%d:%d]", surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));
  }
}

// Load all texture files matching pattern in folder
void loadTextures(ref App app, const(char)* folder = "data/textures/", string pattern = "*.{png,jpg}") {
  immutable(char)*[] files = dir(folder, pattern, false);
  foreach(file; files){ app.loadTexture(file); }
}

void loadTexture(ref App app, const(char)* path) {
  if(app.trace) SDL_Log("loadTexture '%s'", path);
  auto surface = IMG_Load(path);
  if(app.trace) SDL_Log("loadTexture '%s', Surface: %p [%dx%d:%d]", path, surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));

  // Adapt surface to 32 bit, and create structure
  if (surface.format.BitsPerPixel != 32) { surface.toRGBA(app.verbose); }
  Texture texture = { path : path, width: surface.w, height: surface.h, surface: surface };
  app.toGPU(texture);
  app.mainDeletionQueue.add((){ app.deAllocate(texture); });
}

void toGPU(ref App app, ref Texture texture){
  // Create a buffer to transfer the image to the GPU
  VkBuffer stagingBuffer;
  VkDeviceMemory stagingBufferMemory;
  app.createBuffer(&stagingBuffer, &stagingBufferMemory, texture.surface.imageSize);

  // Copy the image data to the StagingBuffer memory
  void* data;
  vkMapMemory(app.device, stagingBufferMemory, 0, texture.surface.imageSize, 0, &data);
  memcpy(data, texture.surface.pixels, texture.surface.imageSize);
  vkUnmapMemory(app.device, stagingBufferMemory);

  // Create an image, transition the layout
  app.createImage(texture.surface.w, texture.surface.h, &texture.image, &texture.memory);
  app.transitionImageLayout(texture.image, null, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
  app.copyBufferToImage(stagingBuffer, texture.image, texture.surface.w, texture.surface.h);
  app.transitionImageLayout(texture.image, null, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

  // Create an imageview on the image
  texture.view = app.createImageView(texture.image, VK_FORMAT_R8G8B8A8_SRGB);

  // Register Texture with ImGui, and store in texture array
  app.registerTexture(texture);
  app.textures ~= texture;

  // Cleanup
  if(app.trace) SDL_Log("Freeing surface: %p [%dx%d:%d]", texture.surface, texture.surface.w, texture.surface.h, (texture.surface.format.BitsPerPixel / 8));
  SDL_FreeSurface(texture.surface);
  vkDestroyBuffer(app.device, stagingBuffer, app.allocator);
  vkFreeMemory(app.device, stagingBufferMemory, app.allocator);
}

/** Texture index
 */
@nogc int idx(const Texture[] textures, const(char)* name) nothrow {
  for(uint i = 0; i < textures.length; i++) { if(strstr(textures[i].path, name) != null) return(i); }
  return(-1);
}

/** Create a TextureSampler for sampling from a texture
 */
void createSampler(ref App app) {
  if(app.verbose) SDL_Log("Create texture sampler");
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
    borderColor: VK_BORDER_COLOR_INT_OPAQUE_BLACK,
    unnormalizedCoordinates: VK_FALSE,
    compareEnable: VK_FALSE,
    compareOp: VK_COMPARE_OP_ALWAYS,
    mipmapMode: VK_SAMPLER_MIPMAP_MODE_LINEAR,
    mipLodBias: 0.0f,
    minLod: 0.0f,
    maxLod: 0.0f
  };

  enforceVK(vkCreateSampler(app.device, &samplerInfo, null, &app.sampler));
  app.mainDeletionQueue.add((){ vkDestroySampler(app.device, app.sampler, null); });

  if(app.verbose) SDL_Log("Created TextureSampler: %p", app.sampler);
}

/** 'Register' a texture in the ImGui DescriptorSet
 */
void registerTexture(ref App app, ref Texture texture) {
  if(app.trace) SDL_Log("Registering Texture %p with ImGui", texture.view);
  texture.imID = createDescriptorSet(app.device, app.pools[IMGUI], app.layouts[IMGUI], 1)[0];

  VkDescriptorImageInfo textureImage = {
    imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    imageView: texture.view,
    sampler: app.sampler
  };
  VkWriteDescriptorSet[1] descriptorWrites = [{
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: texture.imID,
    dstBinding: 0,
    dstArrayElement: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount: 1,
    pImageInfo: &textureImage
  }];
  vkUpdateDescriptorSets(app.device, 1, &descriptorWrites[0], 0, null);
}

void deAllocate(App app, Texture texture) {
  vkDestroyImageView(app.device, texture.view, app.allocator);
  vkDestroyImage(app.device, texture.image, app.allocator);
  vkFreeMemory(app.device, texture.memory, app.allocator);
}
