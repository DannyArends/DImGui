/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import geometry : Geometry;
import vertex : Vertex;

/** Cube
 */
class Cube : Geometry {
  this(){
    vertices = [
      Vertex([  0.5f,  0.5f,  0.5f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 1.0f, 1.0f ]),
      Vertex([ -0.5f,  0.5f,  0.5f ], [  1.0f, 0.0f ], [ 1.0f, 0.0f, 1.0f, 1.0f ]),
      Vertex([ -0.5f, -0.5f,  0.5f ], [  1.0f, 1.0f ], [ 1.0f, 0.0f, 1.0f, 1.0f ]),
      Vertex([  0.5f, -0.5f,  0.5f ], [  0.0f, 1.0f ], [ 1.0f, 0.0f, 1.0f, 1.0f ]),

      Vertex([  0.5f,  0.5f,  0.5f ], [  0.0f, 0.0f ], [ 1.0f, 1.0f, 0.0f, 1.0f ]),
      Vertex([  0.5f, -0.5f,  0.5f ], [  1.0f, 0.0f ], [ 1.0f, 1.0f, 0.0f, 1.0f ]),
      Vertex([  0.5f, -0.5f, -0.5f ], [  1.0f, 1.0f ], [ 1.0f, 1.0f, 0.0f, 1.0f ]),
      Vertex([  0.5f,  0.5f, -0.5f ], [  0.0f, 1.0f ], [ 1.0f, 1.0f, 0.0f, 1.0f ]),

      Vertex([  0.5f,  0.5f,  0.5f ], [  0.0f, 0.0f ], [ 0.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([  0.5f,  0.5f, -0.5f ], [  1.0f, 0.0f ], [ 0.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.5f,  0.5f, -0.5f ], [  1.0f, 1.0f ], [ 0.0f, 1.0f, 1.0f, 1.0f ]),
      Vertex([ -0.5f,  0.5f,  0.5f ], [  0.0f, 1.0f ], [ 0.0f, 1.0f, 1.0f, 1.0f ]),

      Vertex([ -0.5f,  0.5f,  0.5f ], [  0.0f, 0.0f ], [ 0.0f, 0.0f, 1.0f, 1.0f ]),
      Vertex([ -0.5f,  0.5f, -0.5f ], [  1.0f, 0.0f ], [ 0.0f, 0.0f, 1.0f, 1.0f ]),
      Vertex([ -0.5f, -0.5f, -0.5f ], [  1.0f, 1.0f ], [ 0.0f, 0.0f, 1.0f, 1.0f ]),
      Vertex([ -0.5f, -0.5f,  0.5f ], [  0.0f, 1.0f ], [ 0.0f, 0.0f, 1.0f, 1.0f ]),

      Vertex([ -0.5f, -0.5f, -0.5f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.5f, -0.5f, -0.5f ], [  1.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.5f, -0.5f,  0.5f ], [  1.0f, 1.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([ -0.5f, -0.5f,  0.5f ], [  0.0f, 1.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),

      Vertex([  0.5f, -0.5f, -0.5f ], [  0.0f, 0.0f ], [ 0.0f, 1.0f, 0.0f, 1.0f ]),
      Vertex([ -0.5f, -0.5f, -0.5f ], [  1.0f, 0.0f ], [ 0.0f, 1.0f, 0.0f, 1.0f ]),
      Vertex([ -0.5f,  0.5f, -0.5f ], [  1.0f, 1.0f ], [ 0.0f, 1.0f, 0.0f, 1.0f ]),
      Vertex([  0.5f,  0.5f, -0.5f ], [  0.0f, 1.0f ], [ 0.0f, 1.0f, 0.0f, 1.0f ])
    ];
    indices = [0, 1, 2,   2, 3, 0,      // front
               4, 5, 6,   6, 7, 4,      // right
               8, 9,10,  10,11, 8,      // top
              12,13,14,  14,15,12,      // left
              16,17,18,  18,19,16,      // bottom
              20,21,22,  22,23,20];     // backside
    name = (){ return(typeof(this).stringof); };
  }
}
