/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.algorithm : sort;
import std.format : format;
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
import assimp : loadOpenAsset;
import obj3ds : loadFromFile;
import turtle : Turtle;
import vertex : Vertex, VERTEX, INSTANCE, INDEX;

/** Create a scene for rendering
 */
void createScene(ref App app){

  SDL_Log("createScene: Add a Square");
  app.objects ~= new Square();
  app.objects[($-1)].position([0.0f, -1.0f,0.0f]);
  for(int x = -75; x < 75; x++) {
    for(int z = -75; z < 75; z++) {
      mat4 instance;  // Add a instances of object 0
      auto scalefactor = 0.5f;
      instance = translate(instance, [cast(float) x, -1.0f, cast(float)z]);
      app.objects[($-1)].instances ~= Instance(instance);
    }
  }

  SDL_Log("createScene: Add a Cube");
  app.objects ~= new Cube();
  app.objects[($-1)].position([3.0f, 0.0f, 3.0f]);
  app.objects[($-1)].texture(app.textures, "image");

  SDL_Log("createScene: Add an Icosahedron");
  app.objects ~= new Icosahedron();
  app.objects[($-1)].refineIcosahedron(3);
  app.objects[($-1)].texture(app.textures, "sun");
  app.objects[($-1)].computeNormals();
  app.objects[($-1)].scale([3.0f, 3.0f, 3.0f]);
  app.objects[($-1)].position([10.0f, 2.0f, 2.0f]);
  app.objects[($-1)].onFrame = (ref App app, ref Geometry obj, float dt){
      auto p = obj.position;
      obj.rotate([dt, 0.0f, 0.0f]);
      obj.position(p);
    };

  SDL_Log("createScene: Add Text");
  app.objects ~= new Text(app);
  app.objects[($-1)].rotate([90.0f, 0.0f, 0.0f]);
  app.objects[($-1)].position([5.0f, 2.0f, 2.0f]);
  app.objects[($-1)].onFrame = (ref App app, ref Geometry obj, float dt){
      obj.rotate([0.0f, 2 * dt, 4 * dt]);
    };

  SDL_Log("createScene: Add viking room OpenAsset");
  app.objects ~= app.loadOpenAsset("data/objects/viking_room.obj");
  app.objects[($-1)].texture(app.textures, "viking");
  app.objects[($-1)].rotate([180.0f, 0.0f, 90.0f]);
  app.objects[($-1)].position([3.0f,-0.5f, 1.0f]);

  SDL_Log("createScene: Add L-System");
  app.objects ~= new Turtle(createLSystem());
  app.objects[($-1)].computeNormals();
  app.objects[($-1)].position([2.0f, 1.0f, -2.0f]);


  SDL_Log("createScene: Add PDB object");
  auto protein = loadProteinCif("data/objects/3kql.cif");

  app.objects ~= new AtomCloud(protein.atoms());
  app.objects[($-1)].scale([0.1f, 0.1f, 0.1f]);
  app.objects[($-1)].position([15.0f, 1.0f, 15.0f]);
  foreach (p; sort(protein.keys)) {
    if (protein[p].isAAChain()) {
      app.objects ~= new Backbone(protein[p]);
      app.objects[($-1)].scale([0.1f, 0.1f, 0.1f]);
      app.objects[($-1)].position([15.0f, 1.0f, 15.0f]);
      app.objects ~= new AminoAcidCloud(protein[p]);
      app.objects[($-1)].scale([0.1f, 0.1f, 0.1f]);
      app.objects[($-1)].position([15.0f, 1.0f, 15.0f]);
    }
  }

  SDL_Log("createScene: Add 3DS");
  app.objects ~= loadFromFile("data/objects/Dragon.3ds");
  app.objects[($-1)].texture(app.textures, "Dragon_ground");
  app.objects[($-1)].computeNormals();
  app.objects[($-1)].position([10.0f, -1.0f, -4.0f]);

  SDL_Log("createScene: Add cottage OpenAsset");
  app.objects ~= app.loadOpenAsset("data/objects/cottage_fbx.fbx");
  app.objects[($-1)].scale([1.0f, 0.5f, 1.0f]);
  app.objects[($-1)].rotate([180.0f, 0.0f, 90.0f]);
  app.objects[($-1)].position([4.75f, 0.0f, -0.75f]);

  SDL_Log("createScene: Add Spider OpenAsset");
  app.objects ~= app.loadOpenAsset("data/objects/Spider.fbx");
  app.objects[($-1)].animation = 11;
  app.objects[($-1)].position([1.0f, -8.5f, 3.0f]);
  app.objects[($-1)].scale([0.01f, 0.01f, 0.01f]);

  SDL_Log("createScene: Add Wolf OpenAsset");
  app.objects ~= app.loadOpenAsset("data/objects/Wolf.fbx");
  app.objects[($-1)].animation = 1;
  app.objects[($-1)].position([0.0f, -0.5f, 0.0f]);
  app.objects[($-1)].scale([0.015f, 0.015f, 0.015f]);

  if (app.compute.enabled) {
    SDL_Log("createScene: Add ParticleSystem");
    app.objects ~= app.compute.system;
  }
  SDL_Log("createScene: Finished");
}

