import includes;
import std.conv : to;
import std.string : toStringz;
import std.array : join;

import application : App;

void printSoundDecoders() {
  int nChunk = Mix_GetNumChunkDecoders();
  int nMusic = Mix_GetNumMusicDecoders();

  string chunk = "(chunk):";
  string music = "(music):";

  for(int i =  0; i < nChunk; ++i){ chunk ~= " " ~ to!string(Mix_GetChunkDecoder(i)); } ;
  for(int i = 0; i < nMusic; ++i){ music ~= " " ~ to!string(Mix_GetMusicDecoder(i)); } ;

  int bits, sample_size, rate, audio_rate,audio_channels;
  Uint16 audio_format;
  Mix_QuerySpec(&audio_rate, &audio_format, &audio_channels);
  bits = audio_format&0xFF;
  sample_size = bits/8+audio_channels;
  rate = audio_rate;
  SDL_Log("Decoders %s", toStringz(chunk));
  SDL_Log("Decoders %s", toStringz(music));
  SDL_Log("Audio @ %d Hz %d bit %s, %d bytes audio buffer\n", audio_rate, bits, audio_channels>1?"stereo".ptr:"mono".ptr, 1024 );
}

void initSDL(ref App app){
  app.g_Window = *ImGui_ImplVulkanH_Window_ImGui_ImplVulkanH_Window();

  // Setup SDL
  SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER);
  SDL_version linked;

  SDL_GetVersion(&linked);
  SDL_Log("SDL[C] v%u.%u.%u", SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_PATCHLEVEL);
  SDL_Log("SDL[L] v%u.%u.%u", linked.major, linked.minor, linked.patch);

  SDL_Log("SDL[TTF] %d", TTF_Init());
  linked = *TTF_Linked_Version();
  SDL_Log("TTF[C] v%u.%u.%u", SDL_TTF_MAJOR_VERSION, SDL_TTF_MINOR_VERSION, SDL_TTF_PATCHLEVEL);
  SDL_Log("TTF[L] v%u.%u.%u", linked.major, linked.minor, linked.patch);

  int r = IMG_Init(IMG_INIT_JPG | IMG_INIT_PNG | IMG_INIT_TIF);
  string[] gfxFmts;
  if(r & IMG_INIT_JPG) gfxFmts ~= "jpg";
  if(r & IMG_INIT_PNG) gfxFmts ~= "png";
  if(r & IMG_INIT_TIF) gfxFmts ~= "tif";
  SDL_Log("SDL[IMG] %d = %s", r, toStringz(gfxFmts.join(",")));
  linked = *IMG_Linked_Version();
  SDL_Log("TTF[C] v%u.%u.%u", SDL_IMAGE_MAJOR_VERSION, SDL_IMAGE_MINOR_VERSION, SDL_IMAGE_PATCHLEVEL);
  SDL_Log("TTF[L] v%u.%u.%u", linked.major, linked.minor, linked.patch);

  SDL_Log("SDL[MIX] %d", Mix_Init(MIX_INIT_MP3 | MIX_INIT_OGG | MIX_INIT_MID));
  linked = *Mix_Linked_Version();
  SDL_Log("MIX[C] v%u.%u.%u", SDL_MIXER_MAJOR_VERSION, SDL_MIXER_MINOR_VERSION, SDL_MIXER_PATCHLEVEL);
  SDL_Log("MIX[L] v%u.%u.%u", linked.major, linked.minor, linked.patch);

  Mix_OpenAudio(44100, AUDIO_S32LSB, 2, 1024);
  printSoundDecoders();

  SDL_WindowFlags window_flags = (SDL_WindowFlags)(SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
  app.ptr = SDL_CreateWindow("ImGUI", SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), 1280, 720, window_flags);
}


void quitSDL(ref App app){
  SDL_DestroyWindow(app);
  Mix_CloseAudio();
  Mix_Quit();
  IMG_Quit();
  TTF_Quit();
  SDL_Quit();
}

