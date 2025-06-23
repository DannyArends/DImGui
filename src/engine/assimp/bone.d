/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import animation : Node, calculateGlobalTransform;
import assimp : OpenAsset, name, toMatrix;
import buffer : createBuffer, StageBuffer;
import matrix : Matrix, inverse, rotate, scale, position, transpose;
import sdl : STARTUP;

struct Bone {
  Matrix offset;          /// Inverse bind pose matrix
  uint index;             /// Bone index

  @property float[3] bindPosition() { return offset.inverse().position(); }
}

float[uint][string] loadBones(OpenAsset asset, aiMesh* mesh, ref Bone[string] globalBones) {
  float[uint][string] weights;
  for (uint b = 0; b < mesh.mNumBones; b++) {
    auto aiBone = mesh.mBones[b];
    if (aiBone.mNumWeights == 0) continue; // No weights, no effect, skip
    string name = format("%s:%s", asset.mName, name(aiBone.mName));
    if (!(name in globalBones)) { // New bone, add it to the global bones
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

Matrix[] getBoneOffsets(App app) {
  auto t = SDL_GetTicks() - app.time[STARTUP];

  Matrix[] boneOffsets;
  boneOffsets.length = app.bones.length;
  foreach(obj; app.objects){
    if(obj.animations.length > 0) {

      double timeInTicks = (t / 10000.0f) * obj.animations[obj.animation].ticksPerSecond;
      double currentTick = fmod(timeInTicks, obj.animations[obj.animation].duration / obj.animations[obj.animation].ticksPerSecond);

      Matrix root;
      app.calculateGlobalTransform(obj, boneOffsets, obj.rootnode, root, currentTick);
    }
  }
  //SDL_Log("Computed: %d offsets", nOffsets);
  return(boneOffsets);
}

void bonesToSSBO(ref App app, VkBuffer dst, uint syncIndex) {
  Matrix[] offsets = app.getBoneOffsets();

  StageBuffer buffer = {
    size :  cast(uint)(Matrix.sizeof * offsets.length),
    frame : app.totalFramesRendered + app.framesInFlight
  };

  app.createBuffer(&buffer.sb, &buffer.sbM, buffer.size);
  vkMapMemory(app.device, buffer.sbM, 0, buffer.size, 0, &buffer.data);
  memcpy(buffer.data, &offsets[0], buffer.size);
  vkUnmapMemory(app.device, buffer.sbM);

  VkBufferCopy copyRegion = {
    srcOffset : 0, // Offset in source buffer
    dstOffset : 0, // Offset in destination buffer
    size : buffer.size // Size to copy
  };

  vkCmdCopyBuffer(app.renderBuffers[syncIndex], buffer.sb, dst, 1, &copyRegion);

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
  app.bufferDeletionQueue.add((bool force){
    if (force || (app.totalFramesRendered >= buffer.frame)){
      vkDestroyBuffer(app.device, buffer.sb, app.allocator);
      vkFreeMemory(app.device, buffer.sbM, app.allocator);
      return(true);
    }
    return(false);
  });
}

