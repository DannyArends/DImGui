/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import includes;

import std.algorithm : map, filter;
import std.array : array;
import std.conv : to;
import std.stdio : File;
import std.path : globMatch;
import std.file : exists, isFile, dirEntries, SpanMode;
import std.string : toStringz, fromStringz;
import std.zlib : UnCompress;

/** Read content of a file as a uint[]
 */
char[] readFile(const(char*) path, uint verbose = 0) {
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

version(Android) { 

  // SDL does not provide the ability to scan folders, and on android we need to use the jni
  // dir() is the wrapper function provided
  immutable(char)*[] dir(string path, string pattern = "*", bool shallow = true) { return(listDirContent(path, pattern, shallow)); }

  // listDirContent uses SDL to get jni the environment, and obtain a link to the asset_manager via jni calls
  immutable(char)*[] listDirContent(string path = "", string pattern = "*", bool shallow = true, uint verbose = 0) {
    JNIEnv* env = cast(JNIEnv*)SDL_AndroidGetJNIEnv();
    jobject activity = cast(jobject)SDL_AndroidGetActivity();
    jclass activity_class = (*env).GetObjectClass(env, activity);
    jobject asset_manager = (*env).CallObjectMethod(env, activity, (*env).GetMethodID(env, activity_class, "getAssets", "()Landroid/content/res/AssetManager;"));

    // Query the asset_manager for the list() method
    auto list_method = (*env).GetMethodID(env, (*env).GetObjectClass(env, asset_manager), "list", "(Ljava/lang/String;)[Ljava/lang/String;");
    jstring path_object = (*env).NewStringUTF(env, toStringz(path));
    auto files_object = cast(jobjectArray)(*env).CallObjectMethod(env, asset_manager, list_method, path_object);
    auto length = (*env).GetArrayLength(env, files_object);

    // List all files in the folder
    SDL_Log("Path %s, mngr: %X, list_method: %X, nObjects: %d \n", toStringz(path), asset_manager, list_method, length);
    const(char)*[] files;
    for (int i = 0; i < length; i++) {
      // Allocate the java string, and get the filename
      jstring jstr = cast(jstring)(*env).GetObjectArrayElement(env, files_object, i);
      const(char)* fn = (*env).GetStringUTFChars(env, jstr, null);
      if (fn) {
        string filename = to!string(fn);
        string filepath =  (path ~ (path[($-1)] == '/' ? "" : "/") ~ filename);
        if (globMatch(filepath, pattern)) { 
          //SDL_Log("matching file: %s @ %s", toStringz(filename), toStringz(filepath));
          files ~= toStringz(filepath);
        }
        if (!shallow && isDir(filepath)) files ~= listDirContent(filepath, pattern, shallow, verbose);
      }
      (*env).DeleteLocalRef(env, jstr); // De-Allocate the java string
    }
    (*env).DeleteLocalRef(env, asset_manager);
    (*env).DeleteLocalRef(env, activity_class);
    return(cast(immutable(char)*[])files);
  }

  // We shim ontop of our listDir some functions on Android
  bool isDir(string path){ return(dirExists(path)); }
  bool dirExists(string path){ return(listDirContent(path).length > 0); }

  // isFile uses SDL on Android
  bool isfile (const(char)* path) {
    SDL_RWops *rw = SDL_RWFromFile(path, "rb");
    if (rw == null) return false;
    SDL_RWclose(rw);
    return true;
  }

  bool isfile(string path) { return(isfile(toStringz(path))); }

  bool exists (string path) { return(isFile(path) | dirExists(path)); }

}else{ // Version SDL/OS, just use D to get the dir() functionality


  /** Content of a directory
   */
  immutable(char)*[] dir(string path, string pattern = "*", bool shallow = true) { 
    auto mode = SpanMode.shallow;
    if(!shallow) mode = SpanMode.depth;
    auto entries = dirEntries(path, pattern, mode).filter!(a => a.isFile).map!(a => a.name.toStringz).array;
    return(entries);
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
}

