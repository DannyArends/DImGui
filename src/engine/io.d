/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import includes;

import std.algorithm : map, filter;
import std.array : array;
import std.conv : to;
import std.stdio : File;
import std.file : exists, isFile, dirEntries, SpanMode;
import std.string : toStringz;
import std.zlib : UnCompress;

/** Read content of a file as a uint[]
 */
char[] readFile(const(char*) path, bool verbose = false) {
  SDL_RWops* fp = SDL_RWFromFile(path, "rb");
  if(fp == null) { SDL_Log("[ERROR] couldn't open file '%s'\n", path); return []; }

  char[] content;
  content.length = cast(size_t)SDL_RWsize(fp);

  size_t readTotal = 0, nRead = 1;
  char* bPtr = &content[0];
  while (readTotal < content.length && nRead != 0) {
    nRead = SDL_RWread(fp, bPtr, 1, cast(size_t)(content.length - readTotal));
    readTotal += nRead;
    bPtr += nRead;
  }
  SDL_RWclose(fp);

  if(readTotal != content.length) SDL_Log("[ERROR] read %db, expected %db\n", readTotal, content.length);
  if(verbose) SDL_Log("readFile: loaded %d bytes\n", readTotal);
  return content;
}

/** Content of a directory
 */
immutable(char)*[] dir(string path, string pattern = "*", bool shallow = true) { 
  auto mode = SpanMode.shallow;
  if(!shallow) mode = SpanMode.depth;
  return(dirEntries(path, pattern, mode).filter!(a => a.isFile).map!(a => a.name.toStringz).array);
}

/** Helper function to determine if a path is a file
 */
bool isfile(string path) {
  try {
    if (path.exists() || path.isFile) return(true);
  } catch (Exception e) { SDL_Log("path %s was not a file", path.ptr); }
  return(false);
}

bool isfile(const(char)* path) { return(isfile(to!string(path))); }

/** Load a gzip file
 */
string loadGzfile (const string path, uint chunkSize = 1024) {
  string content = "";
  if (!path.isfile) { return(content); }

  auto uc = new UnCompress();
  foreach (chunk; File(path).byChunk(chunkSize)) {
    auto uncompressed = uc.uncompress(chunk);
    content ~= to!string(uncompressed);
  }
  content ~= to!string(uc.flush());  // flush the compression buffer
  return(content);
}

