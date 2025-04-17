import engine;

import boundingbox : computeBoundingBox;
import cube : Cube;
import geometry : Instance, computeNormals, position, rotate, scale;
import icosahedron : Icosahedron, refineIcosahedron;
import matrix : mat4, scale, translate, rotate;
import square : Square;
import text : Text;

void createScene(ref App app){
  // Add objects
  app.objects ~= Square();

  for(int x = -100; x < 100; x++) {
    for(int z = -100; z < 100; z++) {
      mat4 instance;  // Add a instances to object 0
      auto scalefactor = 0.25f;
      instance = scale(instance, [scalefactor, scalefactor, scalefactor]);
      instance = translate(instance, [cast(float) x /4.0f, -1.0f, cast(float)z /4.0f]);
      if(x <= 0 && z <= 0) app.objects[0].instances ~= Instance(5, instance);
      if(x > 0 && z > 0) app.objects[0].instances ~= Instance(6, instance);
      if(x <= 0 && z > 0) app.objects[0].instances ~= Instance(7, instance);
    }
  }

  //Cube
  app.objects ~= Cube();
  app.objects[1].position([3.0f, 0.0f, 3.0f]);

  //Icosahedron test
  app.objects ~= Icosahedron();
  app.objects[2].instances[0].tid = 8;
  app.objects[2].refineIcosahedron(3);
  app.objects[2].computeNormals();
  app.objects[2].scale([5.0f, 5.0f, 5.0f]);
  app.objects[2].position([10.0f, 6.0f, 2.0f]);
  app.objects ~= computeBoundingBox(app.objects[2]);

  //Cube
  app.objects ~= Text(app.glyphAtlas);
  app.objects[4].rotate([10.0f, 75.0f, 0.0f]);
}

