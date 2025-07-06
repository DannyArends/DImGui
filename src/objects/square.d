/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : Instance, Geometry;
import vertex : Vertex;
import mesh : Mesh;

class Square : Geometry {
   this(){
    vertices = [ Vertex([-0.5f, 0.0f, -0.5f], [1.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]), 
                 Vertex([ 0.5f, 0.0f, -0.5f], [0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([ 0.5f, 0.0f,  0.5f], [0.0f, 0.0f], [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([-0.5f, 0.0f,  0.5f], [1.0f, 0.0f], [1.0f, 1.0f, 1.0f, 1.0f]) ];
    indices = [0, 2, 1, 0, 3, 2];
    instances = [Instance()];
    meshes["Square"] = Mesh([0, cast(uint)vertices.length]);
    //topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    name = (){ return(typeof(this).stringof); };
  };
}

