// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html
import core.stdc.string : memcpy;
import std.datetime : MonoTime, dur;
import std.math;

import includes;
import matrix : mat4, radian, rotate, lookAt, perspective;
import application : App;
import buffer : createBuffer;

struct UniformBufferObject {
  mat4 scene;
  mat4 view;
  mat4 proj;
  mat4 orientation; // Screen orientation
}

struct Uniform {
  VkBuffer[] uniformBuffers;
  VkDeviceMemory[] uniformBuffersMemory;
}

void createUniformBuffers(ref App app) {
  VkDeviceSize bufferSize = UniformBufferObject.sizeof;

  app.uniform.uniformBuffers.length = app.swapchain.swapChainImages.length;
  app.uniform.uniformBuffersMemory.length = app.swapchain.swapChainImages.length;

  for (size_t i = 0; i <  app.swapchain.swapChainImages.length; i++) {
    app.createBuffer(bufferSize, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &app.uniform.uniformBuffers[i], &app.uniform.uniformBuffersMemory[i]);
  }
  SDL_Log("created UniformBuffers");
}

void updateUniformBuffer(ref App app, uint currentImage) {
  UniformBufferObject ubo = {
    scene: mat4.init,
    view: lookAt(app.camera.position, app.camera.lookat, app.camera.up),
    proj: perspective(app.camera.fov, app.aspectRatio(), app.camera.nearfar[0], app.camera.nearfar[1]),
    orientation: mat4.init
  };

  // Adjust for screen orientation so that the world is always up
  if (app.surface.capabilities.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [-90.0f, 0.0f, 0.0f]);
  } else if (app.surface.capabilities.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [90.0f, 0.0f, 0.0f]);
  } else if (app.surface.capabilities.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [180.0f, 0.0f, 0.0f]);
  }

  void* data;
  vkMapMemory(app.dev, app.uniform.uniformBuffersMemory[currentImage], 0, ubo.sizeof, 0, &data);
  memcpy(data, &ubo, ubo.sizeof);
  vkUnmapMemory(app.dev, app.uniform.uniformBuffersMemory[currentImage]);
  //toStdout("UniformBuffer updated");
}
