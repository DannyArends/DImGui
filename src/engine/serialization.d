/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : readFile, writeFile;

enum uint WORLD_MAGIC = 0xCA1DE4A;
enum uint WORLD_SCHEMA = 1;
struct Section { string key; ubyte[] data; }

struct Persistable {
  Section[] delegate() save;
  void delegate(const ubyte[][string] blobs) load;
}

/** Serialize all registered sections into one WORLD_MAGIC container */
void saveSections(const(char)* path, Section[] sections) {
  ubyte[] blob;
  void putU(uint x) { blob ~= (cast(ubyte*)&x)[0 .. uint.sizeof]; }
  putU(WORLD_MAGIC); putU(WORLD_SCHEMA); putU(cast(uint)sections.length);
  foreach(ref s; sections) {
    putU(cast(uint)s.key.length); blob ~= cast(ubyte[])s.key.dup;
    putU(cast(uint)s.data.length); blob ~= s.data;
  }
  writeFile(path, cast(char[])blob);
}

/** Read the container and dispatch each section to the matching registered `load` by id */
ubyte[][string] loadSections(const(char)* path) {
  ubyte[][string] blobs;
  auto raw = cast(ubyte[])readFile(path);
  if(raw.length < 3 * uint.sizeof) return blobs;
  size_t off = 0;
  uint getU() { uint x = *cast(uint*)(raw.ptr + off); off += uint.sizeof; return x; }
  bool have(size_t n) { return off + n <= raw.length; }

  if(getU() != WORLD_MAGIC || getU() != WORLD_SCHEMA) {
    SDL_Log("loadSections: magic/schema mismatch — regenerating world");
    return blobs;
  }
  uint count = getU();
  foreach(_; 0 .. count) {
    if(!have(uint.sizeof)) { SDL_Log("loadSections: truncated key header"); break; }
    uint keyN = getU();
    if(!have(keyN + uint.sizeof)) { SDL_Log("loadSections: truncated key"); break; }
    string key = cast(string)(cast(char[])raw[off .. off + keyN]).idup; off += keyN;
    uint dataN = getU();
    if(!have(dataN)) { SDL_Log("loadSections: truncated data for '%s'", toStringz(key)); break; }
    blobs[key] = raw[off .. off + dataN].dup; off += dataN;
  }
  return blobs;
}
