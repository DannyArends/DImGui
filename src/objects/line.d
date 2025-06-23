/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import boundingbox : BoundingBox;
import geometry : Instance, Geometry;
import matrix : multiply;
import vector : vAdd, vSub, vMul, x, y, z;
import vertex : Vertex;

/** Line
 */
class Line : Geometry {
  this(){
    vertices = [
      Vertex([ 0.0f, 0.0f, 0.0f ], [  0.0f, 0.0f ], [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([ 0.0f, 1.0f, 0.0f ], [  0.0f, 0.0f ], [ 0.0f, 1.0f, 0.0f, 1.0f ])
    ];
    indices = [0, 1];
    instances = [Instance()];

    topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    onTick = (ref App app, ref Geometry obj) { obj.deAllocate = true; }; // Set the deAllocate flag onTick
    name = (){ return(typeof(this).stringof); };
  }
}

/** Ray
 */
alias float[3][2] Ray;

/** Create a Line from a Ray
 */
Line createLine(Ray ray, float length = 50){
  Line line = new Line();
  line.vertices[0].position = ray[0];
  line.vertices[1].position = ray[0].vAdd(ray[1].vMul(length));
  return(line);
}

