/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import particle : Particle;
import geometry : Instance, Geometry;
import vector : Vector, vMul, vAdd, magnitude, normalize;
import vertex : Vertex, VERTEX, INSTANCE, INDEX;
import quaternion : xyzw;

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

  this(uint nParticles = 1000, bool verbose = false) {
    particles.length = nParticles;
    vertices.length = nParticles;
    indices.length = nParticles;
    instances = [Instance()];
    for(uint i = 0; i < nParticles; i++) { spawn(i); }

    topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST;

    /** onFrame handler aging the particles every frame */
    onFrame = (ref App app, ref Geometry obj, float dt){ (cast(ParticleSystem)obj).age(); };
    name = (){ return(typeof(this).stringof); };
  }

  /** (Re)Spawn a particle at i */
  void spawn(uint i) {
    auto r = uniform(color[0][0], color[1][0]);
    auto g = uniform(color[0][1], color[1][1]);
    auto b = uniform(color[0][2], color[1][2]);
    vertices[i] = Vertex(position, [0.0f,0.0f], [r, g, b, 1.0f]);

    particles[i].position = position.xyzw;
    indices[i] = i;
    particles[i].velocity = [uniform(impulse[0][0], impulse[1][0]),
                             uniform(impulse[0][1], impulse[1][1]),
                             uniform(impulse[0][2], impulse[1][2]), 0.0f];
    particles[i].velocity[0..3] = particles[i].velocity[0..3].normalize;
    particles[i].velocity[] = particles[i].velocity[0..3].vMul(uniform(0.01f, 0.1f)).xyzw;
    particles[i].life = uniform(0.1f, 1.0f);
    particles[i].mass = uniform(1.0f, 5.0f);
    particles[i].random1 = uniform(0.0f, 0.1f);
    particles[i].random2 = uniform(0.0f, 0.1f);
  }

  /** Age all particles */
  void age() {
    for (uint i = 0; i < particles.length; i++) {
      vertices[i].position[] = particles[i].position[0..3];
    }
    buffers[VERTEX] = false;
  }
}
