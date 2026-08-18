/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import color : paletteOrdinal;

class Square : Geometry {
  this(float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]) {
    float[3] def = [-1.0f, cast(float)paletteOrdinal(color), color[3]];
    vertices = [
      Vertex([-0.5f, 0.0f, -0.5f], [0.0f, 1.0f, 0.0f], def, [0.0f, 1.0f], [1.0f, 0.0f, 0.0f, -1.0f]),
      Vertex([ 0.5f, 0.0f, -0.5f], [0.0f, 1.0f, 0.0f], def, [1.0f, 1.0f], [1.0f, 0.0f, 0.0f, -1.0f]),
      Vertex([ 0.5f, 0.0f,  0.5f], [0.0f, 1.0f, 0.0f], def, [1.0f, 0.0f], [1.0f, 0.0f, 0.0f, -1.0f]),
      Vertex([-0.5f, 0.0f,  0.5f], [0.0f, 1.0f, 0.0f], def, [0.0f, 0.0f], [1.0f, 0.0f, 0.0f, -1.0f])];
    topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    indices = [0, 2, 1, 0, 3, 2];
    instances = [DrawInstance()];
    meshes["Square"] = Mesh([0, cast(uint)vertices.length]);
    mName = typeof(this).stringof;
  };
}

