/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : Geometry;
import vector : x,y,z;
import vertex : Vertex;
import matrix : Matrix, multiply;

struct Bounds {
  float[3] min = [ float.max, float.max, float.max];
  float[3] max = [-float.max,-float.max,-float.max];
}

void update(ref Bounds b, const Vertex v){
  if (v.x < b.min[0]) b.min[0] = v.x;
  if (v.y < b.min[1]) b.min[1] = v.y;
  if (v.z < b.min[2]) b.min[2] = v.z;

  if (v.x > b.max[0]) b.max[0] = v.x;
  if (v.y > b.max[1]) b.max[1] = v.y;
  if (v.z > b.max[2]) b.max[2] = v.z;
}

void update(ref Geometry obj, string[] mNames, Matrix gTransform) {
  foreach (mName; mNames){   //node.meshes) {
    auto mesh = obj.meshes[mName];

    float[3] localMin = mesh.bounds.min;
    float[3] localMax = mesh.bounds.max;

    float[3][8] corners = [
      localMin,
      [localMax.x, localMin.y, localMin.z],
      [localMin.x, localMax.y, localMin.z],
      [localMin.x, localMin.y, localMax.z],
      [localMax.x, localMax.y, localMin.z],
      [localMax.x, localMin.y, localMax.z],
      [localMin.x, localMax.y, localMax.z],
      localMax
    ];

    foreach (corner; corners) {
        float[3] transformedCorner = gTransform.multiply(corner);

        obj.bounds.min[0] = fmin(obj.bounds.min[0], transformedCorner.x);
        obj.bounds.min[1] = fmin(obj.bounds.min[1], transformedCorner.y);
        obj.bounds.min[2] = fmin(obj.bounds.min[2], transformedCorner.z);

        obj.bounds.max[0] = fmax(obj.bounds.max[0], transformedCorner.x);
        obj.bounds.max[1] = fmax(obj.bounds.max[1], transformedCorner.y);
        obj.bounds.max[2] = fmax(obj.bounds.max[2], transformedCorner.z);
    }
  }
}
