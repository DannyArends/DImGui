/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import quaternion : xyzw;
import buffer : createBuffer, deAllocate;
import matrix : rotate, lookAt, perspective;
import lights : computeLightSpace;
import validation : nameVulkanObject;

struct UniformBufferObject {
  float[4] position;
  Matrix scene;
  Matrix view;
  Matrix proj;
  Matrix orientation;
  uint nlights = 0;
}

struct ParticleUniformBuffer {
  float[4] position;
  float[4] gravity;
  float floor;
  float deltaTime;
};

struct UBO {
  VkBuffer[] buffers;
  VkDeviceMemory[] memory;
  void*[] data;
}

void nameUBO(ref App app, UBO ubo, string name){
  for(uint i = 0; i < ubo.buffers.length; i++) {
    app.nameVulkanObject(ubo.buffers[i], toStringz(format("[UBO-BUF] %s #%d", name, i)), VK_OBJECT_TYPE_BUFFER);
    app.nameVulkanObject(ubo.memory[i], toStringz(format("[UBO-MEM] %s #%d", name, i)), VK_OBJECT_TYPE_DEVICE_MEMORY);
  }
}

void forEachUBO(Shader[] shaders, void delegate(Descriptor) fn) {
  foreach(shader; shaders) { foreach(d; shader.descriptors) { if(d.type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) fn(d); } }
}

void createUBO(ref App app, Descriptor descriptor) {
  if(app.verbose) SDL_Log("Create UBO at %s, size = %d", toStringz(descriptor.base), descriptor.bytes);
  if(descriptor.base in app.ubos) return;
  app.ubos[descriptor.base] = UBO();
  app.ubos[descriptor.base].buffers.length = app.framesInFlight;
  app.ubos[descriptor.base].memory.length = app.framesInFlight;
  app.ubos[descriptor.base].data.length = app.framesInFlight;
  for(uint i = 0; i < app.framesInFlight; i++) {
    app.createBuffer(&app.ubos[descriptor.base].buffers[i], &app.ubos[descriptor.base].memory[i], descriptor.bytes, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    enforceVK(vkMapMemory(app.device, app.ubos[descriptor.base].memory[i], 0, descriptor.bytes, 0, &app.ubos[descriptor.base].data[i]));
  }
  app.nameUBO(app.ubos[descriptor.base], descriptor.base);
  if(app.verbose) SDL_Log("Created %d UBO of size: %d bytes", app.imageCount, descriptor.bytes);

  app.swapDeletionQueue.add((){
    if(app.verbose) SDL_Log("Deleting UBO at %s", toStringz(descriptor.base));
    app.deAllocate(app.ubos, descriptor); 
  });
}

void updateRenderUBO(ref App app, Shader[] shaders, uint syncIndex) {
  UniformBufferObject ubo = {
    position: app.camera.position.xyzw,
    scene: Matrix.init,
    view: app.camera.view,
    proj: app.camera.proj,
    orientation: Matrix.init,
    nlights: cast(uint)app.lights.length,
  };

  // Adjust for screen orientation so that the world is always up
  if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR) {
    ubo.orientation = rotate(Matrix.init, [0.0f, -90.0f, 0.0f]);
  } else if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR) {
    ubo.orientation = rotate(Matrix.init, [0.0f, 90.0f, 0.0f]);
  } else if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR) {
    ubo.orientation = rotate(Matrix.init, [0.0f, 180.0f, 0.0f]);
  }

  shaders.forEachUBO((d) {
    if(d.name == "ubo") { memcpy(app.ubos[d.base].data[syncIndex], &ubo, d.bytes); }
  });
}


