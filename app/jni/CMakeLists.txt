cmake_minimum_required(VERSION 3.15)
project(cimgui)

# Options
option(CIMGUI_STATIC     "Build as static library"  OFF)
option(CIMGUI_USE_SDL2   "Enable SDL2 backend"      ON)
option(CIMGUI_USE_SDL3   "Enable SDL3 backend"      OFF)
option(CIMGUI_USE_VULKAN "Enable Vulkan backend"    ON)

# Paths — override with -DVULKAN_DIR=... and -DSDL3_DIR=...
set(VULKAN_DIR "" CACHE PATH "Vulkan SDK root (Windows: C:/VulkanSDK/x.x.x.x, Linux: /usr)")
set(SDL3_DIR   "" CACHE PATH "SDL3 root (e.g. ../app/jni/SDL)")
set(SDL2_DIR   "" CACHE PATH "SDL2 root (e.g. ../app/jni/SDL2)")

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
    if(SDL3_DIR STREQUAL "")
        message(FATAL_ERROR "SDL3_DIR not set — pass -DSDL3_DIR=path/to/SDL3")
    endif()
    list(APPEND SOURCES  ${IMGUI_DIR}/backends/imgui_impl_sdl3.cpp)
    list(APPEND INCLUDES ${SDL3_DIR}/include)
    list(APPEND DEFINES  CIMGUI_USE_SDL3)
endif()

# SDL2 backend
if(CIMGUI_USE_SDL2)
    if(SDL2_DIR STREQUAL "")
        message(FATAL_ERROR "SDL2_DIR not set — pass -DSDL2_DIR=path/to/SDL2")
    endif()
    list(APPEND SOURCES  ${IMGUI_DIR}/backends/imgui_impl_sdl2.cpp)
    list(APPEND INCLUDES ${SDL2_DIR}/include)
    list(APPEND DEFINES  CIMGUI_USE_SDL2)
endif()

# Vulkan backend
if(CIMGUI_USE_VULKAN)
    if(VULKAN_DIR STREQUAL "")
        message(FATAL_ERROR "VULKAN_DIR not set — pass -DVULKAN_DIR=path/to/VulkanSDK")
    endif()
    list(APPEND SOURCES  ${IMGUI_DIR}/backends/imgui_impl_vulkan.cpp)
    if(WIN32)
        list(APPEND INCLUDES ${VULKAN_DIR}/Include)
    else()
        list(APPEND INCLUDES ${VULKAN_DIR}/include)
    endif()
    list(APPEND DEFINES  CIMGUI_USE_VULKAN)
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
        target_link_directories(cimgui PRIVATE ${SDL3_DIR}/../build/Release)
        target_link_libraries(cimgui PRIVATE SDL3)
    else()
        target_link_directories(cimgui PRIVATE ${SDL3_DIR}/build)
        target_link_libraries(cimgui PRIVATE SDL3)
    endif()
endif()

if(CIMGUI_USE_SDL2)
    if(WIN32)
        target_link_directories(cimgui PRIVATE ${SDL2_DIR}/../build/Release)
        target_link_libraries(cimgui PRIVATE SDL2)
    else()
        target_link_directories(cimgui PRIVATE ${SDL2_DIR}/build)
        target_link_libraries(cimgui PRIVATE SDL2)
    endif()
endif()

if(CIMGUI_USE_VULKAN)
    if(WIN32)
        target_link_directories(cimgui PRIVATE ${VULKAN_DIR}/Lib)
        target_link_libraries(cimgui PRIVATE vulkan-1)
    else()
        target_link_libraries(cimgui PRIVATE vulkan)
    endif()
endif()

# Install
install(TARGETS cimgui DESTINATION lib)
install(FILES ${CIMGUI_DIR}/cimgui.h DESTINATION include)
