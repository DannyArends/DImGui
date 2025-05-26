// DImGui - COMPUTE SHADER
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#version 460

struct Particle {
  vec3 position;    /// Position
  vec3 velocity;    /// Velocity
  float mass;       /// Mass
  float life;       /// Life
  float random;     /// Random number
};

//size of a workgroup for compute
layout (local_size_x = 256) in;

//descriptor bindings for the pipeline
layout(set = 0, binding = 0) uniform ParticleUniformBuffer {
  vec4 position;
  vec4 gravity;
  float floor;
  float deltaTime;
} ubo;

layout(set = 0, binding = 1) readonly buffer lastFrame {
   Particle pIn[];
};

layout(set = 0, binding = 2) buffer currentFrame {
   Particle pOut[];
};

void main(){
  uint index = gl_GlobalInvocationID.x;

  Particle particleIn = pIn[index];
  vec3 particleEnergy = particleIn.velocity * particleIn.mass;
  pOut[index].life = particleIn.life - (particleIn.random);
  vec3 totalEnergy = ubo.gravity.xyz * particleIn.mass + particleEnergy;
  vec3 newVelocity = totalEnergy / particleIn.mass;

  vec3 newPosition = particleIn.position + newVelocity;
  if(newPosition[1] < ubo.floor) { // Bounce
    particleIn.position[1] = ubo.floor;
    newVelocity[1] = -newVelocity[1];
    newVelocity = newVelocity / (1.5 * particleIn.mass);
  }

  pOut[index].position = particleIn.position + newVelocity;
  pOut[index].velocity = newVelocity;
}
