## Cross-compile for Android using Linux
To cross-compile for Android, you'll need:
* LDC2 version 1.40.1
* Python
* LDC2 Android library: ldc2-1.40.1-beta1-android-aarch64.tar.xz
* cmake version 3.27.0
* Android Studio
* Android NDK r27c (version: 27.2.12479018)

### Install Android Studio

Make sure that after installation you set the ANDROID_HOME variable, as well as update your PATH environmental variable
```
  export ANDROID_HOME=~/Android/Sdk
  export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools
```

### Preparing the build environment:
We need to make a single change in the NDK to prevent a compile issue with SDL2, in:
ndk/27.2.12479018/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/sys/types.h

Comment out L119, to prevent recursive definition of variadic arguments:
```
  //typedef __builtin_va_list __va_list;
```

### Setup LDC2 for cross compilation:

Get the android libraries by downloading: ldc2-1.40.1-beta1-android-aarch64.tar.xz
Extract the lib folder in the archive, rename it to "lib-android-aarch64" then copy it in the directory where you installed LDC 1.40.1

Inside the ldc2-1.40.1-linux-x86_64/etc/ folder open the ldc2.conf file and add the android target:

Make sure the %%ndkpath%% is either defined, or replace it with the absolute path to the NDK

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

Now we can are ready to build the dependancies:

### Compile shaderc using cmake
```
  cd deps/shaderc
  python utils/git-sync-deps
  rm -rf build
  mkdir build
  cd build
  cmake -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=/home/rqdt9/Android/Sdk/ndk/27.2.12479018/build/cmake/android.toolchain.cmake \
        -DANDROID_PLATFORM=24 \
        -DANDROID_ABI=arm64-v8a \
        -DSHADERC_SKIP_TESTS=TRUE \
        -DSHADERC_SKIP_EXAMPLES=TRUE \
        -DSHADERC_SKIP_INSTALL=TRUE \
        ../
  make -j8
  mv libshaderc/libshaderc_shared.so ../../../app/src/main/jniLibs/arm64-v8a
```

Move the compiled shared library from "libshaderc/libshaderc_shared.so" to "app/src/main/jniLibs" so 
Android Studio will pick up the compiled library and include it inside the APK.

### Compile spirv_cross using cmake
```
  cd deps/spirv_cross
  rm -rf build
  mkdir build
  cd build
  cmake -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=/home/rqdt9/Android/Sdk/ndk/27.2.12479018/build/cmake/android.toolchain.cmake \
        -DANDROID_PLATFORM=24 \
        -DANDROID_ABI=arm64-v8a \
        -DSPIRV_CROSS_SHARED=ON \
        ../
  make -j8
  mv libspirv-cross-c-shared.so ../../../app/src/main/jniLibs/arm64-v8a
```
Move the compiled shared library from "build/libshaderc/libshaderc_shared.so" to "app/src/main/jniLibs" so 
Android Studio will pick up the compiled library and include it inside the APK.

### Compile IMGUI & IMGUI into a shared library
Make sure to update the paths to the NDK inside the Makefile before trying to build the libCImGui, then compile
```
  make -f Makefile.android
```

### Compile SDL2 & other related libraries

For SDL_Mixer, set the support for libgme to false in the Android.mk file (line 34)
```
  SUPPORT_GME ?= false
```

After this, use Android Studio to compile the SDL libraries, we need to use the .SO files to build the libMAIN.so in the next step. 
Find where the compiled .so files are located inside of: app/build/intermediates/

### Compile the D code into libMAIN.so
We can now use LDC to compile the shared library that will hook the sdl_main entry point, use importC to link to the dependancies, and the D code
```
dub build --compiler=ldc2 --arch=aarch64-*-linux-android --config=android-64 --force
```

