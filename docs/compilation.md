### Prerequisites
You will need a C++ as well as a D compiler and CMake.
* [DMD or LDC2 compiler](https://dlang.org/download.html)
* [CMake](https://cmake.org/)

### Clone the repository
First clone the repository, and initialize all dependancies.
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

### Unitests
Run unittests with:
```
dub --build=unittest --force
```

### Compilation [MS Windows x64]
 
* Install [Visual Studio 2019 Build Tools](https://visualstudio.microsoft.com/downloads/?q=build+tools) with **MSVC v142** and the **Windows 10 SDK**
* Install the [LunarG Vulkan SDK](https://vulkan.lunarg.com/)
* Check the Vulkan SDK version in [dub.json](../dub.json) and update if needed
 
Build all dependencies from `app/jni/` using cmake. This can be done by following the instruction in 
[app/jni/WINDOWS.md](../app/jni/WINDOWS.md) for the full Windows build commands for each dependency.
 
Once dependencies are built, compile the resource file and the executable:

```
call "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
rc /nologo /fo app\windows\CalderaD.res app\windows\CalderaD.rc
dub --build=release --force
```

### Generate a windows installer
Prerequisites:
* [Inno Setup 6+](https://jrsoftware.org/isdl.php) (or `winget install JRSoftware.InnoSetup`). The compiler is `ISCC.exe`; it is not added to `PATH` by default, so either add its folder (e.g. `C:\Program Files (x86)\Inno Setup 6`) to `PATH` or call it by full path.
* The commands below **must run from a `vcvars64` shell**: `app\installer.iss` reads `%VCToolsRedistDir%` (set by `vcvars64.bat`) to locate and bundle the VC++ runtime DLLs. Running `iscc` outside that shell fails with a "VCToolsRedistDir is not set" error.

Make sure to set the verbose level and have validation layers in src/engine.d disabled. The compile using
```
call "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
rc /nologo /fo app\windows\CalderaD.res app\windows\CalderaD.rc
dub build --build=release
iscc app\installer.iss
```
The installer is written to `bin\CalderaD-Setup.exe`.