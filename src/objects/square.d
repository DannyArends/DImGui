/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import includes;
import geometry : Geometry;
import vertex : Vertex;

struct Square {
  Geometry geometry = {
    vertices : [ Vertex([-0.5f, 0.0f, -0.5f], [1.0f, 1.0f], [1.0f, 0.8f, 0.8f, 1.0f]), 
                 Vertex([ 0.5f, 0.0f, -0.5f], [0.0f, 1.0f], [0.8f, 1.0f, 0.8f, 1.0f]),
                 Vertex([ 0.5f, 0.0f,  0.5f], [0.0f, 0.0f], [0.8f, 0.8f, 1.0f, 1.0f]),
                 Vertex([-0.5f, 0.0f,  0.5f], [1.0f, 0.0f], [0.8f, 0.8f, 1.0f, 1.0f]) ],
    indices : [0, 2, 1, 0, 3, 2],
    topology: VK_PRIMITIVE_TOPOLOGY_LINE_LIST
  };

  alias geometry this;
}

