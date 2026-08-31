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

unittest {
  import io : writePath, exists;

  void putU(ref ubyte[] b, uint x){ b ~= (cast(ubyte*)&x)[0 .. uint.sizeof]; }

  SDL_Init(SDL_INIT_AUDIO | SDL_INIT_VIDEO | SDL_INIT_EVENTS); scope(exit) { SDL_Quit(); }

  auto sectionsF = toStringz(writePath("unittest_sections.bin"));
  auto shortF = toStringz(writePath("unittest_short.bin"));
  auto badF = toStringz(writePath("unittest_badmagic.bin"));
  auto truncF = toStringz(writePath("unittest_truncated.bin"));
  scope(exit) foreach(f; [sectionsF, shortF, badF, truncF]){ if(exists(f)) SDL_RemovePath(f); }

  // Round-trip: save then load returns every section's bytes intact
  Section[] original = [
    Section("alpha", cast(ubyte[])[1, 2, 3, 4]),
    Section("beta",  cast(ubyte[])[]),                       // empty section
    Section("gamma", cast(ubyte[])[255, 0, 128, 64, 32]),
  ];
  saveSections(sectionsF, original);
  auto blobs = loadSections(sectionsF);
  assert(blobs.length == 3, format("wrong number of sections restored: got %d", blobs.length));
  assert(blobs["alpha"] == cast(ubyte[])[1, 2, 3, 4], "alpha data corrupted");
  assert(blobs["beta"].length == 0, "empty section not preserved");
  assert(blobs["gamma"] == cast(ubyte[])[255, 0, 128, 64, 32], "gamma data corrupted");

  // Short file (< 4-uint header) yields no sections
  writeFile(shortF, cast(char[])[0, 1, 2]);
  assert(loadSections(shortF).length == 0, "short file should yield no sections");

  // Wrong magic yields no sections (triggers regenerate path)
  ubyte[] bad;
  putU(bad, 0xDEADBEEF); putU(bad, WORLD_SCHEMA); putU(bad, WORLD_PLATFORM); putU(bad, 0);
  writeFile(badF, cast(char[])bad);
  assert(loadSections(badF).length == 0, "bad magic should yield no sections");

  // Truncated section (claims 100 data bytes, only 2 present) stops cleanly
  ubyte[] trunc;
  putU(trunc, WORLD_MAGIC); putU(trunc, WORLD_SCHEMA); putU(trunc, WORLD_PLATFORM); putU(trunc, 1);
  putU(trunc, 3); trunc ~= cast(ubyte[])"key";
  putU(trunc, 100); trunc ~= cast(ubyte[])[1, 2];
  writeFile(truncF, cast(char[])trunc);
  assert("key" !in loadSections(truncF), "truncated section must not be loaded");
}