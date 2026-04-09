/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

size_t fread(SDL_IOStream* fp, void* buffer, size_t n, size_t size) { return(SDL_ReadIO(fp, buffer, n * size)); }
size_t fwrite(SDL_IOStream* fp, void* buffer, size_t n, size_t size) { return(SDL_WriteIO(fp, buffer, n * size)); }
ulong tell(SDL_IOStream* fp){ return(SDL_TellIO(fp)); }
ulong seek(SDL_IOStream* fp, int offset, SDL_IOWhence whence){ return(SDL_SeekIO(fp, offset, whence)); }
ulong fsize(const(char)* path, bool verbose = true){
  path = fixPath(path);
  SDL_IOStream* fp = SDL_IOFromFile(path, "rb");
  if(fp == null && verbose) { SDL_Log("[ERROR] couldn't open file '%s'\n", path); return 0; }
  uint size = cast(uint)SDL_GetIOSize(fp);
  SDL_CloseIO(fp);
  return(size);
}

string fixPath(string path){
  version(Android) { } else { if(!path.startsWith("app/src/main/assets/")) return "app/src/main/assets/" ~ path; }
  return path;
}

void ensureWorldDir(ref App app) {
  string path = fixPath(format("data/world/%d_%d", app.world.seed[0], app.world.seed[1]));
  version (Android) { path = format("%s/%s", fromStringz(SDL_GetAndroidInternalStoragePath()), path); }
  SDL_CreateDirectory(toStringz(path));
}

const(char)* fixPath(const(char)* path){ return toStringz(fixPath(cast(string)fromStringz(path))); }

/** Read content of a file as a char[]
 */
char[] readFile(const(char)* path, uint verbose = 0) {
  path = fixPath(path);
  SDL_IOStream* fp = SDL_IOFromFile(path, "rb");
  if(fp == null) { SDL_Log("[ERROR] couldn't open file '%s'\n", path); return []; }

  char[] content;
  content.length = cast(size_t)SDL_GetIOSize(fp);

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

/** Write content of a char[] to a file
 */
void writeFile(const(char)* path, char[] content, uint verbose = 0) {
  path = fixPath(path);
  version (Android) { path = toStringz(format("%s/%s", fromStringz(SDL_GetAndroidInternalStoragePath()), fromStringz(path))); }
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

  // listDirContent uses SDL to get jni the environment, and obtain a link to the asset_manager via jni calls
  string[] listDirContent(const(char)* path = "", string pattern = "*", bool shallow = true, uint verbose = 0) {
    //SDL_Log("listDirContent %s", path);
    JNIEnv* env = cast(JNIEnv*)SDL_GetAndroidJNIEnv();
    //SDL_Log("JNIEnv %p", env);
    jobject activity = cast(jobject)SDL_GetAndroidActivity();
    jclass activity_class = (*env).GetObjectClass(env, activity);
    jobject asset_manager = (*env).CallObjectMethod(env, activity, (*env).GetMethodID(env, activity_class, "getAssets", "()Landroid/content/res/AssetManager;"));

    // Query the asset_manager for the list() method
    auto list_method = (*env).GetMethodID(env, (*env).GetObjectClass(env, asset_manager), "list", "(Ljava/lang/String;)[Ljava/lang/String;");
    jstring path_object = (*env).NewStringUTF(env, path);
    auto files_object = cast(jobjectArray)(*env).CallObjectMethod(env, asset_manager, list_method, path_object);
    auto length = (*env).GetArrayLength(env, files_object);

    // List all files in the folder
    //SDL_Log("Path %s, mngr: %X, list_method: %X, nObjects: %d \n", path, asset_manager, list_method, length);
    string[] files;
    for (int i = 0; i < length; i++) {
      // Allocate the java string, and get the filename
      jstring jstr = cast(jstring)(*env).GetObjectArrayElement(env, files_object, i);
      const(char)* cstr = (*env).GetStringUTFChars(env, jstr, null); // Get C string memory
      if (cstr == null) { (*env).DeleteLocalRef(env, jstr); continue; }
      string fn = to!string(cstr);
      (*env).ReleaseStringUTFChars(env, jstr, cstr); // Release C string memory

      if (fn) {
        string s = to!string(path);
        fn = format("%s%s%s", s, (s[$-1] == '/'? "": "/"), fromStringz(fn));
        if (globMatch(fn.fromStringz(), pattern)) { 
          //SDL_Log("matching file: %s @ %s", toStringz(s), toStringz(fn));
          files ~= fn;
        }
        if (!shallow && isdir(toStringz(fn))) files ~= listDirContent(toStringz(fn), pattern, shallow, verbose);
      }
      (*env).DeleteLocalRef(env, jstr); // De-Allocate the java string
    }
    
    (*env).DeleteLocalRef(env, files_object);  // Delete the array of files
    (*env).DeleteLocalRef(env, path_object);   // Delete the path string
    (*env).DeleteLocalRef(env, activity);      // Delete the activity object
    
    (*env).DeleteLocalRef(env, asset_manager);
    (*env).DeleteLocalRef(env, activity_class);
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

  bool exists (const(char)* path) { return(isfile(path) | dirExists(path)); }

}else{ // Version SDL/OS, just use D to get the dir() functionality

  /** Content of a directory
   */
  string[] dir(const(char)* dirPath, string pattern = "*", bool shallow = true) { 
    string path = cast(string)fromStringz(fixPath(dirPath));
    auto mode = SpanMode.shallow;
    if(!shallow) mode = SpanMode.depth;
    auto entries = dirEntries(path, pattern, mode).map!(a => a.name).array;
    return(entries);
  }

  /** Helper function to determine if a path is a file
   */
  bool isfile(const(char)* filePath) {
    string path = cast(string)fromStringz(fixPath(filePath));
    try {
      if (path.exists() && path.isFile) return(true);
    } catch (Exception e) { SDL_Log("path %s was not a file", path.ptr); }
    return(false);
  }

  /** Helper function to determine if a path is a file
   */
  bool isdir(const(char)* dirPath) {
    string path = cast(string)fromStringz(fixPath(dirPath));
    try {
      if (path.exists() && path.isDir) return(true);
    } catch (Exception e) { SDL_Log("path %s was not a directory", path.ptr); }
    return(false);
  }
}
