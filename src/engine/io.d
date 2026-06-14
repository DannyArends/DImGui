/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.file : exists, isFile, isDir, dirEntries, SpanMode;

size_t fread(SDL_IOStream* fp, void* buffer, size_t n, size_t size) { return(SDL_ReadIO(fp, buffer, n * size)); }
size_t fwrite(SDL_IOStream* fp, void* buffer, size_t n, size_t size) { return(SDL_WriteIO(fp, buffer, n * size)); }
ulong tell(SDL_IOStream* fp){ return(SDL_TellIO(fp)); }
ulong seek(SDL_IOStream* fp, int offset, SDL_IOWhence whence){ return(SDL_SeekIO(fp, offset, whence)); }
ulong fsize(const(char)* path, bool verbose = true){
  path = fixPath(path);
  SDL_IOStream* fp = SDL_IOFromFile(path, "rb");
  if(fp == null) {
    if(verbose) { SDL_Log("[ERROR] couldn't open file '%s'\n", path); }
    return 0;
  }
  ulong size = SDL_GetIOSize(fp);
  SDL_CloseIO(fp);
  return(size);
}

string fixPath(string path){
  version(Android) { } else { if(!path.startsWith("app/src/main/assets/")) return "app/src/main/assets/" ~ path; }
  return path;
}

void ensureWorldDir() {
  string path = fixPath(format("data/world/"));
  version (Android) { path = format("%s/%s", fromStringz(SDL_GetAndroidInternalStoragePath()), path); }
  SDL_CreateDirectory(toStringz(path));
}

const(char)* fixPath(const(char)* path){ return toStringz(fixPath(cast(string)fromStringz(path))); }

/** Read content of a file as a char[] */
char[] readFile(const(char)* path, uint verbose = 0) {
  path = fixPath(path);
  SDL_IOStream* fp = null;
  for(int retry = 0; retry < 3 && fp == null; retry++) {
    fp = SDL_IOFromFile(path, "rb"); if(fp == null) SDL_Delay(1);
  }
  version(Android) SDL_Log("readFile: '%s' -> %s", path, fp == null ? "NOT FOUND".ptr : "opened".ptr);
  if(fp == null){ return []; }

  auto sz = SDL_GetIOSize(fp);
  if(sz <= 0) { SDL_CloseIO(fp); return []; }

  char[] content = new char[](cast(size_t)sz);
  size_t readTotal = 0, nRead = 1;
  char* buffer = &content[0];
  while (readTotal < content.length && nRead != 0) {
    nRead = fp.fread(buffer, 1, cast(size_t)(content.length - readTotal));
    readTotal += nRead;
    buffer += nRead;
  }
  SDL_CloseIO(fp);

  if(readTotal != content.length) SDL_Log("[ERROR] read %db, expected %db\n", readTotal, content.length);
  if(verbose) SDL_Log("readFile: loaded %d bytes\n", readTotal);
  return content;
}

/** Write content of a char[] to a file */
void writeFile(const(char)* path, char[] content, uint verbose = 0) {
  path = fixPath(path);
  version (Android) { path = toStringz(format("%s/%s", fromStringz(SDL_GetAndroidInternalStoragePath()), fromStringz(path))); }
  version (Android) SDL_Log("writeFile: writing to '%s' (%d bytes)", path, content.length);
  SDL_IOStream* fp = SDL_IOFromFile(path, "w");
  if(fp == null) { SDL_Log("[ERROR] couldn't open file '%s'\n", path); return; }

  size_t writeTotal = 0, nWrite = 1;
  char* buffer = &content[0];
  while (writeTotal < content.length && nWrite != 0) {
    nWrite = fp.fwrite(buffer,1, cast(size_t)(content.length - writeTotal));
    writeTotal += nWrite;
    buffer += nWrite;
  }
  SDL_CloseIO(fp);

  if(writeTotal != content.length) SDL_Log("[ERROR] write %db, expected %db\n", writeTotal, content.length);
  if(verbose) SDL_Log("writeFile: wrote %d bytes\n", writeTotal);
}

version(Android) {
  // SDL does not provide the ability to scan folders, and on android we need to use the jni
  // dir() is the wrapper function provided
  string[] dir(const(char)* path, string pattern = "*", bool shallow = true) { 
    return(listDirContent(path, pattern, shallow)); 
  }

  struct JNI {
    JNIEnv* env;
    auto opDispatch(string m, Args...)(Args args) { mixin("return (*env)." ~ m ~ "(env, args);"); }
  }

  // listDirContent uses SDL to get jni the environment, and obtain a link to the asset_manager via jni calls
  string[] listDirContent(const(char)* path = "", string pattern = "*", bool shallow = true, uint verbose = 0) {
    auto j = JNI(cast(JNIEnv*)SDL_GetAndroidJNIEnv());
    auto activity = SDL_GetAndroidActivity();
    auto activity_class = j.GetObjectClass(activity);
    auto getAssets = j.GetMethodID(activity_class, "getAssets".toStringz, "()Landroid/content/res/AssetManager;".toStringz);
    auto asset_manager = j.CallObjectMethod(activity, getAssets);
    auto asset_class = j.GetObjectClass(asset_manager);
    auto list_method = j.GetMethodID(asset_class, "list".toStringz, "(Ljava/lang/String;)[Ljava/lang/String;".toStringz);
    jstring path_object = j.NewStringUTF(path);
    auto files_object = cast(jobjectArray)j.CallObjectMethod(asset_manager, list_method, path_object);
    auto length = j.GetArrayLength(files_object);
    if (verbose) SDL_Log("listDirContent %s: %d entries", path, length);

    string[] files;
    for (int i = 0; i < length; i++) {
      jstring jstr = cast(jstring)j.GetObjectArrayElement(files_object, i);
      if (jstr == null) continue;
      const(char)* cstr = j.GetStringUTFChars(jstr, null);
      if (cstr == null) { j.DeleteLocalRef(jstr); continue; }
      string fn = to!string(cstr);
      j.ReleaseStringUTFChars(jstr, cstr);
      if (fn.length) {
        string s = to!string(path);
        fn = format("%s%s%s", s, (s.length && s[$-1] == '/' ? "" : "/"), fn);
        if (globMatch(fn, pattern)) files ~= fn;
        if (!shallow && isdir(fn.toStringz)) files ~= listDirContent(fn.toStringz, pattern, shallow, verbose);
      }
      j.DeleteLocalRef(jstr);
    }
    j.DeleteLocalRef(files_object);
    j.DeleteLocalRef(path_object);
    j.DeleteLocalRef(activity);
    j.DeleteLocalRef(asset_manager);
    j.DeleteLocalRef(activity_class);
    return(files);
  }

  // We shim ontop of our listDir some functions on Android
  bool isdir(const(char)* path){ return(dirExists(path)); }
  bool dirExists(const(char)* path){ return(listDirContent(path).length > 0); }

  // isFile uses SDL on Android
  bool isfile(const(char)* path) {
    SDL_IOStream *rw = SDL_IOFromFile(path, "rb");
    if (rw == null) return false;
    SDL_CloseIO(rw);
    return true;
  }

  bool exists(const(char)* path) { return(isfile(path) || dirExists(path)); }

}else{ // Version SDL/OS, just use D to get the dir() functionality

  bool exists (const(char)* path) { return(exists(cast(string)fromStringz(path))); }

  /** Content of a directory */
  string[] dir(const(char)* dirPath, string pattern = "*", bool shallow = true) { 
    string path = cast(string)fromStringz(fixPath(dirPath));
    auto mode = SpanMode.shallow;
    if(!shallow) mode = SpanMode.depth;
    auto entries = dirEntries(path, pattern, mode).map!(a => a.name).array;
    return(entries);
  }

  /** Helper function to determine if a path is a file */
  bool isfile(const(char)* filePath) {
    string path = cast(string)fromStringz(fixPath(filePath));
    try {
      if (path.exists() && path.isFile) return(true);
    } catch (Exception e) { SDL_Log("path %s was not a file", path.ptr); }
    return(false);
  }

  /** Helper function to determine if a path is a file */
  bool isdir(const(char)* dirPath) {
    string path = cast(string)fromStringz(fixPath(dirPath));
    try {
      if (path.exists() && path.isDir) return(true);
    } catch (Exception e) { SDL_Log("path %s was not a directory", path.ptr); }
    return(false);
  }
}
