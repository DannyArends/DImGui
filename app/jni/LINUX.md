## Compile for Linux
Compile Simple DirectMedia Layer (SDL3):
```
rm -rf app\jni\SDL\build
cd app/jni/SDL
call "C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat" 
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DSDL_STATIC=OFF -DSDL_SHARED=ON \
      -DSDL_TESTS=OFF -DSDL_TEST_LIBRARY=OFF -DSDL_X11_XTEST=OFF -DSDL_EXAMPLES=OFF \
      ../
cmake --build . --config Release -j10
cmake --install . --prefix ./install
cd ../../../../
```
Compile SDL_image:
```
rm -rf app\jni\SDL_image\build
cd app/jni/SDL_image
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
      -DSDL3_DIR="$PWD/../../SDL/build" \
      -DSDLIMAGE_AVIF=OFF -DSDLIMAGE_WEBP=OFF -DSDLIMAGE_TIF=OFF -DSDLIMAGE_XCF=OFF -DSDLIMAGE_XPM=OFF -DSDLIMAGE_XV=OFF -DSDLIMAGE_LBM=OFF \
      -DSDLIMAGE_PCX=OFF -DSDLIMAGE_PNM=OFF -DSDLIMAGE_QOI=OFF -DSDLIMAGE_SVG=OFF -DSDLIMAGE_TGA=OFF -DSDLIMAGE_GIF=OFF -DSDLIMAGE_ANI=OFF \
      -DSDLIMAGE_SAMPLES=OFF -DSDLIMAGE_TESTS=OFF \
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile SDL_mixer:
```
rm -rf app/jni/SDL_mixer/Release
cd app/jni/SDL_mixer
mkdir Release
cd Release
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
      -DSDLMIXER_AIFF=OFF -DSDLMIXER_VOC=OFF -DSDLMIXER_AU=OFF -DSDLMIXER_FLAC=OFF -DSDLMIXER_GME=OFF -DSDLMIXER_MOD=OFF \
      -DSDLMIXER_MP3=OFF -DSDLMIXER_MIDI=OFF -DSDLMIXER_OPUS=OFF -DSDLMIXER_VORBIS_STB=OFF -DSDLMIXER_VORBIS_VORBISFILE=OFF \
      -DSDLMIXER_WAVPACK=OFF -DSDLMIXER_EXAMPLES=OFF -DSDLMIXER_TESTS=OFF \
      -DSDL3_DIR="$PWD/../../SDL/build" \
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile SDL_ttf:
```
rm -rf app\jni\SDL_ttf\build
cd app/jni/SDL_ttf
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
      -DSDL3_DIR="$PWD/../../SDL/build" -DSDLTTF_SAMPLES=OFF \
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile Open Asset Import Library (assimp):
```
rm -rf app/jni/assimp/build
cd app/jni/assimp
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
      -DASSIMP_BUILD_TESTS=OFF -DASSIMP_INSTALL=OFF -DASSIMP_BUILD_ASSIMP_TOOLS=OFF -DASSIMP_BUILD_ZLIB=ON \
      -DASSIMP_NO_EXPORT=ON -DASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT=OFF \
      -DASSIMP_BUILD_FBX_IMPORTER=ON -DASSIMP_BUILD_3DS_IMPORTER=ON -DASSIMP_BUILD_OBJ_IMPORTER=ON \
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile C-api for Dear ImGui:
```
rm -rf app\jni\build
cd app/jni/
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
  -DCIMGUI_USE_SDL3=ON -DSDL3_DIR="$PWD/../SDL" \
  ../
cmake --build . --config Release -j10
cd ../../../
```
Compile ShaderC:
```
rm -rf app\jni\shaderc\build
cd app/jni/shaderc
python utils/git-sync-deps
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
      -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_ENABLE_WGSL_OUTPUT=OFF \
      -DSPIRV_TOOLS_BUILD_STATIC=OFF -DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
      -DENABLE_GLSLANG_BINARIES=OFF \
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile spriv_cross:
```
rm -rf app\jni\spirv_cross\build
cd app/jni/spirv_cross
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
      -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_MSL=OFF \
      ../
cmake --build . --config Release -j10
cd ../../../../
```

