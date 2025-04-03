import std.array : array;
import std.file : dirEntries, SpanMode;
import std.algorithm : map, filter;
import std.string : toStringz;

import includes;

string[] dir(string path, string pattern = "*", bool shallow = true) { 
  auto mode = SpanMode.shallow;
  if(!shallow) mode = SpanMode.depth;
  return(dirEntries(path, pattern, mode).filter!(a => a.isFile).map!(a => a.name).array);
}

/* Load a file using SDL2 */
uint[] readFile(string path) {
  SDL_RWops *rw = SDL_RWFromFile(toStringz(path), "rb");
  if (rw == null){
    SDL_Log("readFile: couldn't open file '%s'\n", toStringz(path));
    return [];
  }
  uint[] res;

  res.length = cast(size_t)SDL_RWsize(rw);
  size_t nb_read_total = 0, nb_read = 1;
  uint* cpos = &res[0];
  while (nb_read_total < res.length && nb_read != 0) {
    nb_read = SDL_RWread(rw, cpos, 1, cast(size_t)(res.length - nb_read_total));
    nb_read_total += nb_read;
    cpos += nb_read;
  }
  SDL_RWclose(rw);
  if (nb_read_total != res.length) SDL_Log("readFile: loaded %db, expected %db\n", nb_read_total, res.length);
  SDL_Log("Loaded %d bytes\n", nb_read_total);
  return res;
}

