import engine;

import buffer : createBuffer, copyBufferToImage;
import images : imageSize, createImage, transitionImageLayout;
import swapchain : createImageView;

struct Texture {
  int width = 0;
  int height = 0;
  int id = 0;

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

void destroyTexture(App app, Texture texture) {
  vkDestroyImageView(app.device, texture.textureImageView, app.allocator);
  vkDestroyImage(app.device, texture.textureImage, app.allocator);
  vkFreeMemory(app.device, texture.textureImageMemory, app.allocator);
}

