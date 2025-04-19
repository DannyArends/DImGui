// Copyright Danny Arends 2025
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

import engine;

import std.algorithm : map, startsWith, splitter;
import std.array : array, split;
import std.conv : to;

import geometry : Geometry, rotate;
import io : readFile;
import vertex : Vertex;

struct WaveFront {
  Geometry geometry;
  alias geometry this;
}

WaveFront loadWavefront(ref App app, const(char)* path) {
  char[] content = cast(char[])readFile(path); // Open for reading
  string filecontent = to!string(content);

  float[3][] positions; // per vertex position x,y,z
  float[3][] normals; // per vertex normals x,y,z
  float[2][] texCoords; // per vertex texture mapcoords x,y,z
  int[][] triangles;

  foreach (line; content.split("\n")) {
    if (line.startsWith("v ")) { // Vertex coordinate
      positions ~= line[2..$].splitter.map!(to!float).array[0 .. 3];
    }else if (line.startsWith("vt ")) {
      texCoords ~= line[3..$].splitter.map!(to!float).array[0 .. 2];
    }else if (line.startsWith("vn ")) {
      normals ~= line[3..$].splitter.map!(to!float).array[0 .. 3];
    }else if (line.startsWith("f ")) { // Triangle
      foreach (pol; line[2..$].splitter) {
        auto split = pol.splitter("/").map!(to!int).array;
        split[] = split[] - 1;
        triangles ~= split;
      }
    }
  }
  WaveFront obj = WaveFront();
  foreach (p; positions) { obj.vertices ~= Vertex(p); }
  foreach (t; triangles) {
    if(t.length > 1) {
      obj.vertices[t[0]].texCoord = texCoords[t[1]];
      obj.vertices[t[0]].texCoord[1] = 1.0f - obj.vertices[t[0]].texCoord[1];
    }
    if(t.length > 2) obj.vertices[t[0]].normal = normals[t[2]];
    obj.indices ~= t[0];
  }
  obj.rotate([0.0f, 0.0f, -90.0f]);
  if(app.verbose) SDL_Log("Vertices %d, indices %d", obj.vertices.length, obj.indices.length);
  return(obj);
}
