/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import std.random : uniform;
import std.math : abs;

import vector : Vector, vMul, vAdd, magnitude;
import vertex : Vertex;
import quaternion : Quaternion;

/** A single particle
 */
struct Particle {
  float[3] position;
  float[3] velocity;
  float[4] color;
  float mass = 1.0f;
  float life = 1.0f;

  float[3] energy(){ return(velocity.vMul(mass)); }
}

/** (Re)Spawn a particle at i */
Vertex spawn(ref Particle[] particles, uint i, float[3] impulse = Vector.init, float delta = 0.2f, float[4] color = Quaternion.init) {
  particles[i].position = [0.0f, 0.0f, 0.0f];
  particles[i].velocity = [uniform(impulse[0] - delta, impulse[0] + delta),
                           uniform(impulse[1] - 4*delta, impulse[1] + 4*delta), 
                           uniform(impulse[2] - delta, impulse[2] + delta)];
  particles[i].life = uniform(0.1f, 1.0f);
  particles[i].mass = uniform(1.0f, 5.0f);
  particles[i].color = color;
  return(Vertex(particles[i].position, [0.0f,0.0f], particles[i].color));
}

/** Age a particle with a certain rate, and (Re) spawn when dead 
 * We use: totalEnergy = Gravity + current Energy = new velocity & position
 */
Vertex[] age(ref Particle[] particles, float[3] gravity = Vector([0.0f, -0.1f, 0.0f]), float floor = 0.0f, float rate = 0.0001f) {
  Vertex[] vertices;
  vertices.length = particles.length;
  for (uint i = 0; i < particles.length; i++) {
    particles[i].life -= (rate + uniform(0.0f, 0.0005f));
    if(particles[i].life < 0.0f || abs(particles[i].velocity.magnitude) < 0.05) particles.spawn(i, [0.0f, 2.0f, 0.0f]);

    float[3] tE = gravity.vMul(particles[i].mass).vAdd(particles[i].energy);
    particles[i].velocity[] = tE[] / particles[i].mass;

    if(particles[i].position[1] + particles[i].velocity[1] < 0){
      particles[i].velocity[1] = -particles[i].velocity[1];
      particles[i].velocity[] = particles[i].velocity[] / 4.0f;
    }
    particles[i].color[2] = 1.0f - particles[i].life;
    particles[i].position[] = particles[i].position[] + particles[i].velocity[];
    vertices[i] = Vertex(particles[i].position, [0.0f,0.0f], particles[i].color);
  }
  return(vertices);
}
