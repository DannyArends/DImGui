/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.algorithm : sort;
import std.random : uniform;
import std.string : toStringz;

import cube : Cube;
import geometry : Geometry, Instance, computeNormals, position, rotate, scale, texture;
import icosahedron : Icosahedron, refineIcosahedron;
import lsystem : createLSystem;
import matrix : mat4, scale, translate, rotate;
import particlesystem : ParticleSystem;
import pdb : AtomCloud, Backbone, AminoAcidCloud, loadProteinCif;
import square : Square;
import text : Text;
import turtle : Turtle;
import vertex : Vertex, VERTEX, INSTANCE, INDEX;
import wavefront : loadWavefront;

/** Create a scene for rendering
 */
void createScene(ref App app){

  SDL_Log("createScene: Add a Square");
  app.objects ~= new Square();
  app.objects[0].position([0.0f,-0.5f,0.0f]);
/*  for(int x = -50; x < 50; x++) {
    for(int z = -50; z < 50; z++) {
      mat4 instance;  // Add a instances of object 0
      auto scalefactor = 0.25f;
      instance = scale(instance, [scalefactor, scalefactor, scalefactor]);
      instance = translate(instance, [cast(float) x /4.0f, -1.0f, cast(float)z /4.0f]);
      if(x <= 0 && z <= 0) app.objects[0].instances ~= Instance(-1, instance);
      if(x > 0 && z > 0) app.objects[0].instances ~= Instance(-1, instance);
      if(x > 0 && z <= 0) app.objects[0].instances ~= Instance(-1, instance);
      if(x <= 0 && z > 0) app.objects[0].instances ~= Instance(-1, instance);
    }
  }

  SDL_Log("createScene: Add a Cube");
  app.objects ~= new Cube();
  //app.objects[1].computeNormals();
  app.objects[1].position([3.0f, 0.0f, 3.0f]);
  app.objects[1].texture(app.textures, "image");

  SDL_Log("createScene: Add an Icosahedron");
  app.objects ~= new Icosahedron();
  app.objects[2].texture(app.textures, "sun");
  app.objects[2].refineIcosahedron(3);
  app.objects[2].computeNormals();
  app.objects[2].scale([3.0f, 3.0f, 3.0f]);
  app.objects[2].position([10.0f, 2.0f, 2.0f]);
  app.objects[2].onFrame = (ref App app, ref Geometry obj, float dt){
      auto p = obj.position;
      obj.rotate([dt, 0.0f, 0.0f]);
      obj.position(p);
    };

  SDL_Log("createScene: Add Text");
  app.objects ~= new Text(app);
  app.objects[3].rotate([90.0f, 0.0f, 0.0f]);
  app.objects[3].position([5.0f, 2.0f, 2.0f]);
  app.objects[2].computeNormals();
  app.objects[3].onFrame = (ref App app, ref Geometry obj, float dt){
      obj.rotate([0.0f, 2 * dt, 4 * dt]);
    };

  SDL_Log("createScene: Add Wavefront");
  app.objects ~= app.loadWavefront("data/objects/viking_room.obj");
  app.objects[4].texture(app.textures, "viking");
  app.objects[4].rotate([0.0f, 180.0f, 0.0f]);
  app.objects[4].position([2.0f, 0.0f, 0.0f]);

  /** Stress test with 20 x 20 instanced rendering of a 10k / 50k Particle system (50k x 400 = ~20mio particles) */
  /*
  for(int x = -10; x < 10; x++) {
    for(int z = -10; z < 10; z++) {
      mat4 instance;  // Add a instances of object 0
      auto scalefactor = 0.25f;
      instance = scale(instance, [scalefactor, scalefactor, scalefactor]);
      instance = translate(instance, [cast(float) x * 4, 2.0f, cast(float)z * 4]);
      app.objects[5].instances ~= Instance(-1, instance);
    }
  } */

/*
  SDL_Log("createScene: Add L-System");
  app.objects ~= new Turtle(createLSystem());
  app.objects[5].computeNormals();
  app.objects[5].position([2.0f, 1.0f, -2.0f]);


  SDL_Log("createScene: Add PDB object");
  auto protein = loadProteinCif("data/objects/3kql.cif");
  uint i = 5;
  app.objects ~= new AtomCloud(protein.atoms());
  app.objects[i].scale([0.5f, 0.5f, 0.5f]);
  i++;
  foreach (p; sort(protein.keys)) {
    if (protein[p].isAAChain()) {
      app.objects ~= new Backbone(protein[p]);
      app.objects[i].scale([0.5f, 0.5f, 0.5f]);
      i++;
      app.objects ~= new AminoAcidCloud(protein[p]);
      app.objects[i].scale([0.5f, 0.5f, 0.5f]);
      i++;
    }
  } */

  if (app.compute.enabled) {
    SDL_Log("createScene: Add ParticleSystem");
    app.objects ~= app.compute.system;
  }
  SDL_Log("createScene: Finished");
}

