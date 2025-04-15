import engine;

import cube : Cube;
import geometry : Instance, computeNormals, destroyObject;
import icosahedron : Icosahedron, refineIcosahedron;
import matrix : mat4, scale, translate, rotate;
import square : Square;
import text : Text;

void createScene(ref App app){
  // Add objects
  app.objects ~= Square();
  app.objects ~= Cube();
  app.objects ~= Icosahedron();
  app.objects ~= Text(app.glyphAtlas);

  app.objects[3].instances[0] = rotate(app.objects[3].instances[0], [0.0f, 90.0f, 0.0f]);

  // Add a couple of instances to object 0
  for(int x = -10; x < 10; x++) {
    for(int z = -10; z < 10; z++) {
      mat4 instance;
      auto scalefactor = 0.25f;
      instance = scale(instance, [scalefactor, scalefactor, scalefactor]);
      instance = translate(instance, [cast(float) x /4.0f, -1.0f, cast(float)z /4.0f]);
      if(x <= 0 && z <= 0) app.objects[0].instances ~= Instance(5, instance);
      if(x > 0 && z > 0) app.objects[0].instances ~= Instance(6, instance);
      if(x <= 0 && z > 0) app.objects[0].instances ~= Instance(7, instance);
    }
  }
  app.objects[2].refineIcosahedron(4);
  app.objects[2].computeNormals();
  app.objects[2].instances[0] = scale(app.objects[2].instances[0], [5.0f, 5.0f, 5.0f]);

  app.objects[2].instances[0].tid = 6;
  app.objects[2].instances[0] = translate(app.objects[2].instances[0], [10.0f, 6.0f, 2.0f]);

  //Buffer the objects
  for (uint i = 0; i < app.objects.length; i++) {
    app.objects[i].buffer(app);
  }
}
