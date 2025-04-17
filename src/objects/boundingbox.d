import includes;

import cube : Cube;
import geometry : Geometry;
import vertex : Vertex;

struct BoundingBox {
  Geometry geometry = {
    vertices : [
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),

      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ])
    ],
    indices : [0, 1,  0, 3,  0, 4,  1, 2, 
               1, 5,  2, 3,  2, 6,  3, 7, 
               4, 5,  4, 7,  5, 6,  6, 7],
    topology : VK_PRIMITIVE_TOPOLOGY_LINE_LIST
  };
  alias geometry this;

  @property @nogc pure float[3] min() nothrow const { return(vertices[0].position); }
  @property @nogc pure float[3] max() nothrow const { return(vertices[6].position); }

  @property @nogc pure float[3] scale() nothrow const {
    float[3] scale = vertices[0].position[] - vertices[6].position[];
    return(scale);
  }

  @nogc void setDimensions(float[3] min, float[3] max) nothrow {
    vertices[0].position = [min[0], min[1], min[2]]; vertices[1].position = [max[0], min[1], min[2]];
    vertices[2].position = [max[0], max[1], min[2]]; vertices[3].position = [min[0], max[1], min[2]];
    vertices[4].position = [min[0], min[1], max[2]]; vertices[5].position = [max[0], min[1], max[2]];
    vertices[6].position = [max[0], max[1], max[2]]; vertices[7].position = [min[0], max[1], max[2]];
  }

  @property @nogc pure float[3] center() nothrow const {
    float[3] mid = (vertices[0].position[] + vertices[6].position[]) / 2.0f;
    return(mid);
  }
}

/* Compute the bounding box for object */
BoundingBox computeBoundingBox(Geometry object) {
  BoundingBox box;
  float[3][2] size = [[float.infinity, float.infinity, float.infinity], 
                      [-float.infinity, -float.infinity, -float.infinity]];

  for (size_t i = 0; i < object.vertices.length; i++) {
    if (object.vertices[i].position[0] < size[0][0]) size[0][0] = object.vertices[i].position[0];
    if (object.vertices[i].position[0] > size[1][0]) size[1][0] = object.vertices[i].position[0];

    if (object.vertices[i].position[1] < size[0][1]) size[0][1] = object.vertices[i].position[1];
    if (object.vertices[i].position[1] > size[1][1]) size[1][1] = object.vertices[i].position[1];

    if (object.vertices[i].position[2] < size[0][2]) size[0][2] = object.vertices[i].position[2];
    if (object.vertices[i].position[2] > size[1][2]) size[1][2] = object.vertices[i].position[2];
  }
  box.setDimensions(size[0], size[1]);
  box.instances[0].matrix = object.instances[0].matrix;
  return(box);
}

