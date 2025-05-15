### DImGui
An SDL2 + Vulkan + ImGui renderer in the D Programming Language

### Prerequisites
Make sure the following (development) libraries are installed:
* SDL2
* Vulkan
* [DMD compiler](https://dlang.org/download.html) >2.110.0

### Compilation [Linux & Windows]

* Clone the repository
  * `git clone --recursive https://github.com/DannyArends/DImGui.git`
  * `git submodule update --init --recursive` (If already cloned)
* Compile [Linux]
  * Make sure the `SDL2`, `SDL2_image`, `SDL2_mixer`, `SDL2_ttf` development libraries are installed
    * [SDL2](https://www.libsdl.org/)
    * [SDL2_image](https://www.libsdl.org/projects/SDL_image/)
    * [SDL_mixer](https://www.libsdl.org/projects/SDL_mixer/)
    * [SDL_ttf](https://www.libsdl.org/projects/SDL_ttf/)
  * Execute dub to compile the executable
    * `dub`
* Compile [MS windows (x64)]
  * Install the Visual Studio 2019 Build Tools with MSVC v142 and windows 10 SDK
  * Install the [LunarG Vulkan SDK](https://vulkan.lunarg.com/) and make sure to **install the SDL2 Component**
  * Check the paths in the dub.json file, and update the version (1.4.309.0) to the version installed
  * Execute dub to compile the executable
    * `dub`

### Structure
The following folders are interesting, if you're interested in how CalderaD is coded:

- [src/](./src/) which stores the D source code and the includes.c holding the importC instructions
- [src/engine](./src/engine/) main folder for the engine objects
- [src/math](./src/math/) math functions for vectors, matrices, particles, and the L-system
- [src/objects](./src/objects) All geometric (renderable) objects are in here
- [assets/](./assets/) All assets of the engine (font, objects, shaders, and textures)
- [deps/](./deps/) CImGui source code as well as Windows 64bit runtime SDL2 DLLs for image,mixer and ttf
