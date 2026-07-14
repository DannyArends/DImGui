/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : readFile, writeFile;

enum uint WORLD_MAGIC = 0xCA1DE4A;
enum uint WORLD_SCHEMA = 1;
enum SectionID : uint { WorldDiffs = 1, Blocks = 2, Water = 3, Clouds = 4, Vegetation = 5, Dwarfs = 6, Stockpiles = 7 }

struct Persistable {
  SectionID id;                                         /// TypeID
  ubyte[] delegate(out uint meta) save;                 /// produce this section's bytes, set its meta
  void delegate(const(ubyte)[] body, uint meta) load;   /// consume this section's bytes + meta
}

/** Serialize all registered sections into one WORLD_MAGIC container */
void saveSections(const(char)* path, Persistable[] parts) {
  ubyte[] blob;
  uint[3] header = [WORLD_MAGIC, WORLD_SCHEMA, cast(uint)parts.length];
  blob ~= cast(ubyte[])header;
  foreach(ref p; parts) {
    uint meta;
    auto payload = p.save(meta);
    uint[3] shead = [cast(uint)p.id, meta, cast(uint)payload.length];
    blob ~= cast(ubyte[])shead;
    blob ~= payload;
  }
  writeFile(path, cast(char[])blob);
}

/** Read the container and dispatch each section to the matching registered `load` by id */
bool loadSections(const(char)* path, Persistable[] parts) {
  auto raw = cast(ubyte[])readFile(path);
  if(raw.length < uint[3].sizeof) { return(false); }
  auto head = cast(uint[])raw[0 .. uint[3].sizeof];
  if(head[0] != WORLD_MAGIC || head[1] != WORLD_SCHEMA) {
    SDL_Log("loadSections: magic/schema mismatch (got %u/%u) — regenerating world", head[0], head[1]);
    return(false);
  }
  uint count = head[2];
  size_t off = uint[3].sizeof;
  foreach(_; 0 .. count) {
    if(off + uint[3].sizeof > raw.length) { SDL_Log("loadSections: truncated header"); return(false); }
    auto sh = cast(uint[])raw[off .. off + uint[3].sizeof]; off += uint[3].sizeof;
    uint id = sh[0], meta = sh[1], len = sh[2];
    if(off + len > raw.length) { SDL_Log("loadSections: truncated section %u", id); return(false); }
    auto body = raw[off .. off + len]; off += len;
    foreach(ref p; parts) { if(cast(uint)p.id == id) { p.load(body, meta); break; } }
  }
  return(true);
}

/** Reads a WORLD_MAGIC-tagged file into T[] data, meta is a uint the caller can use (e.g. block.d/dwarf.d store a live counter like nextID here) */
bool readData(T)(const(char)* path, out T[] data, out uint meta) {
  auto raw = readFile(path);
  if(raw.length < uint[2].sizeof || (cast(uint[])raw)[0] != WORLD_MAGIC) { return(false); }
  meta = (cast(uint[])raw)[1];
  auto content = raw[uint[2].sizeof..$];
  if(content.length % T.sizeof != 0) {
    SDL_Log("readData!%s: size mismatch (body=%d bytes, T.sizeof=%d) — stale save file? Regenerating.", T.stringof.ptr, content.length, T.sizeof);
    return(false);
  }
  data = cast(T[])content.dup;
  return(true);
}

/** Writes `data` to a WORLD_MAGIC-tagged file, with `meta` as one uint the caller can also save. */
void writeData(T)(const(char)* path, T[] data, uint meta) {
  uint[2] header = [WORLD_MAGIC, meta];
  writeFile(path, cast(char[])(cast(ubyte[])header ~ cast(ubyte[])data));
}

