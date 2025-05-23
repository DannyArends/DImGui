/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.random : uniform;
import std.math : abs;

import particle : Particle;
import geometry : Instance, Geometry;
import vector : Vector, vMul, vAdd, magnitude, normalize;
import vertex : Vertex, VERTEX, INSTANCE, INDEX;

/** ParticleSystem
 */
class ParticleSystem : Geometry {
  float[3] position = [15.0f, 8.0f, -8.0f];
  float[3][2] impulse = [[-2.0f, -1.0f, -1.0f],
                         [2.0f, 8.0f, 10.0f]];
  float[3] gravity = [0.0f, -0.005f, 0.0f];
  float[4][2] color = [[0.0f, 0.5f, 0.6f, 1.0f],
                       [0.1f, 1.0f, 1.0f, 1.0f]];
  float floor = -1.0f;
  float rate = 0.000001f;
  Particle[] particles;

  this(uint nParticles = 10000, bool verbose = false) {
    particles.length = nParticles;
    vertices.length = nParticles;
    indices.length = nParticles;
    instances = [Instance()];
    for(uint i = 0; i < nParticles; i++) { spawn(i); }

    topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST;

    /** onFrame handler aging the particles every frame */
    onFrame = (ref App app, ref Geometry obj){ (cast(ParticleSystem)obj).age(); };
    name = (){ return(typeof(this).stringof); };
  }

  /** (Re)Spawn a particle at i */
  void spawn(uint i) {
    auto r = uniform(color[0][0], color[1][0]);
    auto g = uniform(color[0][1], color[1][1]);
    auto b = uniform(color[0][2], color[1][2]);
    vertices[i] = Vertex(position, [0.0f,0.0f], [r, g, b, 1.0f]);
    indices[i] = i;
    particles[i].velocity = [uniform(impulse[0][0], impulse[1][0]),
                             uniform(impulse[0][1], impulse[1][1]),
                             uniform(impulse[0][2], impulse[1][2])];
    particles[i].velocity[].normalize;
    particles[i].velocity[] = particles[i].velocity[].vMul(uniform(0.01f, 0.1f));
    particles[i].life = uniform(0.1f, 1.0f);
    particles[i].mass = uniform(1.0f, 5.0f);
    particles[i].random = uniform(0.0f, 0.005f);
  }

  /** Age all particles */
  void age() {
    for (uint i = 0; i < particles.length; i++) {
      particles[i].life -= (rate + particles[i].random);
      if(particles[i].life < 0.0f) spawn(i);

      float[3] tE = gravity.vMul(particles[i].mass).vAdd(particles[i].energy);
      particles[i].velocity[] = tE[] / particles[i].mass;

      if(vertices[i].position[1] + particles[i].velocity[1] < floor){
        vertices[i].position[1] = floor;
        particles[i].velocity[1] = -particles[i].velocity[1];
        particles[i].velocity[] = particles[i].velocity[] / (1.5 * particles[i].mass);
      }
      vertices[i].position[] = vertices[i].position[] + particles[i].velocity[];
    }
    buffers[VERTEX] = false;
  }
}
