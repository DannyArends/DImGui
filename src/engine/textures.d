/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import core.time : dur;

import io : dir;
import glyphatlas : createFontTexture;
import buffer : createBuffer, copyBufferToImage;
import images : imageSize, createImage, transitionImageLayout;
import swapchain : createImageView;
import descriptor : createDescriptorSet, updateDescriptorSet;
import validation : nameVulkanObject;

struct Texture {
  const(char)* path;
  uint width = 0;
  uint height = 0;
  SDL_Surface* surface;

  VkDescriptorSet imID;
  VkImage image;
  VkImageView view;
  VkDeviceMemory memory;

  bool dirty = true;
  int syncIndex = -1;
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

// Function to create a 1x1 white SDL_Surface
SDL_Surface* createDummySDLSurface() {
  SDL_Surface* surface = SDL_CreateRGBSurfaceWithFormat(0, 1, 1, 32, SDL_PIXELFORMAT_RGBA32);
  if(!surface){
    SDL_Log("Failed to create dummy SDL_Surface: %s", SDL_GetError());
    return null;
  }

  if(SDL_MUSTLOCK(surface)) SDL_LockSurface(surface);
  auto whitePixel = SDL_MapRGBA(surface.format, 255, 255, 255, 255);
  memcpy(surface.pixels, &whitePixel, surface.format.BytesPerPixel);
  if(SDL_MUSTLOCK(surface)) SDL_UnlockSurface(surface);
  return surface;
}

uint findTextureSlot(App app, string name = "empty"){
  for(uint x = 0; x < app.maxTextures; x++) { 
    string slot = to!string(app.textures[x].path);
    if(slot == "empty" || slot == name) return(x);
  }
  assert(0, "No more texture slots");
}

void initDummyTexture(ref App app, immutable(char)*[] files, uint x){
  Texture dummy = { path : "empty", width: 1, height: 1, surface: createDummySDLSurface() };
  if(x < files.length) dummy.path = files[x];
  app.toGPU(dummy, x);
  app.mainDeletionQueue.add((){ app.deAllocate(dummy); });
}

// Load all texture files matching pattern in folder
void loadTextures(ref App app, const(char)* folder = "data/textures/", string pattern = "*.{png,jpg}") {
  immutable(char)*[] files = dir(folder, pattern, false);
  app.textures.length = app.maxTextures;
  for(uint x = 0; x < app.maxTextures; x++) { app.initDummyTexture(files, x); }
  new Thread({
    if(app.verbose) SDL_Log("Loading textures under %p", Thread.getThis());
    app.createFontTexture();
    foreach(i, file; files) { app.loadTexture(file, cast(uint)i); /*Thread.sleep(dur!("msecs")( 150 )); */ }
  }).start();
}

void updateTextures(ref App app) {
  bool needsUpdate = false;
  for(uint i = 0; i < app.textures.length; i++) { 
    if(app.textures[i].dirty) {
      needsUpdate = true;
      if(app.textures[i].syncIndex == app.syncIndex) {
        // We are round, we updated all the descriptors for each Frame in Flight
        app.textures[i].dirty = false;
        app.textures[i].syncIndex = -1;
        needsUpdate = false;
      } else if(app.textures[i].syncIndex == -1) { // Dirty and not in the process of update
        app.textures[i].syncIndex = app.syncIndex;
      } // else:  // Dirty and in the process of update
    }
  }
  if(needsUpdate) { if(app.verbose) SDL_Log("Texture Loaded A-sync, updating");
    app.updateDescriptorSet(app.shaders, app.sets[RENDER], app.syncIndex);
  }
}

void loadTexture(ref App app, const(char)* path, uint i) {
  if(app.verbose) SDL_Log("loadTexture '%s'", path);
  auto surface = IMG_Load(path);
  if(app.trace) SDL_Log("loadTexture '%s', Surface: %p [%dx%d:%d]", path, surface, surface.w, surface.h, (surface.format.BitsPerPixel / 8));

  // Adapt surface to 32 bit, and create structure
  if (surface.format.BitsPerPixel != 32) { surface.toRGBA(app.verbose); }
  Texture texture = { path : path, width: surface.w, height: surface.h, surface: surface };
  app.toGPU(texture, i);
  app.textures[i].dirty = true;
  if(app.verbose) SDL_Log("loadTexture '%s' DONE", path);
  app.mainDeletionQueue.add((){ app.deAllocate(texture); });
}

void toGPU(ref App app, ref Texture texture, uint i) {
  // Create a buffer to transfer the image to the GPU
  VkBuffer stagingBuffer;
  VkDeviceMemory stagingBufferMemory;
  app.createBuffer(&stagingBuffer, &stagingBufferMemory, texture.surface.imageSize);

  // Copy the image data to the StagingBuffer memory
  void* data;
  vkMapMemory(app.device, stagingBufferMemory, 0, texture.surface.imageSize, 0, &data);
  if(SDL_MUSTLOCK(texture.surface)) SDL_LockSurface(texture.surface);
  memcpy(data, texture.surface.pixels, texture.surface.imageSize);
  if(SDL_MUSTLOCK(texture.surface)) SDL_UnlockSurface(texture.surface);
  vkUnmapMemory(app.device, stagingBufferMemory);

  // Create an image, transition the layout
  app.createImage(texture.surface.w, texture.surface.h, &texture.image, &texture.memory);
  app.transitionImageLayout(texture.image, app.transferPool, app.transfer, null, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
  app.copyBufferToImage(stagingBuffer, texture.image, texture.surface.w, texture.surface.h);
  app.transitionImageLayout(texture.image, app.transferPool, app.transfer, null, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

  // Create an imageview on the image
  texture.view = app.createImageView(texture.image, VK_FORMAT_R8G8B8A8_SRGB);

  // Register Texture with ImGui, and store in texture array
  app.registerTexture(texture);
  app.textures[i] = texture;

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
