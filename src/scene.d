/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : computeNormals, computeTangents, position, rotate, scale, texture, bumpmap, opacity;
import icosahedron : refineIcosahedron;
import lsystem : createLSystem;
import matrix : scale, translate, rotate;
import pdb : loadProteinCif;
import assimp : loadOpenAsset;

/** Create a scene for rendering
 */
void createScene(ref App app){
  SDL_Log("createScene: Add a Square");
  app.objects ~= new Square();
  app.objects[($-1)].computeTangents();
  app.objects[($-1)].texture("Bump_03_base");
  app.objects[($-1)].bumpmap("Bump_03_normal");
  app.objects[($-1)].position([0.0f, -0.5f, 0.0f]);
  for(int x = -5; x <= 5; x++) {
    for(int z = -5; z <= 5; z++) {
      Matrix instance;  // Add a instances of object 0
      auto scalefactor = 5.0f;
      instance = instance.translate([0.0f, -1.0f, 0.0f]);
      instance = instance.scale([scalefactor, scalefactor, scalefactor]);
      instance = instance.translate([cast(float) x, 0.0f, cast(float)z]);
      app.objects[($-1)].instances ~= Instance(matrix: instance);
    }
  }

  SDL_Log("createScene: Add a Cube");
  app.objects ~= new Cube(color : [1.0f, 1.0f, 0.0f, 1.0f]);
  app.objects[($-1)].computeTangents();
  app.objects[($-1)].position([3.0f, 0.5f, 1.5f]);
  app.objects[($-1)].scale([0.35f, 0.35f, 0.35f]);
  app.objects[($-1)].texture("image");
  app.objects[($-1)].onFrame = (ref App app, ref Geometry obj, float dt){ obj.rotate([20 * dt, 2 * dt, 14 * dt]); };

  SDL_Log("createScene: Add a Cone");
  app.objects ~= new Cone(color : [1.0f, 0.0f, 0.0f, 1.0f]);
  app.objects[($-1)].computeTangents();
  app.objects[($-1)].position([3.0f, 0.7f, 0.5f]);
  app.objects[($-1)].scale([0.35f, 0.35f, 0.35f]);
  app.objects[($-1)].texture("image");
  app.objects[($-1)].onFrame = (ref App app, ref Geometry obj, float dt){ obj.rotate([6 * dt, 6 * dt, 12 * dt]); };

  SDL_Log("createScene: Add a Cylinder");
  app.objects ~= new Cylinder(color : [0.0f, 1.0f, 0.0f, 1.0f]);
  app.objects[($-1)].computeTangents();
  app.objects[($-1)].position([3.0f, 0.7f, -0.5f]);
  app.objects[($-1)].scale([0.35f, 0.35f, 0.35f]);
  app.objects[($-1)].texture("image");
  app.objects[($-1)].onFrame = (ref App app, ref Geometry obj, float dt){ obj.rotate([6 * dt, 6 * dt, 10 * dt]); };

  SDL_Log("createScene: Add a Torus");
  app.objects ~= new Torus(color : [0.0f, 0.0f, 1.0f, 1.0f]);
  app.objects[($-1)].computeTangents();
  app.objects[($-1)].position([3.0f, 0.5f, -1.5f]);
  app.objects[($-1)].scale([0.35f, 0.35f, 0.35f]);
  app.objects[($-1)].texture("image");
  app.objects[($-1)].onFrame = (ref App app, ref Geometry obj, float dt){ obj.rotate([6 * dt, 20 * dt, 14 * dt]); };

  SDL_Log("createScene: Add an Icosahedron");
  app.objects ~= new Icosahedron();
  app.objects[($-1)].refineIcosahedron(3);
  app.objects[($-1)].computeNormals();
  app.objects[($-1)].computeTangents();
  app.objects[($-1)].texture("earth_day");
  app.objects[($-1)].scale([2.0f, 2.0f, 2.0f]);
  app.objects[($-1)].position([5.5f, 2.0f, 2.5f]);
  app.objects[($-1)].onFrame = (ref App app, ref Geometry obj, float dt){
    obj.rotate([4 * dt, 0.0f, 0.0f]);
  };

  SDL_Log("createScene: Add Text");
  app.objects ~= new Text(app);
  app.objects[($-1)].computeNormals();
  app.objects[($-1)].computeTangents();
  app.objects[($-1)].rotate([90.0f, 0.0f, 0.0f]);
  app.objects[($-1)].position([5.0f, 1.0f, -2.0f]);
  app.objects[($-1)].scale([0.35f, 0.35f, 0.35f]);
  app.objects[($-1)].onFrame = (ref App app, ref Geometry obj, float dt){
    obj.rotate([0.0f, 2 * dt, 4 * dt]);
  };

  SDL_Log("createScene: Add L-System");
  app.objects ~= new Turtle(createLSystem());
  app.objects[($-1)].computeNormals();
  app.objects[($-1)].position([4.5f, 2.5f, -2.0f]);

  SDL_Log("createScene: Add PDB object");
  auto protein = loadProteinCif("data/objects/3kql.cif");

  app.objects ~= new AtomCloud(protein.atoms());
  app.objects[($-1)].scale([0.1f, 0.1f, 0.1f]);
  app.objects[($-1)].position([10.0f, 1.0f, -4.0f]);
  foreach (p; sort(protein.keys)) {
    if (protein[p].isAAChain()) {
      app.objects ~= new Backbone(protein[p]);
      app.objects[($-1)].scale([0.1f, 0.1f, 0.1f]);
      app.objects[($-1)].position([10.0f, 1.0f, -4.0f]);
      app.objects ~= new AminoAcidCloud(protein[p]);
      app.objects[($-1)].computeNormals();
      app.objects[($-1)].computeTangents();
      app.objects[($-1)].scale([0.1f, 0.1f, 0.1f]);
      app.objects[($-1)].position([10.0f, 1.0f, -4.0f]);
    }
  }

  if (app.hasCompute) {
    SDL_Log("createScene: Add ParticleSystem");
    app.objects ~= app.compute.system;
  }
  SDL_Log("createScene: Finished");
}
