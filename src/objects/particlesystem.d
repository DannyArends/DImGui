/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import particle : Particle, spawn, age;
import geometry : Geometry;

/** ParticleSystem
 */
class ParticleSystem : Geometry {
  float[3] position = [0.0f, 2.0f, 0.0f];
  Particle[] particles;

  this(uint nParticles, bool verbose = false) {
    particles.length = nParticles;
    vertices.length = nParticles;
    indices.length = nParticles;
    for(uint i = 0; i < nParticles; i++) {
      vertices[i] = particles.spawn(i, position);
      indices[i] = i;
    }
    topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
    onFrame = (ref App app, ref Geometry obj, SDL_Event e){
      ParticleSystem pSystem = cast(ParticleSystem)obj;
      pSystem.vertices = pSystem.particles.age();
      pSystem.isBuffered = false;
    };
  }
}

