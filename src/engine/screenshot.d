/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : createBuffer, copyImageToBuffer;
import commands : beginSingleTimeCommands, endSingleTimeCommands;
import images : transitionImageLayout;
import io : fixPath;

void saveScreenshot(ref App app) {
  uint w = app.camera.width;
  uint h = app.camera.height;
  VkDeviceSize size = w * h * 4;  // RGBA8

  // Staging buffer to receive pixel data
  VkBuffer stagingBuffer;
  VkDeviceMemory stagingMemory;
  app.createBuffer(&stagingBuffer, &stagingMemory, size, VK_BUFFER_USAGE_TRANSFER_DST_BIT);

  void* data;
  enforceVK(vkMapMemory(app.device, stagingMemory, 0, size, 0, &data));

  VkImage srcImage = app.swapChainImages[app.frameIndex];
  VkFormat srcFormat = app.surfaceformats[app.format].format;

  auto cmd = app.beginSingleTimeCommands(app.commandPool);
  app.transitionImageLayout(cmd, srcImage, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
  app.copyImageToBuffer(cmd, srcImage, stagingBuffer, w, h);
  app.transitionImageLayout(cmd, srcImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
  app.endSingleTimeCommands(cmd, app.queue);

  // Handle BGRA → RGBA swap if needed
  ubyte[] pixels = (cast(ubyte*)data)[0 .. size];
  if(srcFormat == VK_FORMAT_B8G8R8A8_UNORM || srcFormat == VK_FORMAT_B8G8R8A8_SRGB) {
    for(size_t i = 0; i < size; i += 4) { swap(pixels[i], pixels[i+2]); }
  }

  // Save as PNG
  auto ts = SDL_GetTicks();
  string path = fixPath(format("data/screenshots/%d.png", ts));
  SDL_Surface* surface = SDL_CreateSurfaceFrom(w, h, SDL_PIXELFORMAT_RGBA32, data, w * 4);
  IMG_SavePNG(surface, toStringz(path));
  SDL_DestroySurface(surface);
  SDL_Log("Screenshot saved: %s", toStringz(path));

  vkUnmapMemory(app.device, stagingMemory);
  vkFreeMemory(app.device, stagingMemory, app.allocator);
  vkDestroyBuffer(app.device, stagingBuffer, app.allocator);
}

