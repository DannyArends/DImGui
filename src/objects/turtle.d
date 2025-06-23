/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : Instance, Geometry;
import lsystem : LSystem, Symbols;
import vector : vAdd, vMul, normalize;
import vertex : Vertex, VERTEX, INSTANCE, INDEX;

/** Turtle
 */
class Turtle : Geometry {
  uint seed;
  LSystem lsystem;
  float[3][] stack;
  float[3] origin = [0.0f, 0.0f, 0.0f];
  float[4][2] colors = [[0.5f, 0.5f, 0.0f, 1.0f],
                       [1.0f, 1.0f, 0.2f, 1.0f]];

  this(LSystem system) {
    seed = uniform(0, 256);
    lsystem = system;

    vertices = [Vertex(origin, [0.0f, 0.0f], colors[0]), Vertex([0.0f, 0.0f, 0.0f], [0.0f, 0.0f], colors[1])];
    indices = [0, 1];
    instances = [Instance()];

    topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST;

    /** onFrame handler aging the particles every frame */
    onFrame = (ref App app, ref Geometry obj, float dt){ (cast(Turtle)obj).age(); };
    name = (){ return(typeof(this).stringof); };
  }

  void age() {
    if(!lsystem.iterate()){ return; }
    auto rnd = Random(this.seed);
    //SDL_Log("state: %s", to!string(lsystem.state).toStringz);
    stack = [];
    float[3] direction = [0.0f, 0.1f, 0.0f];
    float[3] lpos = [0.0f, 0.0f, 0.0f];
    float[3] cpos = [0.0f, 0.0f, 0.0f];
    float[4] color = colors[0];
    vertices = [Vertex(origin, [0.0f, 0.0f], colors[0]), Vertex([0.0f, 0.0f, 0.0f], [0.0f, 0.0f], colors[1])];
    indices = [0, 1];
    foreach (i, symbol; lsystem.state) {
      switch (symbol) {
        case Symbols.Origin: cpos = origin; break;
        case Symbols.Point: 
          if(cpos != lpos){
            //SDL_Log("%d %f %f %f -> %f %f %f", i,lpos[0],lpos[1],lpos[2],cpos[0],cpos[1],cpos[2]);
            vertices ~= Vertex(lpos, [0.0f, 0.0f], color);
            vertices ~= Vertex(cpos, [0.0f, 0.0f], color);
            lpos = cpos;
            indices ~= [cast(uint)indices.length, cast(uint)indices.length+1];
          }
        break;
        case Symbols.Move:  cpos = cpos.vAdd(direction); break;
        case Symbols.Color:
          color[0] = uniform(colors[0][0], colors[1][0], rnd);
          color[1] = uniform(colors[0][1], colors[1][1], rnd);
          color[2] = uniform(colors[0][2], colors[1][2], rnd);
        break;
        case Symbols.Rotate: 
          float rx = uniform(-1.0f, 1.0f, rnd);
          float ry = uniform(-1.0f, 1.0f, rnd);
          float rz = uniform(-1.0f, 1.0f, rnd);
          direction = direction.vAdd([rx, ry, rz]);
          direction = direction.normalize().vMul(0.1f);
          break;
        case Symbols.PushLoc: stack ~= cpos; break;
        case Symbols.PopLoc:  if(stack.length > 1) {
                                cpos = stack[($-1)]; 
                                stack = stack[0 .. ($-1)]; 
                              }
                              break;
        case Symbols.Forward: cpos = cpos.vAdd([0.1f, 0.0f, 0.0f]); break;
        case Symbols.Backward: cpos = cpos.vAdd([-0.1f, 0.0f, 0.0f]); break;
        case Symbols.Left: cpos = cpos.vAdd([0.0f, 0.0f, 0.1f]);  break;
        case Symbols.Right: cpos = cpos.vAdd([0.0f, 0.0f, -0.1f]);  break;
        case Symbols.Up: cpos = cpos.vAdd([0.0f, 0.1f, 0.0f]); break;
        case Symbols.Down: cpos = cpos.vAdd([0.0f, -0.1f, 0.0f]); break;
        default: break;
      }
    }
    buffers[VERTEX] = false;
    buffers[INDEX] = false;
  }
}
