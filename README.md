### DImGui
An SDL2 + Vulkan + ImGui renderer in the D Programming Language

### Prerequisites
Make sure the following libraries are installed:
* SDL2
* Vulkan
* DMD >2.110.0

### Compilation [linux]

* Clone the repository
  * `git clone --recursive https://github.com/DannyArends/DImGui.git`
  * `git submodule update --init --recursive` (If already cloned)
* Compile
  * Execute configure on SDL, and install into the build folder
    * `cd deps/SDL`
    * `./configure --prefix=$PWD/../`
    * `make -j8 install`
    * `cd ../..`
  * Execute configure on SDL_ttf, and install into the build folder
    * `cd deps/SDL_ttf`
    * `./configure --with-sdl-prefix=$PWD/../ --prefix=$PWD/../`
    * `make -j8 install`
    * `cd ../..`
  * Execute configure on SDL_image and install into the build folder
    * `cd deps/SDL_image`
    * `./configure --with-sdl-prefix=$PWD/../ --prefix=$PWD/../`
    * `make -j8 install`
    * `cd ../..`
  * Execute make to compile libcimgui.a on linux
    * `make static`
  * Execute dub to compile the executable
    * `dub`

