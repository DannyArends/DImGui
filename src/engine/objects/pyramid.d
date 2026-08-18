/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

/** Pyramid: square base at Y=-0.5 rising to a single apex at Y=+0.5 (base-anchored like Cube).
    radius/length/depth scale base-width / height / base-depth. For spikes, teeth, claws, horn tips. */
class Pyramid : Geometry {
  this(float[4] color = [1.0f, 1.0f, 1.0f, 1.0f]){
    enum float n = 0.4472f, u = 0.8944f;   // face normal (1:0.5 rise, normalised)
    vertices = [
      // Front (Normal: +Z/+Y): FL, FR, apex
      Vertex([ -0.5f, -0.5f,  0.5f ], [ 0.0f, 0.0f ], [  0.0f, n,  u ], -1.0f, [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.5f, -0.5f,  0.5f ], [ 1.0f, 0.0f ], [  0.0f, n,  u ], -1.0f, [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f,  0.5f,  0.0f ], [ 0.5f, 1.0f ], [  0.0f, n,  u ], -1.0f, [ 1.0f, 0.0f, 0.0f, 1.0f ]),

      // Right (Normal: +X/+Y): FR, BR, apex
      Vertex([  0.5f, -0.5f,  0.5f ], [ 0.0f, 0.0f ], [  u, n, 0.0f ], -1.0f, [ 0.0f, 0.0f, -1.0f, 1.0f ]),
      Vertex([  0.5f, -0.5f, -0.5f ], [ 1.0f, 0.0f ], [  u, n, 0.0f ], -1.0f, [ 0.0f, 0.0f, -1.0f, 1.0f ]),
      Vertex([  0.0f,  0.5f,  0.0f ], [ 0.5f, 1.0f ], [  u, n, 0.0f ], -1.0f, [ 0.0f, 0.0f, -1.0f, 1.0f ]),

      // Back (Normal: -Z/+Y): BR, BL, apex
      Vertex([  0.5f, -0.5f, -0.5f ], [ 0.0f, 0.0f ], [  0.0f, n, -u ], -1.0f, [ -1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([ -0.5f, -0.5f, -0.5f ], [ 1.0f, 0.0f ], [  0.0f, n, -u ], -1.0f, [ -1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.0f,  0.5f,  0.0f ], [ 0.5f, 1.0f ], [  0.0f, n, -u ], -1.0f, [ -1.0f, 0.0f, 0.0f, 1.0f ]),

      // Left (Normal: -X/+Y): BL, FL, apex
      Vertex([ -0.5f, -0.5f, -0.5f ], [ 0.0f, 0.0f ], [ -u, n, 0.0f ], -1.0f, [ 0.0f, 0.0f, 1.0f, 1.0f ]),
      Vertex([ -0.5f, -0.5f,  0.5f ], [ 1.0f, 0.0f ], [ -u, n, 0.0f ], -1.0f, [ 0.0f, 0.0f, 1.0f, 1.0f ]),
      Vertex([  0.0f,  0.5f,  0.0f ], [ 0.5f, 1.0f ], [ -u, n, 0.0f ], -1.0f, [ 0.0f, 0.0f, 1.0f, 1.0f ]),

      // Base (Normal: -Y): FL, FR, BR, BL
      Vertex([ -0.5f, -0.5f,  0.5f ], [ 0.0f, 0.0f ], [ 0.0f, -1.0f, 0.0f ], -1.0f, [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.5f, -0.5f,  0.5f ], [ 1.0f, 0.0f ], [ 0.0f, -1.0f, 0.0f ], -1.0f, [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([  0.5f, -0.5f, -0.5f ], [ 1.0f, 1.0f ], [ 0.0f, -1.0f, 0.0f ], -1.0f, [ 1.0f, 0.0f, 0.0f, 1.0f ]),
      Vertex([ -0.5f, -0.5f, -0.5f ], [ 0.0f, 1.0f ], [ 0.0f, -1.0f, 0.0f ], -1.0f, [ 1.0f, 0.0f, 0.0f, 1.0f ])
    ];
    indices = [ 0, 1, 2,                // front
                3, 4, 5,                // right
                6, 7, 8,                // back
                9,10,11,                // left
               12,13,14,  14,15,12 ];   // base
    instances = [DrawInstance()];
    meshes["Pyramid"] = Mesh([0, cast(uint)vertices.length]);
    mName = typeof(this).stringof;
  }
}