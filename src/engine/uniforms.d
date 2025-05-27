/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import core.time : MonoTime;
import std.random : uniform;
import std.conv : to;

import descriptor : Descriptor;
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

struct ParticleUniformBuffer {
  float[4] position;
  float[4] gravity;
  float floor;
  float deltaTime;
};

struct UBO {
  VkBuffer[] buffer;
  VkDeviceMemory[] memory;
}

void createUBO(ref App app, Descriptor descriptor) {
  uint size = 0;
  if(SDL_strcmp(descriptor.base, "ParticleUniformBuffer") == 0) size = ParticleUniformBuffer.sizeof;
  if(SDL_strcmp(descriptor.base, "UniformBufferObject") == 0) size = UniformBufferObject.sizeof;
  if(app.verbose) SDL_Log("Create UBO at %s, size = %d", descriptor.base, size);

  app.ubos[descriptor.base] = UBO();
  app.ubos[descriptor.base].buffer.length = app.framesInFlight;
  app.ubos[descriptor.base].memory.length = app.framesInFlight;
  for(uint i = 0; i < app.framesInFlight; i++) {
    app.createBuffer(&app.ubos[descriptor.base].buffer[i], &app.ubos[descriptor.base].memory[i], size, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
  }
  if(app.verbose) SDL_Log("Created %d ComputeBuffers of size: %d bytes", app.imageCount, size);

  app.frameDeletionQueue.add((){
    if(app.verbose) SDL_Log("Delete Compute UBO at %s", descriptor.base);
    for(uint i = 0; i < app.framesInFlight; i++) {
      vkDestroyBuffer(app.device, app.ubos[descriptor.base].buffer[i], app.allocator);
      vkFreeMemory(app.device, app.ubos[descriptor.base].memory[i], app.allocator);
    }
  });
}

void updateRenderUBO(ref App app, Shader[] shaders, uint syncIndex) {
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

  for(uint s = 0; s < shaders.length; s++) {
    auto shader = shaders[s];
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
        void* data;
        vkMapMemory(app.device, app.ubos[shader.descriptors[d].base].memory[syncIndex], 0, ubo.sizeof, 0, &data);
        memcpy(data, &ubo, ubo.sizeof);
        vkUnmapMemory(app.device, app.ubos[shader.descriptors[d].base].memory[syncIndex]);
      }
    }
  }
}

