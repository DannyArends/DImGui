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
  * Execute configure on SDL2, and install into the build folder
    * `cd deps/SDL`
    * `./configure --prefix=$PWD/build/`
    * `make install`
    * `cd ../..`
  * Execute make to compile libcimgui.a on linux
    * `make static`
  * Execute dub to compile the executable
    * `dub`

