/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : readFile, writeFile;

enum uint WORLD_MAGIC = 0xCA1DE4A;
enum uint WORLD_SCHEMA = 1;
version (Android) { enum uint WORLD_PLATFORM = 0x414E4452;
}else{ enum uint WORLD_PLATFORM = 0x57494E44; }
struct Section { string key; ubyte[] data; }

struct Persist {
  Section[] delegate() save;
  void delegate(const ubyte[][string] blobs) load;

  /** POD single-section helper: a T[] save + a T[] load, keyed by `key`. */
  static Persist pod(T)(string key, T[] delegate() save, void delegate(T[]) load) {
    return Persist(
      () => [Section(key, cast(ubyte[])save())],
      (const ubyte[][string] b) { if(auto p = key in b){ load(cast(T[])(*p)); } });
  }
}

/** Serialize all registered sections into one WORLD_MAGIC container */
void saveSections(const(char)* path, Section[] sections, bool verbose = false) {
  ubyte[] blob;
  void putU(uint x) { blob ~= (cast(ubyte*)&x)[0 .. uint.sizeof]; }
  putU(WORLD_MAGIC); putU(WORLD_SCHEMA); putU(WORLD_PLATFORM); putU(cast(uint)sections.length);
  foreach(ref s; sections) {
    if(verbose) SDL_Log("saveSections: '%s' = %d bytes", toStringz(s.key), cast(int)s.data.length);
    putU(cast(uint)s.key.length); blob ~= cast(ubyte[])s.key.dup;
    putU(cast(uint)s.data.length); blob ~= s.data;
  }
  writeFile(path, cast(char[])blob);
}

/** Read the container and dispatch each section to the matching registered `load` by id */
ubyte[][string] loadSections(const(char)* path, bool verbose = false) {
  ubyte[][string] blobs;
  auto raw = cast(ubyte[])readFile(path);
  if(raw.length < 4 * uint.sizeof) return blobs;
  size_t off = 0;
  uint getU() { uint x = *cast(uint*)(raw.ptr + off); off += uint.sizeof; return x; }
  bool have(size_t n) { return off + n <= raw.length; }

  if(getU() != WORLD_MAGIC || getU() != WORLD_SCHEMA) { SDL_Log("loadSections: magic/schema mismatch — regenerating world"); return blobs; }
  if(getU() != WORLD_PLATFORM) { SDL_Log("loadSections: platform mismatch (save from another platform) — regenerating world"); return blobs; }
  uint count = getU();
  foreach(_; 0 .. count) {
    if(!have(uint.sizeof)) { SDL_Log("loadSections: truncated key header"); break; }
    uint keyN = getU();
    if(!have(keyN + uint.sizeof)) { SDL_Log("loadSections: truncated key"); break; }
    string key = cast(string)(cast(char[])raw[off .. off + keyN]).idup; off += keyN;
    uint dataN = getU();
    if(!have(dataN)) { SDL_Log("loadSections: truncated data for '%s'", toStringz(key)); break; }
    if(verbose) SDL_Log("loadSections: '%s' = %d bytes", toStringz(key), cast(int)dataN);
    blobs[key] = raw[off .. off + dataN].dup; off += dataN;
  }
  return blobs;
}
