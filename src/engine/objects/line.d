/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : paletteOrdinal;
import vector : vAdd, vMul;

/** Line */
class Line : Geometry {
  this(float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]){
    float[3] def = [-1.0f, cast(float)paletteOrdinal(color), color[3]];
    vertices = [
      Vertex([ 0.0f, 0.0f, 0.0f ], [0.0f, 0.0f, 0.0f], def, [ 0.0f, 0.0f ]),
      Vertex([ 0.0f, 1.0f, 0.0f ], [0.0f, 0.0f, 0.0f], def, [ 0.0f, 0.0f ])
    ];
    indices = [0, 1];
    instances = [DrawInstance()];

    topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    onTick = (){ this.deAllocate = true; };
    mName = typeof(this).stringof;
  }
}

/** Ray */
alias float[3][2] Ray;

/** Create a Line from a Ray */
Line createLine(Ray ray, float length = 50){
  Line line = new Line();
  line.vertices[0].position = ray[0];
  line.vertices[1].position = ray[0].vAdd(ray[1].vMul(length));
  return(line);
}
