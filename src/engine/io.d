/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

size_t fread(SDL_RWops* fp, void* buffer, size_t n, size_t size) { return(SDL_RWread(fp, buffer, n, size)); }
size_t fwrite(SDL_RWops* fp, void* buffer, size_t n, size_t size) { return(SDL_RWwrite(fp, buffer, n, size)); }
ulong tell(SDL_RWops* fp){ return(SDL_RWtell(fp)); }
ulong seek(SDL_RWops* fp, int offset, int whence){ return(SDL_RWseek(fp, offset, whence)); }

/** Read content of a file as a char[]
 */
char[] readFile(const(char)* path, uint verbose = 0) {
  version (Android){ }else{ path = toStringz(format("app/src/main/assets/%s", fromStringz(path))); }
  SDL_RWops* fp = SDL_RWFromFile(path, "rb");
  if(fp == null) { SDL_Log("[ERROR] couldn't open file '%s'\n", path); return []; }

  char[] content;
  content.length = cast(size_t)SDL_RWsize(fp);

  size_t readTotal = 0, nRead = 1;
  char* buffer = &content[0];
  while (readTotal < content.length && nRead != 0) {
    nRead = fp.fread(buffer, 1, cast(size_t)(content.length - readTotal));
    readTotal += nRead;
    buffer += nRead;
  }
  SDL_RWclose(fp);

  if(readTotal != content.length) SDL_Log("[ERROR] read %db, expected %db\n", readTotal, content.length);
  if(verbose) SDL_Log("readFile: loaded %d bytes\n", readTotal);
  return content;
}

/** Write content of a char[] to a file
 */
void writeFile(const(char)* path, char[] content, uint verbose = 0) {
  version (Android) {
    path = toStringz(format("%s/%s", fromStringz(SDL_AndroidGetInternalStoragePath()), fromStringz(path)));
   }else{ path = toStringz(format("app/src/main/assets/%s", fromStringz(path))); }
  SDL_RWops* fp = SDL_RWFromFile(path, "w");
  if(fp == null) { SDL_Log("[ERROR] couldn't open file '%s'\n", path); return; }

  size_t writeTotal = 0, nWrite = 1;
  char* buffer = &content[0];
  while (writeTotal < content.length && nWrite != 0) {
    nWrite = fp.fwrite(buffer,1, cast(size_t)(content.length - writeTotal));
    writeTotal += nWrite;
    buffer += nWrite;
  }
  SDL_RWclose(fp);

  if(writeTotal != content.length) SDL_Log("[ERROR] write %db, expected %db\n", writeTotal, content.length);
  if(verbose) SDL_Log("writeFile: wrote %d bytes\n", writeTotal);
}

version(Android) {
  // SDL does not provide the ability to scan folders, and on android we need to use the jni
  // dir() is the wrapper function provided
  immutable(char)*[] dir(const(char)* path, string pattern = "*", bool shallow = true) { 
    return(listDirContent(path, pattern, shallow)); 
  }

  // listDirContent uses SDL to get jni the environment, and obtain a link to the asset_manager via jni calls
  immutable(char)*[] listDirContent(const(char)* path = "", string pattern = "*", bool shallow = true, uint verbose = 0) {
    JNIEnv* env = cast(JNIEnv*)SDL_AndroidGetJNIEnv();
    jobject activity = cast(jobject)SDL_AndroidGetActivity();
    jclass activity_class = (*env).GetObjectClass(env, activity);
    jobject asset_manager = (*env).CallObjectMethod(env, activity, (*env).GetMethodID(env, activity_class, "getAssets", "()Landroid/content/res/AssetManager;"));

    // Query the asset_manager for the list() method
    auto list_method = (*env).GetMethodID(env, (*env).GetObjectClass(env, asset_manager), "list", "(Ljava/lang/String;)[Ljava/lang/String;");
    jstring path_object = (*env).NewStringUTF(env, path);
    auto files_object = cast(jobjectArray)(*env).CallObjectMethod(env, asset_manager, list_method, path_object);
    auto length = (*env).GetArrayLength(env, files_object);

    // List all files in the folder
    //SDL_Log("Path %s, mngr: %X, list_method: %X, nObjects: %d \n", toStringz(path), asset_manager, list_method, length);
    const(char)*[] files;
    for (int i = 0; i < length; i++) {
      // Allocate the java string, and get the filename
      jstring jstr = cast(jstring)(*env).GetObjectArrayElement(env, files_object, i);
      const(char)* fn = (*env).GetStringUTFChars(env, jstr, null);
      if (fn) {
        string s = to!string(path);
        fn = toStringz(format("%s%s%s", s, (s[$-1] == '/'? "": "/"), fromStringz(fn)));
        if (globMatch(fn.fromStringz(), pattern)) { 
          //SDL_Log("matching file: %s @ %s", toStringz(filename), toStringz(filepath));
          files ~= fn;
        }
        if (!shallow && isDir(fn)) files ~= listDirContent(fn, pattern, shallow, verbose);
      }
      (*env).DeleteLocalRef(env, jstr); // De-Allocate the java string
    }
    (*env).DeleteLocalRef(env, asset_manager);
    (*env).DeleteLocalRef(env, activity_class);
    return(cast(immutable(char)*[])files);
  }

  // We shim ontop of our listDir some functions on Android
  bool isdir(const(char)* path){ return(dirExists(path)); }
  bool dirExists(const(char)* path){ return(listDirContent(path).length > 0); }

  // isFile uses SDL on Android
  bool isfile (const(char)* path) {
    SDL_RWops *rw = SDL_RWFromFile(path, "rb");
    if (rw == null) return false;
    SDL_RWclose(rw);
    return true;
  }

  bool exists (const(char)* path) { return(isfile(path) | dirExists(path)); }

}else{ // Version SDL/OS, just use D to get the dir() functionality

  /** Content of a directory
   */
  immutable(char)*[] dir(const(char)* dirPath, string pattern = "*", bool shallow = true) { 
    string path = format("app/src/main/assets/%s", fromStringz(dirPath));
    auto mode = SpanMode.shallow;
    if(!shallow) mode = SpanMode.depth;
    auto entries = dirEntries(path, pattern, mode).map!(a => a.name.toStringz).array;
    return(entries);
  }

  /** Helper function to determine if a path is a file
   */
  bool isfile(const(char)* filePath) {
    string path = format("app/src/main/assets/%s", fromStringz(filePath));
    try {
      if (path.exists() && path.isFile) return(true);
    } catch (Exception e) { SDL_Log("path %s was not a file", path.ptr); }
    return(false);
  }

  /** Helper function to determine if a path is a file
   */
  bool isdir(const(char)* filePath) {
    string path = format("app/src/main/assets/%s", fromStringz(filePath));
    try {
      if (path.exists() && path.isDir) return(true);
    } catch (Exception e) { SDL_Log("path %s was not a directory", path.ptr); }
    return(false);
  }
}
