/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import geometry : setColor;

class Square : Geometry {
   this() {
    vertices = [ Vertex([-0.5f, 0.0f, -0.5f], [1.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]), 
                 Vertex([ 0.5f, 0.0f, -0.5f], [0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([ 0.5f, 0.0f,  0.5f], [0.0f, 0.0f], [1.0f, 1.0f, 1.0f, 1.0f]),
                 Vertex([-0.5f, 0.0f,  0.5f], [1.0f, 0.0f], [1.0f, 1.0f, 1.0f, 1.0f]) ];
    topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    indices = [0, 2, 1, 0, 3, 2];
    instances = [Instance()];
    meshes["Square"] = Mesh([0, cast(uint)vertices.length]);
    name = (){ return(typeof(this).stringof); };
  };
}

class Outline : Square {
  float highlightTime = 0.0f;

   this() { super();
    topology = VK_PRIMITIVE_TOPOLOGY_LINE_STRIP;
    indices  = [0, 1, 2, 3, 0];
    onFrame = (ref App app, ref Geometry obj, float dt) {
      auto t = (cast(Outline)obj).highlightTime += dt;
      obj.setColor([1.0f, (sin(t) + 1.0f) * 0.5f, 0.0f, 1.0f]);
    };
  };
}

