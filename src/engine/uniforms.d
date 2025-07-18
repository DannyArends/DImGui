/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import quaternion : xyzw;

import descriptor : Descriptor;
import buffer : createBuffer;
import matrix : mat4, rotate, lookAt, perspective;
import lights : computeLightSpace;

struct UniformBufferObject {
  float[4] position;
  mat4 scene = mat4.init;
  mat4 view = mat4.init;
  mat4 proj = mat4.init;
  mat4 orientation = mat4.init;   /// Screen orientation
  uint nlights = 0;
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
  void*[] data;
}

void createUBO(ref App app, Descriptor descriptor) {
  if(app.verbose) SDL_Log("Create UBO at %s, size = %d", toStringz(descriptor.base), descriptor.bytes);
  if(descriptor.base in app.ubos) return;
  app.ubos[descriptor.base] = UBO();
  app.ubos[descriptor.base].buffer.length = app.framesInFlight;
  app.ubos[descriptor.base].memory.length = app.framesInFlight;
  app.ubos[descriptor.base].data.length = app.framesInFlight;
  for(uint i = 0; i < app.framesInFlight; i++) {
    app.createBuffer(&app.ubos[descriptor.base].buffer[i], &app.ubos[descriptor.base].memory[i], descriptor.bytes, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    vkMapMemory(app.device, app.ubos[descriptor.base].memory[i], 0, descriptor.bytes, 0, &app.ubos[descriptor.base].data[i]);
  }
  if(app.verbose) SDL_Log("Created %d UBO of size: %d bytes", app.imageCount, descriptor.bytes);

  app.frameDeletionQueue.add((){
    if(app.verbose) SDL_Log("Delete Compute UBO at %s", toStringz(descriptor.base));
    for(uint i = 0; i < app.framesInFlight; i++) {
      vkUnmapMemory(app.device, app.ubos[descriptor.base].memory[i]);
      vkDestroyBuffer(app.device, app.ubos[descriptor.base].buffer[i], app.allocator);
      vkFreeMemory(app.device, app.ubos[descriptor.base].memory[i], app.allocator);
    }
    app.ubos.remove(descriptor.base);
  });
}

void updateRenderUBO(ref App app, Shader[] shaders, uint syncIndex) {
  UniformBufferObject ubo = {
    position: app.camera.position.xyzw,
    scene: mat4.init, //rotate(mat4.init, [time, 0.0f , 0.0f]),
    view: app.camera.view,
    proj: app.camera.proj,
    orientation: mat4.init,
    nlights: cast(uint)app.lights.length,
  };

  // Adjust for screen orientation so that the world is always up
  if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_90_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [0.0f, -90.0f, 0.0f]);
  } else if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_270_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [0.0f, 90.0f, 0.0f]);
  } else if (app.camera.currentTransform & VK_SURFACE_TRANSFORM_ROTATE_180_BIT_KHR) {
    ubo.orientation = rotate(mat4.init, [0.0f, 180.0f, 0.0f]);
  }

  for(uint s = 0; s < shaders.length; s++) {
    auto shader = shaders[s];
    for(uint d = 0; d < shader.descriptors.length; d++) {
      if(shader.descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
        if(shader.descriptors[d].name == "ubo") {
          memcpy(app.ubos[shader.descriptors[d].base].data[syncIndex], &ubo, shader.descriptors[d].bytes);
        }
      }
    }
  }
}

void writeUniformBuffer(ref App app, ref VkWriteDescriptorSet[] write, Descriptor descriptor, VkDescriptorSet[] dst, ref VkDescriptorBufferInfo[] bufferInfos, uint syncIndex = 0){
  if(app.verbose) SDL_Log("writeUniformBuffer");
  bufferInfos ~= VkDescriptorBufferInfo(app.ubos[descriptor.base].buffer[syncIndex], 0, descriptor.bytes);
  VkWriteDescriptorSet set = {
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: dst[syncIndex],
    dstBinding: descriptor.binding,
    dstArrayElement: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    descriptorCount: 1,
    pBufferInfo: &bufferInfos[($-1)]
  };
  write ~= set;
}
