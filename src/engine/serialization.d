/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : readFile, writeFile;

enum uint WORLD_MAGIC = 0xCA1DE4A;

// TODO: replace per-subsystem flatten/unflatten (block/water/clouds/dwarf/vegetation) with a generic @Persist-UDA + .tupleof serializer for WorldData

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

