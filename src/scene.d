/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import cube : Cube;
import geometry : Instance, computeNormals, position, rotate, scale, texture;
import icosahedron : Icosahedron, refineIcosahedron;
import matrix : mat4, scale, translate, rotate;
import particlesystem : ParticleSystem;
import square : Square;
import text : Text;
import wavefront : loadWavefront;

/** Create a scene for rendering
 */
void createScene(ref App app){
  SDL_Log("createScene: Add a Square");
  app.objects ~= new Square();

  for(int x = -100; x < 100; x++) {
    for(int z = -100; z < 100; z++) {
      mat4 instance;  // Add a instances of object 0
      auto scalefactor = 0.25f;
      instance = scale(instance, [scalefactor, scalefactor, scalefactor]);
      instance = translate(instance, [cast(float) x /4.0f, -1.0f, cast(float)z /4.0f]);
      if(x <= 0 && z <= 0) app.objects[0].instances ~= Instance(5, instance);
      if(x > 0 && z > 0) app.objects[0].instances ~= Instance(6, instance);
      if(x <= 0 && z > 0) app.objects[0].instances ~= Instance(7, instance);
    }
  }

  SDL_Log("createScene: Add a Cube");
  app.objects ~= new Cube();
  app.objects[1].position([3.0f, 0.0f, 3.0f]);

  SDL_Log("createScene: Add an Icosahedron");
  app.objects ~= new Icosahedron();
  app.objects[2].texture(app.textures, "sun");
  app.objects[2].refineIcosahedron(3);
  app.objects[2].computeNormals();
  app.objects[2].scale([3.0f, 3.0f, 3.0f]);
  app.objects[2].position([10.0f, 2.0f, 2.0f]);

  SDL_Log("createScene: Add Text");
  app.objects ~= new Text(app);
  app.objects[3].rotate([90.0f, 0.0f, 0.0f]);
  app.objects[3].position([5.0f, 2.0f, 2.0f]);

  SDL_Log("createScene: Add Wavefront");
  app.objects ~= app.loadWavefront("assets/objects/viking_room.obj");
  app.objects[4].texture(app.textures, "viking");
  app.objects[4].rotate([0.0f, 180.0f, 0.0f]);
  app.objects[4].position([2.0f, 0.0f, 0.0f]);

  SDL_Log("createScene: Done");
}
