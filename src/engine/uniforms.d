import engine;

import core.time : MonoTime;

import buffer : createBuffer;
import matrix : mat4, rotate, lookAt, perspective;


struct UniformBufferObject {
  mat4 scene = mat4.init;
  mat4 view = mat4.init;
  mat4 proj = mat4.init;
  mat4 orientation = mat4.init; // Screen orientation
}

struct Uniform {
  VkBuffer[] uniformBuffers;
  VkDeviceMemory[] uniformBuffersMemory;
}

void createUniforms(ref App app) {
  VkDeviceSize size = UniformBufferObject.sizeof;

  app.uniform.uniformBuffers.length = app.imageCount;
  app.uniform.uniformBuffersMemory.length = app.imageCount;

  for (size_t i = 0; i <  app.imageCount; i++) {
    app.createBuffer(&app.uniform.uniformBuffers[i], &app.uniform.uniformBuffersMemory[i], size, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
  }
  SDL_Log("Created %d UniformBuffers of size: %d bytes", app.imageCount, size);
}


void updateUniformBuffer(ref App app, uint currentImage) {
  UniformBufferObject ubo = {
    scene: mat4.init, //rotate(mat4.init, [time, 0.0f , 0.0f]),
    view: lookAt(app.camera.position, app.camera.lookat, app.camera.up),
    proj: perspective(app.camera.fov, app.aspectRatio, app.camera.nearfar[0], app.camera.nearfar[1]),
    orientation: mat4.init
  };

  // Adjust for screen orientation so that the world is always up
  if (app.capabilities.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [-90.0f, 0.0f, 0.0f]);
  } else if (app.capabilities.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [90.0f, 0.0f, 0.0f]);
  } else if (app.capabilities.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [180.0f, 0.0f, 0.0f]);
  }

  void* data;
  vkMapMemory(app.device, app.uniform.uniformBuffersMemory[currentImage], 0, ubo.sizeof, 0, &data);
  memcpy(data, &ubo, ubo.sizeof);
  vkUnmapMemory(app.device, app.uniform.uniformBuffersMemory[currentImage]);
  //toStdout("UniformBuffer updated");
}

void destroyUniforms(App app) {
  for (size_t i = 0; i <  app.imageCount; i++) {
    vkDestroyBuffer(app.device, app.uniform.uniformBuffers[i], app.allocator);
    vkFreeMemory(app.device, app.uniform.uniformBuffersMemory[i], app.allocator);
  }
}

