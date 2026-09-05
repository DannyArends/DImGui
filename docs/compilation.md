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
 
### Compilation (Linux)
Build all dependencies from `app/jni/` using cmake. This can be done by following command:
```
rm -rf app/jni/build
python3 app/jni/shaderc/utils/git-sync-deps
cmake -S app/jni -B app/jni/build -DCMAKE_BUILD_TYPE=Release -DVULKAN_DIR=/usr -DSDL3_DIR="$PWD/app/jni/SDL"
cmake --build app/jni/build -j$(nproc)
```

Once dependencies are built, compile with dub:
```
dub --build=release --force
```

### Compilation (MS Windows)
* Install [Visual Studio 2019 Build Tools](https://visualstudio.microsoft.com/downloads/?q=build+tools) (or above) with **MSVC v142** and the **Windows 10/11 SDK**
* Install the [LunarG Vulkan SDK](https://vulkan.lunarg.com/)
* Check the Vulkan SDK version in [dub.json](../dub.json) and update if needed

Build all dependencies from `app/jni/` using cmake. This can be done by following command:
```
call "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64 10.0.19041.0
rmdir /s /q app\jni\build 2>nul
python app\jni\shaderc\utils\git-sync-deps
cmake -S app/jni -B app/jni/build -DCMAKE_BUILD_TYPE=Release -DVULKAN_DIR="C:/VulkanSDK/1.4.341.1" -DSDL3_DIR="%CD%/app/jni/SDL"
cmake --build app/jni/build --config Release -j10
```

Once dependencies are built, compile the resource file and the executable:
```
call "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64 10.0.19041.0
rc /nologo /fo app\windows\CalderaD.res app\windows\CalderaD.rc
dub --build=release --force
```

### Generate a MS Windows installer
Prerequisites:
* [Inno Setup 6+](https://jrsoftware.org/isdl.php) (or `winget install JRSoftware.InnoSetup`). The compiler is `ISCC.exe`; it is not added to `PATH` by default, so either add its folder (e.g. `C:\Program Files (x86)\Inno Setup 6`) to `PATH` or call it by full path.
* The commands below **must run from a `vcvars64` shell**: `app\installer.iss` reads `%VCToolsRedistDir%` (set by `vcvars64.bat`) to locate and bundle the VC++ runtime DLLs. Running `iscc` outside that shell fails with a "VCToolsRedistDir is not set" error.

For a distributable build, make sure validation layers and verbose logging are disabled in `src/engine.d`. Then compile and package:
```
call "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64 10.0.19041.0
rc /nologo /fo app\windows\CalderaD.res app\windows\CalderaD.rc
dub build --build=release
iscc app\installer.iss
```
The installer is written to `bin\CalderaD-Setup.exe`.

### Unittests (MS Windows & Linux)
Run unittests with:
```
dub --build=unittest --force
```