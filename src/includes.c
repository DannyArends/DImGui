// Copyright Danny Arends 2025
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#define SDLCALL
#define DECLSPEC
#define SDL_INIT_TIMER 0x00000001u
#define SDL_INIT_VIDEO 0x00000020u
#define SDL_INIT_GAMECONTROLLER 0x00002000u
extern DECLSPEC int SDLCALL SDL_Init(Uint32 flags);
extern DECLSPEC void SDLCALL SDL_Quit(void);

#include <SDL_audio.h>
#include <SDL_events.h>
#include <SDL_video.h>
#include <SDL_log.h>
#include <SDL_render.h>
#include <SDL_timer.h>
#include <SDL_version.h>
#include <SDL_vulkan.h>

#define SDL_h_
#undef SDL_DEPRECATED
#define SDL_DEPRECATED
#include <SDL_ttf.h>
#include <SDL_image.h>
#include <SDL_mixer.h>
#include <vulkan/vulkan.h>

#define IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE   (1)     // Minimum per atlas

#define CIMGUI_USE_SDL2
#define CIMGUI_USE_VULKAN
#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#include "cimgui.h"
#include "cimgui_impl.h"

