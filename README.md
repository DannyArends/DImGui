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
* Compile [Linux]
  * Make sure the `SDL2`, `SDL2_image`, `SDL2_mixer`, `SDL2_ttf` development libraries are installed
  * Execute dub to compile the executable
    * `dub`
* Compile [MS windows (x64)]
  * Install the Visual Studio 2019 Build Tools with MSVC v142 and windows 10 SDK
  * Install the LunarG Vulkan SDK and install the SDL2 Component
  * Check the paths in the dub.json file, and update the version (1.4.309.0) to the version installed
  * Execute dub to compile the executable
    * `dub`

