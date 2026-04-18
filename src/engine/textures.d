/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : createBuffer, copyBufferToImage;
import commands : beginSingleTimeCommands, endSingleTimeCommands;
import descriptor : createDescriptorSet, updateDescriptorSet;
import images : nameImageBuffer, imageSize, createImage, deAllocate, transitionImageLayout;
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
  
  this(string path, uint width = 0, uint height = 0, SDL_Surface* surface = null){
    this.path = path;
    this.width = width;
    this.height = height;
    this.surface = surface;
  }
}

struct PendingTexture {
  Texture texture;
  SingleTimeCommand cmdBuffer;
  StageBuffer staging;
}

struct Textures {
  Texture[] textures;                         /// Textures
  PendingTexture[] pending;                   /// Textures submitted to GPU but not yet confirmed ready
  bool loaded = false;                        /// Are we loading a texture a-sync ?
  alias textures this;
}

bool isTexture(string path){
  if(extension(path) == ".jpg") return(true);
  if(extension(path) == ".png") return(true);
  return(false);
}

// Convert an SDL-Surface to RGBA32 format
void toRGBA(ref SDL_Surface* surface, uint verbose = 0) {
  SDL_Surface* adapted = SDL_ConvertSurface(surface, SDL_PIXELFORMAT_RGBA32);
  if (adapted) {
    SDL_DestroySurface(surface); // Free the SDL_Surface
    surface = adapted;
    if(verbose > 1) SDL_Log("surface adapted: %p [%dx%d:%d]", surface, surface.w, surface.h, (SDL_GetPixelFormatDetails(surface.format).bytes_per_pixel));
  }
}

/** Create a 1x1 white SDL_Surface
 */
SDL_Surface* createDummySDLSurface() {
  SDL_Surface* surface = SDL_CreateSurface(1, 1, SDL_PIXELFORMAT_RGBA32);
  if(!surface){
    SDL_Log("Failed to create dummy SDL_Surface: %s", SDL_GetError());
    return null;
  }

  if(SDL_MUSTLOCK(surface)) SDL_LockSurface(surface);
  auto whitePixel = SDL_MapRGBA(SDL_GetPixelFormatDetails(surface.format), null, 255, 255, 255, 255);
  memcpy(surface.pixels, &whitePixel, SDL_GetPixelFormatDetails(surface.format).bytes_per_pixel);
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

void transferTextureAsync(ref App app, ref Texture texture) {
  SingleTimeCommand cmdBuffer = app.beginSingleTimeCommands(app.transferPool, true);
  StageBuffer staging;
  app.toGPU(cmdBuffer, texture, staging);
  vkEndCommandBuffer(cmdBuffer);
  VkSubmitInfo submitInfo = {
    sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount: 1,
    pCommandBuffers: &cmdBuffer.commands,
  };
  app.nameVulkanObject(cmdBuffer.fence, toStringz(format("[FENCE] %s", texture.path)), VK_OBJECT_TYPE_FENCE);
  enforceVK(vkQueueSubmit(app.transfer, 1, &submitInfo, cmdBuffer.fence));
  app.textures.pending ~= PendingTexture(texture, cmdBuffer, staging);
}

int getTexture(ref App app, Material material, aiTextureType type = aiTextureType_DIFFUSE){
  if (type in material.textures) { return(idx(app.textures, material.textures[type])); }
  return(-1);
}

void mapTextures(ref App app) { for(uint i = 0; i < app.objects.length; i++) { app.mapTextures(app.objects[i]); } }

void mapTextures(ref App app, ref Geometry object) {
  foreach (ref mesh; object.meshes) {
    if(mesh.mid < 0) continue;
    auto tid = app.getTexture(object.materials[mesh.mid], aiTextureType_DIFFUSE);
    auto nid = app.getTexture(object.materials[mesh.mid], aiTextureType_NORMALS);
    auto oid = app.getTexture(object.materials[mesh.mid], aiTextureType_OPACITY);
    if(tid != mesh.tid || nid != mesh.nid || oid != mesh.oid) {
      object.buffers[INSTANCE] = false;
      app.buffers["MeshMatrices"].dirty[] = true;
    }
    mesh.tid = tid; mesh.nid = nid; mesh.oid = oid;
  }
}

void updateTextures(ref App app) {
  bool needsUpdate = false;
  size_t nPending = app.textures.pending.length;
  foreach(ref texture; app.textures) {
    if(texture.dirty) {
      needsUpdate = true;
      if(app.trace) { SDL_Log("updateTextures: syncIndex=%d texture.syncIndex=%d pending=%d", app.syncIndex, texture.syncIndex, nPending); }
      if(texture.syncIndex == app.syncIndex) {
        app.mapTextures();
        texture.dirty = false;
        texture.syncIndex = -1;
        needsUpdate = false;
      } else if(texture.syncIndex == -1) { texture.syncIndex = app.syncIndex; }
    }
  }
  if(needsUpdate) {
    if(app.trace) SDL_Log("updateTextures -> updateDescriptorSet (syncIndex=%d textures.length=%d)", app.syncIndex, app.textures.length);
    app.updateDescriptorSet(app.shaders, app.sets[Stage.RENDER], app.syncIndex);
  }
}

void toGPU(ref App app, VkCommandBuffer cmdBuffer, ref Texture texture, out StageBuffer staging) {
  // Create a buffer to transfer the image to the GPU
  app.createBuffer(&staging.sb, &staging.sbM, texture.surface.imageSize);
  app.nameVulkanObject(staging.sb, toStringz("[IMAGE-SB] " ~ baseName(texture.path)), VK_OBJECT_TYPE_BUFFER);

  // Copy the image data to the StagingBuffer memory
  void* data;
  enforceVK(vkMapMemory(app.device, staging.sbM, 0, texture.surface.imageSize, 0, &data));
  if(SDL_MUSTLOCK(texture.surface)) SDL_LockSurface(texture.surface);
  memcpy(data, texture.surface.pixels, texture.surface.imageSize);
  if(SDL_MUSTLOCK(texture.surface)) SDL_UnlockSurface(texture.surface);

  // If we already had an image, view and memory, make sure to deAllocate it on shutdown
  if(texture.image){ app.mainDeletionQueue.add((){ app.deAllocate(texture); }); }

  // Create an image, transition the layout
  app.createImage(texture.surface.w, texture.surface.h, &texture.image, &texture.memory);
  app.transitionImageLayout(cmdBuffer, texture.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
  app.copyBufferToImage(cmdBuffer, staging.sb, texture.image, texture.surface.w, texture.surface.h);
  app.transitionImageLayout(cmdBuffer, texture.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

  // Create an imageview and register the texture with ImGui
  texture.view = app.createImageView(texture.image, VK_FORMAT_R8G8B8A8_SRGB);
  app.nameImageBuffer(texture, texture.path);
  app.registerTexture(texture);
}

/** 'Register' a texture in the ImGui DescriptorSet
 */
void registerTexture(ref App app, ref Texture texture) {
  if(app.trace) SDL_Log("Registering Texture %p with ImGui", texture.view);
  texture.imID = createDescriptorSet(app.device, app.pools[Stage.IMGUI], app.layouts[Stage.IMGUI], 1)[0];

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

