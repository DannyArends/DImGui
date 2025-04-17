import includes;

import geometry : Geometry;
import vertex : Vertex;

struct Line {
  Geometry geometry = {
    vertices : [
      Vertex([  0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([  0.0f, 1.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 1.0f, 1.0f, 1.0f ])
    ],
    indices : [0, 1],
    topology : VK_PRIMITIVE_TOPOLOGY_LINE_LIST
  };
  alias geometry this;
}

