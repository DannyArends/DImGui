import engine;

import buffer : createBuffer, copyBufferToImage;
import images : imageSize, createImage, transitionImageLayout;
import swapchain : createImageView;

struct Texture {
  uint width = 0;
  uint height = 0;

  VkImage textureImage;
  VkDeviceMemory textureImageMemory;
  VkImageView textureImageView;

  SDL_Surface* surface;
  alias surface this;
}

// Convert an SDL-Surface to RGBA32 format
void toRGBA(ref SDL_Surface* surface, bool verbose = false) {
  SDL_PixelFormat *fmt = SDL_AllocFormat(SDL_PIXELFORMAT_RGBA32);
  fmt.BitsPerPixel = 32;
  SDL_Surface* adapted = SDL_ConvertSurface(surface, fmt, 0);
  SDL_FreeFormat(fmt); // Free the SDL_PixelFormat
  if (adapted) {
    SDL_FreeSurface(surface); // Free the SDL_Surface
    surface = adapted;
    if(verbose) SDL_Log("surface adapted: %p [%dx%d:%d]", surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));
  }
}

Texture loadTexture(App app, const(char)* path) {
  SDL_Log("loadTexture '%s'", path);
  auto surface = IMG_Load(path);
  SDL_Log("loadTexture '%s', Surface: %p [%dx%d:%d]", path, surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));

  // Adapt surface to 32 bit, and create structure
  if (surface.format.BitsPerPixel != 32) { surface.toRGBA(app.verbose); }
  Texture texture = { width: surface.w, height: surface.h, surface: surface };

  // Create a buffer to transfer the image to the GPU
  VkBuffer stagingBuffer;
  VkDeviceMemory stagingBufferMemory;
  app.createBuffer(&stagingBuffer, &stagingBufferMemory, surface.imageSize);

  // Copy the image data to the StagingBuffer memory
  void* data;
  vkMapMemory(app.device, stagingBufferMemory, 0, surface.imageSize, 0, &data);
  memcpy(data, surface.pixels, surface.imageSize);
  vkUnmapMemory(app.device, stagingBufferMemory);

  // Create an image, transition the layout
  app.createImage(surface.w, surface.h, &texture.textureImage, &texture.textureImageMemory);
  app.transitionImageLayout(texture.textureImage, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
  app.copyBufferToImage(stagingBuffer, texture.textureImage, surface.w, surface.h);
  app.transitionImageLayout(texture.textureImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

  // Create an imageview on the image
  texture.textureImageView = app.createImageView(texture.textureImage, VK_FORMAT_R8G8B8A8_SRGB);

  // Cleanup
  if(app.verbose) SDL_Log("Freeing surface: %p [%dx%d:%d]", surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));
  SDL_FreeSurface(surface);
  vkDestroyBuffer(app.device, stagingBuffer, app.allocator);
  vkFreeMemory(app.device, stagingBufferMemory, app.allocator);
  return(texture);
}

// Create a TextureSampler for sampling from a texture
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
}

void destroyTexture(App app, Texture texture) {
  vkDestroyImageView(app.device, texture.textureImageView, app.allocator);
  vkDestroyImage(app.device, texture.textureImage, app.allocator);
  vkFreeMemory(app.device, texture.textureImageMemory, app.allocator);
}

