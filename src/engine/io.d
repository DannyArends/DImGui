import includes;

uint[] readFile(const(char*) path, bool verbose) {
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
