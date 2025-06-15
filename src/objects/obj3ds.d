/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import std.format : format;
import std.conv : to;
import std.string : toStringz, fromStringz;

import geometry : Instance, Geometry, rotate, scale;
import io : tell, fread, seek;
import vertex : Vertex;

/** 3DS
 */
class Obj3DS : Geometry {
  this(){
    instances = [Instance()];
    name = (){ return(typeof(this).stringof); };
  }
}

struct Material {
  float[4] ambient  = [1.0f, 1.0f, 1.0f, 1.0f];
  float[4] specular = [1.0f, 1.0f, 1.0f, 1.0f];
  float[4] diffuse  = [1.0f, 1.0f, 1.0f, 1.0f];
}

T[N][] readData(T, uint N)(SDL_RWops* fp) {
  ushort l_qty;
  fp.fread(&l_qty, 1, ushort.sizeof);
  T[N][] values = new T[N][l_qty];
  for(size_t i = 0; i < l_qty; i++) {
    for(size_t j = 0; j < N; j++) {
      fp.fread(&values[i][j], 1, T.sizeof);
    }
  }
  return(values);
}

const(char)* readString(SDL_RWops* fp) {
  char l_char;
  string rstring;
  do {
    fp.fread(&l_char, 1, char.sizeof);
    rstring ~= cast(char)l_char;
  } while (l_char != '\0');
  return(toStringz(rstring));
}

enum cTypes {ambient = 0, specular = 1, diffuse = 2 }

Obj3DS loadFromFile(const(char)* path, bool trace = true) {
  if(trace) SDL_Log("Loading: %s", path);
  version (Android){ }else{ path = toStringz(format("app/src/main/assets/%s", fromStringz(path))); }
  ushort l_chunk_id;
  uint l_chunk_length;
  Obj3DS object = new Obj3DS();
  Material[string] materials;
  const(char)* material;
  SDL_RWops* fp = SDL_RWFromFile(path, "rb");
  if(trace) SDL_Log("Fp: %p", fp);
  long filesize = SDL_RWsize(fp);
  if(trace) SDL_Log("fize: %d", filesize);
  cTypes cType;
  while (fp.tell() < filesize) {
    fp.fread(&l_chunk_id, 1, ushort.sizeof);         // Read the chunk id
    fp.fread(&l_chunk_length, 1, uint.sizeof);     // Read the chunk length
    auto l_chunk_size = l_chunk_length - 6;
    //SDL_Log("Chunk: 0x%.4x, length: %d", l_chunk_id, l_chunk_size);
    switch(l_chunk_id) {
      case 0x4d4d: break; // MAIN3DS
      case 0x0002:
        int fversion;
        fp.fread(&fversion, 1, l_chunk_size);
        if(trace) SDL_Log("Version: %d", fversion);
      break; // MAIN3DS
      case 0x3d3d: break; // EDIT3DS
      case 0xb000: break; // KEYF3DS
      case 0x4000:        // EDIT_OBJECT
        auto name = fp.readString();
        if(trace) SDL_Log("Object: %s", name);
      break;
      case 0x4100: break; // OBJ_TRIMESH
      case 0x4110:        // TRI_VERTEXL
        auto vertices = fp.readData!(float, 3)();
        if(trace) SDL_Log("Number of vertices: %d", vertices.length);
        for(size_t i = 0; i < vertices.length; i++) {
          object.vertices ~= Vertex(vertices[i]);
        }
      break;
      case 0x4120:        // TRI_FACEL1
        auto poligons = fp.readData!(ushort, 4)();
        if(trace) SDL_Log("Number of poligons: %d", poligons.length);
        for(size_t i = 0; i < poligons.length; i++) {
          object.indices ~= to!(uint[3])(poligons[i][0..3]);
        }
      break;
      case 0x4130:        // TRI_MATERIAL
        material = fp.readString();
        auto poligon = fp.readData!(ushort, 1)();
        for(size_t i = 0; i < poligon.length; i++) {
          auto vertices = object.indices[(3*poligon[i][0])..(3*poligon[i][0])+3];
          foreach(v; vertices) {
            //object.vertices[v].color = materials[fromStringz(material)].diffuse;
          }
        }
        if(trace) SDL_Log("Material[%d]: %s", poligon.length, material); 
      break;
      case 0x4140:        // TRI_MAPPINGCOORS
        auto texcoord = fp.readData!(float, 2)();
        if(trace) SDL_Log("Number of texcoord: %d", texcoord.length);
        for(size_t i = 0; i < texcoord.length; i++) {
          object.vertices[i].texCoord[0] = texcoord[i][0];
          object.vertices[i].texCoord[1] = 1.0f - texcoord[i][1];
        }
      break;
      case 0x4160:        // TRI_LOCAL
        for(size_t i = 0; i < 4; i++) { fp.fread(&object.instances[0][i*4], 3, float.sizeof); }
        object.scale([0.05f, 0.05f, 0.05f]);
        object.rotate([65.0f, 0.0f, 90.0f]);
      break;
      case 0xAFFF: break; // EDIT_MATERIAL
      case 0xA000:        // MAT_NAME01
        material = fp.readString();
        materials[fromStringz(material)] = Material();
        if(trace) SDL_Log("Material definition: %s", material);
      break;
      case 0xA010: cType = cTypes.ambient; break;
      case 0xA020: cType = cTypes.specular; break;
      case 0xA030: cType = cTypes.diffuse; break;
      case 0xA300: 
        auto texture = fp.readString();
        if(trace) SDL_Log("Texture: %s", texture);
      break;
      case 0x0011:        //COL_TRU
        char[3] color;
        fp.fread(&color, 3, char.sizeof);
        if(trace) SDL_Log("- Color: [%d,%d,%d]",color[0], color[1], color[2]);
        float[3] floatcolor = color[] / 255.0f;
        if(cType == cTypes.ambient) materials[fromStringz(material)].ambient[0..3] = floatcolor;
        if(cType == cTypes.specular) materials[fromStringz(material)].specular[0..3] = floatcolor;
        if(cType == cTypes.diffuse) materials[fromStringz(material)].diffuse[0..3] = floatcolor;
      break;
      default:
        if(trace) SDL_Log("Skipping chunk: 0x%.4x", l_chunk_id);
        fp.seek(fp, l_chunk_length - 6, SEEK_CUR);
      break;
    }
  }
  return(object);
}