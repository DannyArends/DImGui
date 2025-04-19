/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import includes;

import std.algorithm : map, filter;
import std.array : array;
import std.file : dirEntries, SpanMode;
import std.string : toStringz;

uint[] readFile(const(char*) path, bool verbose = false) {
  SDL_RWops* fp = SDL_RWFromFile(path, "rb");
  if(fp == null) { SDL_Log("[ERROR] couldn't open file '%s'\n", path); return []; }

  uint[] content;
  content.length = cast(size_t)SDL_RWsize(fp);

  size_t readTotal = 0, nRead = 1;
  uint* cPos = &content[0];
  while (readTotal < content.length && nRead != 0) {
    nRead = SDL_RWread(fp, cPos, 1, cast(size_t)(content.length - readTotal));
    readTotal += nRead;
    cPos += nRead;
  }
  SDL_RWclose(fp);

  if(readTotal != content.length) SDL_Log("[ERROR] read %db, expected %db\n", readTotal, content.length);
  if(verbose) SDL_Log("readFile: loaded %d bytes\n", readTotal);
  return content;
}

immutable(char)*[] dir(string path, string pattern = "*", bool shallow = true) { 
  auto mode = SpanMode.shallow;
  if(!shallow) mode = SpanMode.depth;
  return(dirEntries(path, pattern, mode).filter!(a => a.isFile).map!(a => a.name.toStringz).array);
}
