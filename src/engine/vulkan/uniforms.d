/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : createBuffer, cleanup;
import quaternion : xyzw;
import matrix : multiply, rotate, lookAt, perspective;
import lights : computeLightSpace, LMode;
import validation : nameVulkanObject;
import vram : mapped;

struct UniformBufferObject {
  float[4] position;
  Matrix viewProj;
  Matrix view;
  Matrix proj;
  Matrix orientation;
  float shadowTexelSize;
  uint nlights;
  LMode lMode = LMode.LightsAndShadows;
  uint indexBufferLength;
  float[4] clusterCfg;
  float[4] shadowCentre;
}

struct ParticleUniformBuffer {
  float[4] position;
  float[4] gravity;
  float floor;
  float deltaTime;
};

alias UBO = GPUAllocation[];

void createUBO(ref App app, Descriptor descriptor) {
  SDL_Log("Create UBO at %s, size = %d", toStringz(descriptor.base), descriptor.bytes);
  if(descriptor.base in app.ubos) return;
  app.ubos[descriptor.base] = new GPUAllocation[](app.framesInFlight);

  foreach(i, ref a; app.ubos[descriptor.base]) {
    app.createBuffer(&a.buffer, &a.memory, descriptor.bytes, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    a.data = app.mapped(a.memory);
    app.nameVulkanObject(a.buffer, cstr("[UBO-BUF] %s #%d", descriptor.base, i), VK_OBJECT_TYPE_BUFFER);
  }
  if(app.verbose) SDL_Log("Created %d UBO of size: %d bytes", app.imageCount, descriptor.bytes);

  app.swapDeletionQueue.add((){
    if(app.verbose) SDL_Log("Deleting UBO at %s", toStringz(descriptor.base));
    foreach(ref a; app.ubos[descriptor.base]){ app.cleanup(a); }
    app.ubos.remove(descriptor.base);
  });
}

void updateRenderUBO(ref App app, Descriptor d, uint syncIndex) {
  float logFN = log2(app.camera.nearfar[1] / app.camera.nearfar[0]);
  auto cam = app.camera;
  
  UniformBufferObject ubo = {
    position: app.camera.position.xyzw,
    view: app.camera.view, proj: app.camera.proj, orientation: Matrix.init,
    shadowTexelSize: 1.0f / cast(float)app.shadows.dimension,
    nlights: cast(uint)app.lights.length,
    lMode: cast(LMode)app.lMode,
    indexBufferLength: ("ClusterLights" in app.buffers) ? app.buffers["ClusterLights"].nObjects : 0,
    clusterCfg: [LIGHT_GRID[2] / logFN, -(LIGHT_GRID[2] * log2(cam.nearfar[0])) / logFN, cast(float)cam.width, cast(float)cam.height],
    shadowCentre: [cam.lookat[0], 0.0f, cam.lookat[2], 0.0f],
  };

  // Adjust for screen orientation so that the world is always up
  if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR) {
    ubo.orientation = rotate(Matrix.init, [0.0f, -90.0f, 0.0f]);
  } else if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR) {
    ubo.orientation = rotate(Matrix.init, [0.0f, 90.0f, 0.0f]);
  } else if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR) {
    ubo.orientation = rotate(Matrix.init, [0.0f, 180.0f, 0.0f]);
  }
  ubo.viewProj = ubo.orientation.multiply(ubo.proj).multiply(ubo.view);
  memcpy(app.ubos[d.base][syncIndex].data, &ubo, d.bytes);
}
