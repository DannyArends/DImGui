echo off
set vulkandir=%1
set X=./deps/cimgui
set Y=%X%/imgui
mkdir bin
call "C:/Program Files/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat"
cl.exe /LD /Fe:./bin/ /Fo:./bin/ /DIMGUI_DISABLE_OBSOLETE_FUNCTIONS=1 /DIMGUI_IMPL_API="extern \"C\" __declspec(dllexport)" /DCIMGUI_USE_SDL2 /DCIMGUI_USE_VULKAN ^
/I %Y% /I %Y%/backends/ /I %vulkandir%/Include /I %vulkandir%/Include/SDL2 ^
%X%/cimgui.cpp %X%/cimgui_impl.cpp %Y%/imgui.cpp %Y%/imgui_draw.cpp %Y%/imgui_demo.cpp %Y%/imgui_tables.cpp ^
%Y%/imgui_widgets.cpp %Y%/backends/imgui_impl_vulkan.cpp %Y%/backends/imgui_impl_sdl2.cpp ^
SDL2main.lib SDL2.lib vulkan-1.lib /link /LIBPATH:%vulkandir%/Lib
rm ./bin/*.obj
