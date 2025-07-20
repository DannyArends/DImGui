/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : dir;

/** WAV format for sound effects
 */
struct WavFMT {
  string path;
  Mix_Chunk* chunk;
  float pitch = 1.0;
  float gain = 0.5;
  bool loaded = false;
  bool looping = false;
}

/** Audio information structure
 */
struct Audio {
  const(char)*[] chunk;
  const(char)*[] music;

  ushort audioFmt;
  int audioRate, audioChannels;

  @property int bits(){ return(audioFmt & 0xFF); }
  @property int sampleSize(){ return((bits / 8) + audioChannels); }
}

string[] listAudioDevices() {
  uint nDevices = SDL_GetNumAudioDevices(0); // 0 for output devices
  if(nDevices == 0){ SDL_Log("Error: No audio output devices found"); return([]); }

  string[] devices; devices.length = nDevices; // Create Devices

  for (uint i = 0; i < nDevices; ++i) {
    const char* device_name = SDL_GetAudioDeviceName(i, 0); // 0 for output device
    if (device_name != null) {
      devices[i] = to!string(fromStringz(device_name));
    } else { SDL_Log("Error: Could not get device name for index %d, Error: %s", i, SDL_GetError()); }
  }
  return(devices);
}

/** Initialize audio and open an audio channel
 */
void openAudio(int rate = 44100, int size = 1024, bool verbose = false) {
  Audio sfx;
  auto devices = listAudioDevices();

  Mix_OpenAudio(rate, AUDIO_S32LSB, 2, size);
  int nChunk = Mix_GetNumChunkDecoders();
  int nMusic = Mix_GetNumMusicDecoders();

  sfx.chunk.length = nChunk;
  sfx.music.length = nMusic;

  for(int i = 0; i < nChunk; ++i){ sfx.chunk[i] = Mix_GetChunkDecoder(i); } ;
  for(int i = 0; i < nMusic; ++i){ sfx.music[i] = Mix_GetMusicDecoder(i); } ;

  Mix_QuerySpec(&sfx.audioRate, &sfx.audioFmt, &sfx.audioChannels);
  if(verbose) {
    SDL_Log(toStringz(format("Audio Devices: %s", devices)));
    SDL_Log("Audio @ %d Hz, Decoders chunks|music %d|%d", sfx.audioRate, nChunk, nMusic);
    SDL_Log("Audio %d bit %s with %d bits audio buffer\n", sfx.bits, sfx.audioChannels > 1?"stereo".ptr:"mono".ptr, size);
  }
}

/** Load a WAV formatted file
 */
WavFMT loadWav(string path, float pitch = 1.0, float gain = 0.5, bool looping = false) {
  WavFMT sfx = { path: path, 
                 chunk: Mix_LoadWAV(toStringz(path)),
                 pitch: pitch, gain: gain, loaded: false, looping: looping
                };
  if (!sfx.chunk) {
    SDL_Log("Unable to create buffer for '%s' cause '%s'", toStringz(path), SDL_GetError());
    return sfx;
  }
  sfx.loaded = true;
  Mix_VolumeChunk(sfx.chunk, cast(int)(sfx.gain * SDL_MIX_MAXVOLUME));
  return(sfx);
}

/** Load all CasualGameSounds WAV sound effects
 */
void loadAllSoundEffect(ref App app, const(char)* path = "data/sfx/CasualGameSounds", float pitch = 1.0, float gain = 0.5, bool looping = false, bool play = false) {
  auto files = dir(path, "*.wav");
  foreach(file; files) {
    app.soundfx ~= loadWav(file, pitch, gain, looping);
  }
  SDL_Log("Loaded %d sounds effects from: %s", app.soundfx.length, path);
}

/** Play a sound effect
 */
int play(const App app, WavFMT sfx) { 
  if(!sfx.loaded) return(-1);
  Mix_VolumeChunk(sfx.chunk, cast(int)(sfx.gain * app.soundEffectGain * SDL_MIX_MAXVOLUME));
  return(Mix_PlayChannel(-1, cast(Mix_Chunk*)(sfx.chunk), 0));
}

