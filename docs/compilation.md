### Prerequisites
You will need a D compiler
* [DMD or LDC2 compiler](https://dlang.org/download.html) >2.110.0

### Clone the repository
 
```
git clone --recursive https://github.com/DannyArends/DImGui.git
git submodule update --init --recursive  # if already cloned
```
 
### Compilation [Linux]
 
Build all dependencies from `app/jni/` using cmake, then compile with dub.
See [app/jni/LINUX.md](../app/jni/LINUX.md) for the full Linux build commands for each dependency.
 
Once dependencies are built:
```
dub
```
 
For some Linux distributions, the dynamic loader never checks the current directory for shared libs:
```
LD_LIBRARY_PATH=. dub
```
 
### Compilation [MS Windows x64]
 
* Install [Visual Studio 2019 Build Tools](https://visualstudio.microsoft.com/downloads/?q=build+tools) with **MSVC v142** and the **Windows 10 SDK**
* Install the [LunarG Vulkan SDK](https://vulkan.lunarg.com/)
* Check the Vulkan SDK version in [dub.json](../dub.json) and update if needed
 
Build all dependencies from `app/jni/` using cmake.
See [app/jni/WINDOWS.md](../app/jni/WINDOWS.md) for the full Windows build commands for each dependency.
 
Once dependencies are built:
```
dub
```
