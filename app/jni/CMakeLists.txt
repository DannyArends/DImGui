cmake_minimum_required(VERSION 3.15)
project(cimgui)
if(ANDROID)
    # SDL3
    set(SDL_STATIC OFF)
    set(SDL_SHARED ON)
    set(SDL_TESTS OFF)
    set(SDL_TEST_LIBRARY OFF)
    set(SDL_EXAMPLES OFF)
    set(SDL_HIDAPI_LIBUSB OFF)
    add_subdirectory(SDL SDL_build)
    set(SDL3_DIR ${CMAKE_CURRENT_SOURCE_DIR}/SDL)

    # spirv_cross
    cmake_policy(SET CMP0077 NEW)
    set(SPIRV_CROSS_ENABLE_TESTS OFF)
    set(SPIRV_CROSS_CLI OFF)
    set(SPIRV_CROSS_ENABLE_MSL OFF)
    set(SPIRV_CROSS_SHARED ON CACHE BOOL "" FORCE)
    add_subdirectory(spirv_cross spirv_cross_build)

    # assimp
    set(ASSIMP_BUILD_TESTS OFF)
    add_compile_definitions("FOPEN_FUNC(filename,mode)=fopen(filename,mode)")
    set(ASSIMP_INSTALL OFF)
    set(ASSIMP_BUILD_ASSIMP_TOOLS OFF)
    set(ASSIMP_NO_EXPORT ON)
    set(ASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT OFF)
    set(ASSIMP_BUILD_FBX_IMPORTER ON)
    set(ASSIMP_BUILD_3DS_IMPORTER ON)
    set(ASSIMP_BUILD_OBJ_IMPORTER ON)
    add_subdirectory(assimp assimp_build)

    # shaderc
    set(SHADERC_SKIP_TESTS ON)
    set(SHADERC_SKIP_EXAMPLES ON)
    set(SHADERC_SKIP_COPYRIGHT_CHECK ON)
    set(SHADERC_ENABLE_WGSL_OUTPUT OFF)
    set(ENABLE_GLSLANG_BINARIES OFF)
    set(ENABLE_CTEST OFF)
    add_subdirectory(shaderc shaderc_build)

    # SDL_image
    set(SDLIMAGE_AVIF OFF) 
    set(SDLIMAGE_WEBP OFF)
    set(SDLIMAGE_TIF OFF)
    set(SDLIMAGE_XCF OFF)
    set(SDLIMAGE_XPM OFF)
    set(SDLIMAGE_XV OFF)
    set(SDLIMAGE_LBM OFF)
    set(SDLIMAGE_PCX OFF)
    set(SDLIMAGE_PNM OFF)
    set(SDLIMAGE_QOI OFF)
    set(SDLIMAGE_SVG OFF)
    set(SDLIMAGE_TGA OFF)
    set(SDLIMAGE_GIF OFF)
    set(SDLIMAGE_ANI OFF)
    set(SDLIMAGE_SAMPLES OFF)
    set(SDLIMAGE_TESTS OFF)
    add_subdirectory(SDL_image SDL_image_build)

    # SDL_mixer
    set(SDLMIXER_AIFF OFF)
    set(SDLMIXER_VOC OFF)
    set(SDLMIXER_AU OFF)
    set(SDLMIXER_FLAC OFF)
    set(SDLMIXER_GME OFF)
    set(SDLMIXER_MOD OFF)
    set(SDLMIXER_MP3 OFF)
    set(SDLMIXER_MIDI OFF)
    set(SDLMIXER_OPUS OFF)
    set(SDLMIXER_VORBIS_STB OFF)
    set(SDLMIXER_VORBIS_VORBISFILE OFF)
    set(SDLMIXER_WAVPACK OFF)
    set(SDLMIXER_EXAMPLES OFF)
    set(SDLMIXER_TESTS OFF)
    add_subdirectory(SDL_mixer SDL_mixer_build)

    # SDL_ttf
    set(SDLTTF_SAMPLES OFF)
    add_subdirectory(SDL_ttf SDL_ttf_build)
endif()
# Options
option(CIMGUI_STATIC     "Build as static library"  OFF)
option(CIMGUI_USE_SDL3   "Enable SDL3 backend"      ON)
option(CIMGUI_USE_VULKAN "Enable Vulkan backend"    ON)

# Paths — override with -DVULKAN_DIR=... and -DSDL3_DIR=...
set(VULKAN_DIR "" CACHE PATH "Vulkan SDK root (Windows: C:/VulkanSDK/x.x.x.x, Linux: /usr)")
set(SDL3_DIR   "" CACHE PATH "SDL3 root (e.g. ../app/jni/SDL)")
set(IMGUI_DIR  ${CMAKE_CURRENT_SOURCE_DIR}/cimgui/imgui)
set(CIMGUI_DIR ${CMAKE_CURRENT_SOURCE_DIR}/cimgui)

# Core sources
set(SOURCES
    ${CIMGUI_DIR}/cimgui.cpp
    ${CIMGUI_DIR}/cimgui_impl.cpp
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_demo.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
)

# Core includes
set(INCLUDES
    ${IMGUI_DIR}
    ${IMGUI_DIR}/backends
)

# Core defines
set(DEFINES
    IMGUI_DISABLE_OBSOLETE_FUNCTIONS
)

# SDL3 backend
if(CIMGUI_USE_SDL3)
    if(ANDROID)
        list(APPEND INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/SDL/include)
    elseif(SDL3_DIR STREQUAL "")
        message(FATAL_ERROR "SDL3_DIR not set — pass -DSDL3_DIR=path/to/SDL3")
    else()
        list(APPEND INCLUDES ${SDL3_DIR}/include)
    endif()
    list(APPEND SOURCES  ${IMGUI_DIR}/backends/imgui_impl_sdl3.cpp)
    list(APPEND DEFINES  CIMGUI_USE_SDL3)
endif()

# Vulkan backend
if(CIMGUI_USE_VULKAN)
    list(APPEND SOURCES  ${IMGUI_DIR}/backends/imgui_impl_vulkan.cpp)
    list(APPEND DEFINES  CIMGUI_USE_VULKAN)
    if(ANDROID)
        # NDK provides Vulkan headers automatically
    elseif(VULKAN_DIR STREQUAL "")
        message(FATAL_ERROR "VULKAN_DIR not set — pass -DVULKAN_DIR=path/to/VulkanSDK")
    elseif(WIN32)
        list(APPEND INCLUDES ${VULKAN_DIR}/Include)
    else()
        list(APPEND INCLUDES ${VULKAN_DIR}/include)
    endif()
endif()

# Build target — must come before target_* calls
if(CIMGUI_STATIC)
    add_library(cimgui STATIC ${SOURCES})
else()
    add_library(cimgui SHARED ${SOURCES})
endif()

target_include_directories(cimgui PRIVATE ${INCLUDES})

# Platform specific IMGUI_IMPL_API and compile options
if(WIN32)
    target_compile_definitions(cimgui PRIVATE
        ${DEFINES}
        "IMGUI_IMPL_API=extern \"C\" __declspec(dllexport)"
    )
else()
    target_compile_definitions(cimgui PRIVATE
        ${DEFINES}
        "IMGUI_IMPL_API=extern \"C\""
    )
    target_compile_options(cimgui PRIVATE -fvisibility=default)
endif()

# Link dependencies
if(CIMGUI_USE_SDL3)
    if(WIN32)
        target_link_directories(cimgui PRIVATE ${SDL3_DIR}/build)
        target_link_libraries(cimgui PRIVATE SDL3)
    elseif(ANDROID)
        target_link_libraries(cimgui PRIVATE SDL3-shared)
    else()
        target_link_directories(cimgui PRIVATE ${SDL3_DIR}/build)
        target_link_libraries(cimgui PRIVATE SDL3)
    endif()
endif()

if(CIMGUI_USE_VULKAN)
    if(WIN32)
        target_link_directories(cimgui PRIVATE ${VULKAN_DIR}/Lib)
        target_link_libraries(cimgui PRIVATE vulkan-1)
    elseif(ANDROID)
        target_link_libraries(cimgui PRIVATE -lvulkan)
    else()
        target_link_libraries(cimgui PRIVATE vulkan)
    endif()
endif()

# Install
install(TARGETS cimgui DESTINATION lib)
install(FILES ${CIMGUI_DIR}/cimgui.h DESTINATION include)
