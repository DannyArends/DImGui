/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;


import buffer : createBuffer, copyBufferToImage;
import commands : SingleTimeCommand, beginSingleTimeCommands, endSingleTimeCommands;
import descriptor : createDescriptorSet, updateDescriptorSet;
import geometry : Geometry;
import glyphatlas : createFontTexture;
import material : getTexture;
import images : ImageBuffer, nameImageBuffer, imageSize, createImage, deAllocate, transitionImageLayout;
import io : dir;
import swapchain : createImageView;
import validation : nameVulkanObject;

ImTextureRef ImTextureRefFromID(ulong tex_id) { 
  ImTextureRef tex_ref = { null, cast(ImTextureID)tex_id }; 
  return tex_ref; 
}

struct Texture {
  string path;
  uint width = 0;
  uint height = 0;
  SDL_Surface* surface;

  VkDescriptorSet imID;
  ImageBuffer buffer;

  bool dirty = true;
  int syncIndex = -1;
  alias buffer this;
}

struct Textures {
  Texture[] textures;             /// Textures
  bool loaded = false;            /// Are we loading a texture a-sync ?
  bool transfer = false;          /// Are we currently using the transfer queue for uploading & transitioning ?
  SingleTimeCommand cmdBuffer;    /// A-Sync single time command buffer
  alias textures this;
}

bool isTexture(string path){
  if(extension(path) == ".jpg") return(true);
  if(extension(path) == ".png") return(true);
  return(false);
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

/** Create a 1x1 white SDL_Surface
 */
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

/** Texture index
 */
@nogc pure int idx(const Texture[] textures, string name) nothrow {
  int besthit = -1;
  for(uint i = 0; i < textures.length; i++) {
    if(stripExtension(baseName(textures[i].path)) == name) return(i);
    if(textures[i].path.indexOf(name) >= 0) besthit = i;
  }
  return(besthit);
}

void transferTextureAsync(ref App app, ref Texture texture){
  app.textures.cmdBuffer = app.beginSingleTimeCommands(app.transferPool, true);
  app.toGPU(app.textures.cmdBuffer, texture);
  vkEndCommandBuffer(app.textures.cmdBuffer);
  VkSubmitInfo submitInfo = {
    sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount: 1,
    pCommandBuffers: &app.textures.cmdBuffer.commands,
  };
  app.nameVulkanObject(app.textures.cmdBuffer.fence, toStringz(format("[FENCE] %s", texture.path)), VK_OBJECT_TYPE_FENCE);
  enforceVK(vkQueueSubmit(app.transfer, 1, &submitInfo, app.textures.cmdBuffer.fence)); // Submit to the transfer queue
  app.textures ~= texture;
}

void mapTextures(ref App app){
  for(uint i = 0; i < app.objects.length; i++) { app.mapTextures(app.objects[i]); }
}

void mapTextures(ref App app, ref Geometry object){
  foreach (ref mesh; object.meshes) {
    if(mesh.mid < 0) continue;
    mesh.tid = app.getTexture(object, mesh.mid, aiTextureType_DIFFUSE);
    mesh.nid = app.getTexture(object, mesh.mid, aiTextureType_NORMALS);
    mesh.oid = app.getTexture(object, mesh.mid, aiTextureType_OPACITY);
  }
}

void updateTextures(ref App app) {
  bool needsUpdate = false;
  for(uint i = 0; i < app.textures.length; i++) { 
    if(app.textures[i].dirty) {
      needsUpdate = true;
      if(app.textures[i].syncIndex == app.syncIndex) { // We are round, we updated all the descriptors for each Frame in Flight
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

void toGPU(ref App app, VkCommandBuffer cmdBuffer, ref Texture texture) {
  // Create a buffer to transfer the image to the GPU
  VkBuffer stagingBuffer;
  VkDeviceMemory stagingBufferMemory;
  app.createBuffer(&stagingBuffer, &stagingBufferMemory, texture.surface.imageSize);
  app.nameVulkanObject(stagingBuffer, toStringz("[IMAGE-SB] " ~ baseName(texture.path)), VK_OBJECT_TYPE_BUFFER);

  // Copy the image data to the StagingBuffer memory
  void* data;
  vkMapMemory(app.device, stagingBufferMemory, 0, texture.surface.imageSize, 0, &data);
  if(SDL_MUSTLOCK(texture.surface)) SDL_LockSurface(texture.surface);
  memcpy(data, texture.surface.pixels, texture.surface.imageSize);
  if(SDL_MUSTLOCK(texture.surface)) SDL_UnlockSurface(texture.surface);

  // If we already had an image, view and memory, make sure to deAllocate it on shutdown
  if(texture.image){ app.mainDeletionQueue.add((){ app.deAllocate(texture); }); }

  // Create an image, transition the layout
  app.createImage(texture.surface.w, texture.surface.h, &texture.image, &texture.memory);
  app.transitionImageLayout(cmdBuffer, texture.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
  app.copyBufferToImage(cmdBuffer, stagingBuffer, texture.image, texture.surface.w, texture.surface.h);
  app.transitionImageLayout(cmdBuffer, texture.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

  // Create an imageview and register the texture with ImGui
  texture.view = app.createImageView(texture.image, VK_FORMAT_R8G8B8A8_SRGB);
  app.nameImageBuffer(texture, texture.path);
  app.registerTexture(texture);

  // Cleanup to mainDeletionQueue
  app.mainDeletionQueue.add((){
    vkUnmapMemory(app.device, stagingBufferMemory);
    vkFreeMemory(app.device, stagingBufferMemory, app.allocator);
    vkDestroyBuffer(app.device, stagingBuffer, app.allocator);
    SDL_FreeSurface(texture.surface);
  });
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

