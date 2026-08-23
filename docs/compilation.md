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
 
Build all dependencies from `app/jni/` using cmake.
See [app/jni/WINDOWS.md](../app/jni/WINDOWS.md) for the full Windows build commands for each dependency.
 
Once dependencies are built:
```
dub
```


#### Cross-Compilation [MS Windows x64 -> Android]
```
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
set PATH=%PATH%;C:\Users\Danny\AppData\Local\Android\Sdk\platform-tools

gradlew --stop

echo === Building native libs ===
gradlew externalNativeBuildDebug

echo === Building D code (libmain.so) ===
dub build --build=release --compiler=ldc2 --arch=aarch64-unknown-linux-android --config=android-64 --force

echo === Assembling APK & Installing ===
gradlew assembleDebug
adb install -r app\build\outputs\apk\debug\app-debug.apk

echo === Launching ===
adb shell am force-stop org.libsdl.app
adb shell monkey -p org.libsdl.app -c android.intent.category.LAUNCHER 1

echo === Connect Logcat ===
adb logcat -c
adb logcat -s SDL,DEBUG,AndroidRuntime,libc
```