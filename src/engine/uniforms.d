/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import core.time : MonoTime;
import std.random : uniform;
import std.conv : to;

import buffer : createBuffer;
import matrix : mat4, rotate, lookAt, perspective;
import lights : Light, Lights;

struct UniformBufferObject {
  mat4 scene = mat4.init;
  mat4 view = mat4.init;
  mat4 proj = mat4.init;
  mat4 orientation = mat4.init; // Screen orientation
  Light[4] lights;
  uint nlights = 4;
}

struct Uniform {
  VkBuffer[] uniformBuffers;
  VkBuffer[] computeBuffers;
  VkDeviceMemory[] uniformBuffersMemory;
  VkDeviceMemory[] computeBuffersMemory;
}

void createRenderUBO(ref App app) {
  app.uniform.uniformBuffers.length = app.framesInFlight;
  app.uniform.uniformBuffersMemory.length = app.framesInFlight;

  for (uint i = 0; i < app.framesInFlight; i++) {
    app.createBuffer(&app.uniform.uniformBuffers[i], &app.uniform.uniformBuffersMemory[i], UniformBufferObject.sizeof, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
  }
  if(app.verbose) SDL_Log("Created %d Render UBO of size: %d bytes", app.framesInFlight, UniformBufferObject.sizeof);
  app.frameDeletionQueue.add((){
    for (uint i = 0; i < app.framesInFlight; i++) {
      vkDestroyBuffer(app.device, app.uniform.uniformBuffers[i], app.allocator);
      vkFreeMemory(app.device, app.uniform.uniformBuffersMemory[i], app.allocator);
    }
  });
}

void updateRenderUBO(ref App app, uint syncIndex) {
  UniformBufferObject ubo = {
    scene: mat4.init, //rotate(mat4.init, [time, 0.0f , 0.0f]),
    view: app.camera.view,
    proj: app.camera.proj,
    orientation: mat4.init,
    lights : app.lights,
    nlights : 4
  };

  // Adjust for screen orientation so that the world is always up
  if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [-90.0f, 0.0f, 0.0f]);
  } else if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [90.0f, 0.0f, 0.0f]);
  } else if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [180.0f, 0.0f, 0.0f]);
  }

  void* data;
  vkMapMemory(app.device, app.uniform.uniformBuffersMemory[syncIndex], 0, ubo.sizeof, 0, &data);
  memcpy(data, &ubo, ubo.sizeof);
  vkUnmapMemory(app.device, app.uniform.uniformBuffersMemory[syncIndex]);
}

