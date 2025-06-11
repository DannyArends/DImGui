## DImGui
![Screenshot](/app/src/main/assets/data/screenshots/example.png? "Screenshot")
Another SDL2 + Vulkan + ImGui renderer in the D Programming Language. However, this one will work on Windows, Linux, and even Android. The current 'engine' is based on the excellent vulkan-tutorial.com, and uses SDL2 for cross-platform support. This repository includes the SDL DLLs for x64 MS Windows, and is in itself a minimal SDL2 android_project. There are a lot of requirements to build the example (SDL, Vulkan, Android Studio, Android NDK). The software has been tested under x64 (Windows and Linux) and on arm64-v8a (Android 10).

### (Cross-)Compilation

For building DImGui on MS Windows and/or Linux, see the instruction in [compilation.md](./docs/compilation.md). Instructions 
on how to cross-compile for Android using Linux, see: [cross-compilation.md](./docs/cross-compilation.md)

### Structure
The following folders are interesting, if you're interested in how the repository is structured:

- [src/](./src/) which stores the D source code 
- [src/engine](./src/engine/) main folder for the engine objects
- [src/math](./src/math/) math functions for vectors, matrices, particles, and the L-system
- [src/objects](./src/objects) All geometric (renderable) objects are in here
- [assets/](./app/src/main/assets/data/) All assets of the engine (font, objects, shaders, and textures)
- [deps/](./deps/) CImGui source code as well as Windows 64bit runtime SDL2 DLLs for image, mixer, and ttf

Some noteworthy files:

- [dub.json](./dub.json) contains the D language dependancies, and build instructions
- [src/main.d](./src/main.d) contains the main entry function, and SDL event loop
- [src/scene.d](./src/scene.d) contains the code that sets up the example scene
- [src/includes.c](./src/includes.c) contains the importC instructions

### Contributing

Want to contribute? Great! Contribute to this repo by starring or forking on Github, and feel free 
to start an issue first to discuss idea's before sending a pull request. You're also welcome to 
post comments on commits.

Or be a maintainer, and adopt (the documentation of) a function.

### License

Written by Danny Arends and is released under the GNU GENERAL PUBLIC LICENSE Version 3 (GPLv3). See [LICENSE.txt](./LICENSE.txt).
