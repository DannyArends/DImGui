## DImGui ✨
![Screenshot](/app/src/main/assets/data/screenshots/March13_2026.png? "Screenshot")

Another 3D renderer developed in the D Programming Language, designed for cross-platform compatibility 
across Windows, Linux, and Android. The core "engine" is inspired by the excellent vulkan-tutorial.com, 
and leverages SDL3 for robust cross-platform support.

### Features 🚀

The engine boasts the following features:
- Basic geometries (cube, cone, torus, etc.) and complex 3D objects (FBX, 3DS, etc.)
- Skeletal and key-frame animations
- HDR Lighting Engine, Shadow maps & Normal mapping
- Bindless textures with async GPU upload
- Compute shaders for particle engines and texture generation
- Shader reflection for UBOs, SSBOs, and textures
- Instanced rendering of objects with dynamic vertex/index buffers
- L-system procedural geometry
- PDB protein structure viewer
- GUI windows for settings, objects, textures, lights, and sounds

### (Cross-)Compilation ⚙️

All dependencies are included as git submodules in `app/jni/`, making this repository 
self-contained. It is also a minimal SDL3 android_project ready for Android Studio. 
The software has been tested on x64 Windows, x64 Linux, and arm64-v8a Android 15.

For building on MS Windows and/or Linux, see [compilation.md](./docs/compilation.md).  
For cross-compiling for Android arm64-v8a, see [cross-compilation.md](./docs/cross-compilation.md).

### Build with 🛠️

DImGui is made possible by, and has dependencies on, the following excellent software:

- [D Programming Language](https://dlang.org/)
- [Android Studio](https://developer.android.com/studio)
- [SDL3](https://www.libsdl.org/)
- [Shaderc](https://github.com/google/shaderc) & [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross)
- [Dear ImGui](https://github.com/ocornut/imgui) & [cImGui api wrapper](https://github.com/cimgui/cimgui)
- [Open Asset Import Library](https://github.com/assimp/assimp) 

### Structure 📁

The following folders are interesting, if you're interested in how the repository is structured:

- [src/](./src/) which stores the D source code 
- [src/engine](./src/engine/) main folder for the engine objects
- [src/engine/assimp](./src/engine/assimp/) Open Asset Import Library (assimp) folder
- [src/engine/imgui](./src/engine/imgui/) Dear ImGui UI folder
- [src/math](./src/math/) math functions for vectors, matrices, particles, and the L-system
- [src/objects](./src/objects) All geometric (renderable) objects are in here
- [assets/](./app/src/main/assets/data/) Assets used (fonts, objects, shaders, and textures)
- [app/jni/](./app/jni/) all dependencies as git submodules (SDL3, shaderc, spirv_cross, assimp, cimgui)

Some noteworthy files:

- [dub.json](./dub.json) contains the D language dependencies, and build instructions
- [src/main.d](./src/main.d) contains the main entry function, and SDL event loop
- [src/scene.d](./src/scene.d) contains the code that sets up the example scene
- [src/includes.c](./src/includes.c) contains the importC instructions

### Contributing 🙌

Want to contribute? Great! Contribute to this repo by starring ⭐ or forking 🍴, and feel 
free to start an issue first to discuss idea's before sending a pull request. You're also 
welcome to post comments on commits.

Or be a maintainer, and adopt (the documentation of) a function.

### License ⚖️

Written by Danny Arends and is released under the GNU GENERAL PUBLIC LICENSE Version 3 (GPLv3). 
See [LICENSE.txt](./LICENSE.txt).
