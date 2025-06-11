### Prerequisites
Make sure the following (development) libraries are installed:
* [SDL2](https://www.libsdl.org/)
* [SDL2_image](https://www.libsdl.org/projects/SDL_image/)
* [SDL_mixer](https://www.libsdl.org/projects/SDL_mixer/)
* [SDL_ttf](https://www.libsdl.org/projects/SDL_ttf/)
* [LunarG Vulkan SDK](https://vulkan.lunarg.com/)
* [ShaderC](https://github.com/google/shaderc)
* [SPIRV-Cross](https://https://github.com/KhronosGroup/SPIRV-Cross)
* [DMD compiler](https://dlang.org/download.html) >2.110.0

Often we can install all Linux dependancies by issuing the following commands:

```
  sudo apt install libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev
  sudo apt install shaderc spirv-cross-dev
```

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
  * Execute dub to compile the executable and run the engine:
    * `dub`
  * For some linux distributions, the dynamic loader never checks the current directory for shared libs, which can be fixed by:
    * `$LD_LIBRARY_PATH=. dub`
* Compile [MS windows (x64)]
  * Install the [Visual Studio 2019 Build Tools](https://visualstudio.microsoft.com/downloads/?q=build+tools) with **MSVC v142** and the **Windows 10 SDK**
  * Install the [LunarG Vulkan SDK](https://vulkan.lunarg.com/) and make sure to **install the SDL2 Component**
  * Check the paths in the [dub.json](./dub.json) file, and update the Vulkan version (1.4.309.0) to the version installed
  * Execute dub to compile the executable
    * `dub`
