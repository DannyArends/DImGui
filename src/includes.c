/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
#undef __SIZEOF_INT128__

#include <SDL3/SDL.h>
#include <SDL3/SDL_video.h>
#include <SDL3/SDL_vulkan.h>
#include <SDL3_image/SDL_image.h>
#include <SDL3_ttf/SDL_ttf.h>
#include <SDL3_image/SDL_image.h>
#include <SDL3_mixer/SDL_mixer.h>

#if defined(__ANDROID__)
  #include <jni.h>
  #include <SDL3/SDL_system.h>
#endif

#include <vulkan/vulkan.h>
#include <shaderc/shaderc.h>
#include <spirv_cross/spirv_cross_c.h>

#define IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE (1) // Minimum per atlas
#define CIMGUI_USE_SDL3
#define CIMGUI_USE_VULKAN
#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#include "cimgui.h"
#include "cimgui_impl.h"

#include "IconsFontAwesome.h"

// Assimp includes
#include <assimp/cimport.h>
#include <assimp/scene.h>
#include <assimp/material.h>
#include <assimp/types.h>
#include <assimp/postprocess.h>
