import std.array : array;
import std.file : dirEntries, SpanMode;
import std.algorithm : map, filter;

string[] dir(string path, string pattern = "*", bool shallow = true) { 
  auto mode = SpanMode.shallow;
  if(!shallow) mode = SpanMode.depth;
  return(dirEntries(path, pattern, mode).filter!(a => a.isFile).map!(a => a.name).array);
}
