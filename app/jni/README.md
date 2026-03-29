## Compile for MS Windows 10 / 11
Compile Open Asset Import Library (assimp):
```
rd /s /q app\jni\assimp\build
cd app/jni/assimp
call "C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat" 
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON ^
      -DASSIMP_BUILD_TESTS=OFF ^
      -DASSIMP_INSTALL=OFF ^
      -DASSIMP_BUILD_ASSIMP_TOOLS=OFF ^
      -DASSIMP_NO_EXPORT=ON ^
      -DASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT=OFF ^
      -DASSIMP_BUILD_FBX_IMPORTER=ON ^
      -DASSIMP_BUILD_3DS_IMPORTER=ON ^
      -DASSIMP_BUILD_OBJ_IMPORTER=ON ^
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile C-api for Dear ImGui:
```
rd /s /q app\jni\build
cd app/jni/
call "C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat" 
mkdir build
cd build
cmake -DVULKAN_DIR="C:/VulkanSDK/1.4.335.0" -DSDL3_DIR="../SDL/" ../
cmake --build . --config Release -j10
cd ../../../
```
Compile Simple DirectMedia Layer (SDL3):
```
rd /s /q app\jni\SDL\build
cd app/jni/SDL
call "C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat" 
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DSDL_STATIC=OFF -DSDL_SHARED=ON ^
      -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF ^
      ../
cmake --build . --config Release -j10
cmake --install . --prefix ./install
cd ../../../../
```
Compile SDL_image:
```
rd /s /q app\jni\SDL_image\build
cd app/jni/SDL_image
call "C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat" 
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON ^
      -DSDL3_DIR="%CD%/../../SDL/build" ^
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile SDL_mixer:
```
rd /s /q app/jni/SDL_mixer/Release
cd app/jni/SDL_mixer
mkdir Release
cd Release
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON ^
      -DSDL3MIXER_SAMPLES=OFF -DSDL3MIXER_MOD=OFF ^
      -DSDL3_DIR="%CD%/../../SDL/build" ^
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile SDL_ttf:
```
rd /s /q app\jni\SDL_ttf\libtool
cd app/jni/SDL_ttf
call "C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat" 
mkdir libtool
cd libtool
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON ^
      -DSDL3_DIR="%CD%/../../SDL/build" ^
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile ShaderC:
```
rd /s /q app\jni\shaderc\build
cd app/jni/shaderc
python utils/git-sync-deps
call "C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat" 
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON ^
      -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_ENABLE_WGSL_OUTPUT=OFF ^
      -DSPIRV_TOOLS_BUILD_STATIC=OFF -DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON ^
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile spriv_cross:
```
rd /s /q app\jni\spirv_cross\build
cd app/jni/spirv_cross
call "C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat" 
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON ^
      -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_MSL=OFF ^
      ../
cmake --build . --config Release -j10
cd ../../../../
```

## Compile for Linux
Compile Simple DirectMedia Layer (SDL3):
```
rm -rf app/jni/SDL/build
cd app/jni/SDL
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DSDL_STATIC=OFF -DSDL_X11_XTEST=OFF -DBUILD_SHARED_LIBS=ON ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile SDL_image:
```
rm -rf app/jni/SDL_image/build
cd app/jni/SDL_image
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DCMAKE_PREFIX_PATH=$(realpath ../../SDL/build) ../
cmake --build . --config Release -j10
cd ../../../../
```

Compile Open Asset Import Library (assimp):
```
rm -rf app/jni/assimp/build
cd app/jni/assimp
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT=OFF \
      -DASSIMP_BUILD_FBX_IMPORTER=ON \
      -DASSIMP_BUILD_3DS_IMPORTER=ON \
      -DASSIMP_BUILD_OBJ_IMPORTER=ON \
      -DASSIMP_NO_EXPORT=ON \
      -DASSIMP_BUILD_TESTS=OFF \
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile ShaderC:
```
rm -rf app/jni/shaderc/build
cd app/jni/shaderc
python utils/git-sync-deps
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DSPIRV_TOOLS_BUILD_STATIC=OFF \
      -DSHADERC_SKIP_TESTS=ON \
      -DSHADERC_SKIP_EXAMPLES=ON \
      -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
      ../
cmake --build . --config Release -j10
cd ../../../../
```
Compile C-api for Dear ImGui:
```
rm -rf app/jni/build
cd app/jni/
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DVULKAN_DIR="/usr" \
      -DSDL3_DIR="../SDL" \
      ../
cmake --build . --config Release -j10
cd ../../../
```

