## DImGui ✨
![Screenshot](/app/src/main/assets/data/screenshots/June27_2025_Snoo.png)

Another 3D renderer developed in the D Programming Language, designed for cross-platform compatibility 
across Windows, Linux, and Android. The core "engine" is inspired by the excellent vulkan-tutorial.com, 
and leverages SDL2 for robust cross-platform support.

### Features 🚀

The engine boasts the following features:
- Basic geometries (cube, cone, torus, etc.) and complex 3D objects (FBX, glTF, 3DS, etc.)
- Skeletal and key-frame animations
- Compute shaders for particle engines and texture generation
- Shader reflection for UBOs, SSBOs, and textures
- Instanced rendering of objects
- GUI windows for settings, objects, textures, lights, and sounds

### (Cross-)Compilation ⚙️

This repository includes the necessary SDL2 DLLs for x64 MS Windows, and is in itself a minimal SDL2 
android_project for Android Studio. Building the example requires several dependencies, including SDL, 
Vulkan, ShaderC, SPIRV-Cross, and the Open Asset Import Library. To build the Android version Android 
Studio and the Android NDK are required. The software has been tested under x64 systems (Windows and 
Linux) and on arm64-v8a (Android 15).

For building on MS Windows and/or Linux, please refer to the detailed instructions in 
[compilation.md](./docs/compilation.md). If you're cross-compiling for Android arm64-v8a using 
Linux, you'll find the relevant guide in [cross-compilation.md](./docs/cross-compilation.md).

### Build with 🛠️

DImGui is made possible by, and has the following dependencies on, excellent software:

- [D Programming Language](https://dlang.org/)
- [Android Studio](https://developer.android.com/studio)
- [SDL2](https://www.libsdl.org/)
- [Shaderc](https://github.com/google/shaderc) & [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross)
- [Dear ImGui](https://github.com/ocornut/imgui) & [cImGui api wrapper](https://github.com/cimgui/cimgui)
- [Open Asset Import Library](https://github.com/assimp/assimp) 

### Structure 📁

The following folders are interesting, if you're interested in how the repository is structured:

- [src/](./src/) which stores the D source code 
- [src/engine](./src/engine/) main folder for the engine objects
- [src/math](./src/math/) math functions for vectors, matrices, particles, and the L-system
- [src/objects](./src/objects) All geometric (renderable) objects are in here
- [assets/](./app/src/main/assets/data/) Assets used (fonts, objects, shaders, and textures)
- [deps/](./deps/) Dependencies and Windows 64bit runtime SDL2 DLLs for image, mixer, and ttf

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
