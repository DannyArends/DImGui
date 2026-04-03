## Cross-compile for Android
 
All dependencies are included as submodules in `app/jni/` and are built together via the Android CMakeLists.txt.
 
### Requirements
 
* [LDC2](https://github.com/ldc-developers/ldc/releases) version 1.40.1+
* [Android Studio](https://developer.android.com/studio)
* Android NDK r27c (version: 27.2.12479018)
* Python (for shaderc dependency sync)
 
### Install Android Studio
 
After installation, set the required environment variables:
```
export ANDROID_HOME=~/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools
```

### Setup LDC2 for Android cross-compilation
 
Download `ldc2-1.40.1-beta1-android-aarch64.tar.xz`, extract the `lib` folder, rename it to `lib-android-aarch64`, and 
place it in your LDC2 installation directory.
 
Add the Android target to `ldc2-1.40.1-linux-x86_64/etc/ldc2.conf`:
```
"aarch64-.*-linux-android":
{
    switches = [
        "-defaultlib=phobos2-ldc,druntime-ldc",
        "-link-defaultlib-shared=false",
        "-gcc=%%ndkpath%%/27.2.12479018/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang",
    ];
    lib-dirs = [
        "%%ldcbinarypath%%/../lib-android-aarch64",
    ];
    rpath = "";
};
```

### Build Android libraries
 
All dependencies (SDL3, SDL3_image, SDL3_mixer, SDL3_ttf, shaderc, spirv_cross, assimp, cimgui) are built together by 
Android Studio via `app/jni/CMakeLists.txt`. Open the project in Android Studio and build, or use:
```
./gradlew assembleDebug
```
 
### Compile D code into libmain.so
 
```
dub build --compiler=ldc2 --arch=aarch64-unknown-linux-android --config=android-64 --force
```
 
### Install on device
 
```
adb install app/build/outputs/apk/debug/app-debug.apk
```
