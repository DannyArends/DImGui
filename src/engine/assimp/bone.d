/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import animation : Node, calculateGlobalTransform;
import assimp : name, toMatrix;
import buffer : createBuffer;
import matrix : Matrix, inverse, position, transpose;
import sdl : STARTUP;

struct Bone {
  Matrix offset;          /// Inverse bind pose matrix
  uint index;             /// Bone index

  @property float[3] bindPosition() { return offset.inverse().position(); }
}

float[uint][string] loadBones(aiMesh* mesh, ref Bone[string] globalBones) {
  float[uint][string] weights;
  for (uint b = 0; b < mesh.mNumBones; b++) {
    auto aiBone = mesh.mBones[b];
    if(aiBone.mNumWeights == 0) continue;
    string name = aiBone.name();
    if(!(name in globalBones)){
      globalBones[name] = Bone();
      globalBones[name].offset = toMatrix(aiBone.mOffsetMatrix);
      globalBones[name].index = cast(uint)(globalBones.length-1);
    }
    //SDL_Log(toStringz(format("%s.bone: %d -> %d", name, globalBones[name].index, aiBone.mNumWeights)));
    for (uint w = 0; w < aiBone.mNumWeights; w++) {
      auto aiWeight = aiBone.mWeights[w];
      weights[name][aiWeight.mVertexId] = aiWeight.mWeight;
    }
  }
  return(weights);
}

Matrix[] getBoneOffsets(App app, double animationTime = 0.0f) {
  Matrix[] boneOffsets;
  foreach(obj; app.objects){
    if(obj.bones.length > 0) {
      Matrix[] offsets;
      offsets.length = obj.bones.length;
      app.calculateGlobalTransform(app.animations[app.animation], obj.bones, offsets, app.rootnode, Matrix(), animationTime);
      boneOffsets ~= offsets;
    }
  }
  //SDL_Log("Computed: %d offsets", nOffsets);
  return(boneOffsets);
}

void bonesToSSBO(ref App app, VkBuffer dst, uint syncIndex) {
  // Convert time to animation ticks and wrap it
  auto t = SDL_GetTicks() - app.time[STARTUP];

  double timeInTicks = (t / 10000.0f) * app.animations[app.animation].ticksPerSecond;
  double currentTick = fmod(timeInTicks, app.animations[app.animation].duration / app.animations[app.animation].ticksPerSecond);
  //SDL_Log("%f = %f  %f", t/ 1000.0f, timeInTicks, currentTick);
  Matrix[] offsets = app.getBoneOffsets(currentTick);

  uint size = cast(uint)(Matrix.sizeof * offsets.length);

  void* data;
  VkBuffer stagingBuffer;
  VkDeviceMemory stagingBufferMemory;

  app.createBuffer(&stagingBuffer, &stagingBufferMemory, size);
  vkMapMemory(app.device, stagingBufferMemory, 0, size, 0, &data);
  memcpy(data, &offsets[0], size);
  vkUnmapMemory(app.device, stagingBufferMemory);

  VkBufferCopy copyRegion = {
    srcOffset : 0, // Offset in source buffer
    dstOffset : 0, // Offset in destination buffer
    size : size // Size to copy
  };

  vkCmdCopyBuffer(app.renderBuffers[syncIndex], stagingBuffer, dst, 1, &copyRegion);

  VkBufferMemoryBarrier bufferBarrier = {
      sType : VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
      srcAccessMask : VK_ACCESS_TRANSFER_WRITE_BIT, // Data was written by transfer
      dstAccessMask : VK_ACCESS_SHADER_READ_BIT,    // Shader will read it
      srcQueueFamilyIndex : VK_QUEUE_FAMILY_IGNORED,
      dstQueueFamilyIndex : VK_QUEUE_FAMILY_IGNORED,
      buffer : dst, // The SSBO buffer itself
      offset : 0,
      size : VK_WHOLE_SIZE // Barrier applies to the whole buffer
  };

  vkCmdPipelineBarrier(
      app.renderBuffers[syncIndex],
      VK_PIPELINE_STAGE_TRANSFER_BIT,    // Source stage: Transfer (copy)
      VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, // Destination stage: Vertex shader reads
      0, // dependencyFlags
      0, null, // memoryBarriers
      1, &bufferBarrier, // bufferMemoryBarriers (our SSBO barrier)
      0, null // imageMemoryBarriers
  );
  app.frameDeletionQueue.add((){
    vkDestroyBuffer(app.device, stagingBuffer, app.allocator);
    vkFreeMemory(app.device, stagingBufferMemory, app.allocator);
  });
}

