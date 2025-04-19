/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import std.random : uniform;
import std.math : abs;

import vector : Vector, vMul, vAdd;
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
void spawn(ref Particle[] particles, size_t i, float[3] impulse = Vector.init, float delta = 0.1f, float[4] color = Quaternion.init) {
  particles[i].position = [0.0f, 0.0f, 0.0f];
  particles[i].velocity = [uniform(impulse[0] - delta, impulse[0] + delta),
                           uniform(impulse[1] - delta, impulse[1] + delta), 
                           uniform(impulse[2] - delta, impulse[2] + delta)];
  particles[i].life = uniform(0.1f, 1.0f);
  particles[i].mass = uniform(1.0f, 5.0f);
  particles[i].color = color;
}

/** Age a particle with a certain rate, and (Re)Spawn when dead 
 * We use: totalEnergy = Gravity + current Energy = new velocity & position
 */
void age(ref Particle[] particles, float[3] gravity = Vector([0.0f, -0.1f, 0.0f]), float floor = 0.0f, float rate = 0.0001f) {
  for (size_t i = 0; i < particles.length; i++) {
    particles[i].life -= (rate + uniform(0.0f, 0.0005f));
    if(particles[i].life < 0.0f) { particles.spawn(i); }

    float[3] tE = gravity.vMul(particles[i].mass).vAdd(particles[i].energy);
    particles[i].velocity[] = tE[] / particles[i].mass;
    particles[i].position[] = particles[i].position[] + particles[i].velocity[];
  }
}
