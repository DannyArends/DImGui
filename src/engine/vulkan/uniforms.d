/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import quaternion : xyzw;
import buffer : createBuffer;
import matrix : rotate, lookAt, perspective;
import lights : computeLightSpace, LMode;
import validation : nameVulkanObject;

struct UniformBufferObject {
  float[4] position;
  Matrix scene;
  Matrix view;
  Matrix proj;
  Matrix orientation;
  float shadowTexelSize;
  uint nlights;
  LMode lMode = LMode.LightsAndShadows;
  uint indexBufferLength;
  float[4] clusterCfg;
}

struct ParticleUniformBuffer {
  float[4] position;
  float[4] gravity;
  float floor;
  float deltaTime;
};

alias UBO = GPUAllocation[];

void forEachUBO(Shader[] shaders, void delegate(Descriptor) fn) {
  foreach(shader; shaders) { foreach(d; shader.descriptors) { if(d.type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) fn(d); } }
}

void createUBO(ref App app, Descriptor descriptor) {
  SDL_Log("Create UBO at %s, size = %d, D struct size = %d", toStringz(descriptor.base), descriptor.bytes, UniformBufferObject.sizeof);
  if(descriptor.base in app.ubos) return;
  app.ubos[descriptor.base] = new GPUAllocation[](app.framesInFlight);

  foreach(i, ref a; app.ubos[descriptor.base]) {
    app.createBuffer(&a.buffer, &a.memory, descriptor.bytes, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    enforceVK(vkMapMemory(app.device, a.memory, 0, descriptor.bytes, 0, &a.data));
    app.nameVulkanObject(a.buffer, toStringz(format("[UBO-BUF] %s #%d", descriptor.base, i)), VK_OBJECT_TYPE_BUFFER);
    app.nameVulkanObject(a.memory, toStringz(format("[UBO-MEM] %s #%d", descriptor.base, i)), VK_OBJECT_TYPE_DEVICE_MEMORY);
  }
  if(app.verbose) SDL_Log("Created %d UBO of size: %d bytes", app.imageCount, descriptor.bytes);

  app.swapDeletionQueue.add((){
    if(app.verbose) SDL_Log("Deleting UBO at %s", toStringz(descriptor.base));
    foreach(a; app.ubos[descriptor.base]) {
      vkUnmapMemory(app.device, a.memory);
      vkFreeMemory(app.device, a.memory, app.allocator);
      vkDestroyBuffer(app.device, a.buffer, app.allocator);
    }
    app.ubos.remove(descriptor.base);
  });
}

void updateRenderUBO(ref App app, Shader[] shaders, uint syncIndex) {
  float logFN = log2(app.camera.nearfar[1] / app.camera.nearfar[0]);

  UniformBufferObject ubo = {
    position: app.camera.position.xyzw,
    scene: Matrix.init,
    view: app.camera.view,
    proj: app.camera.proj,
    orientation: Matrix.init,
    shadowTexelSize: 1.0f / cast(float)app.shadows.dimension,
    nlights: cast(uint)app.lights.length,
    lMode: cast(LMode)app.lMode,
    indexBufferLength: ("ClusterLights" in app.buffers) ? app.buffers["ClusterLights"].nObjects : 0,
    clusterCfg: [LIGHT_GRID[2] / logFN, -(LIGHT_GRID[2] * log2(app.camera.nearfar[0])) / logFN, 0.0f, 0.0f]
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
    if(d.name == "ubo") { memcpy(app.ubos[d.base][syncIndex].data, &ubo, d.bytes); }
  });
}


