/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : readFile, writeFile;

enum uint WORLD_MAGIC = 0xCA1DE4A;

bool readWorldData(T)(const(char)* path, out T[] data, out uint h) {
  auto raw = readFile(path);
  if(raw.length < uint[2].sizeof) return false;
  if((cast(uint[])raw)[0] != WORLD_MAGIC) return false;
  h = (cast(uint[])raw)[1];
  data = cast(T[])raw[uint[2].sizeof..$].dup;
  return true;
}

void writeWorldData(T)(const(char)* path, T[] data, uint h) {
  uint[2] header = [WORLD_MAGIC, h];
  writeFile(path, cast(char[])(cast(ubyte[])header ~ cast(ubyte[])data));
}
