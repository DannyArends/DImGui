/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import std.conv : to;
import io : dir;

/** WAV format for sound effects
 */
struct WavFMT {
  const(char)* path;
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

/** Initialize audio and open an audio channel
 */
void openAudio(int rate = 44100, int size = 1024, bool verbose = false) {
  Audio sfx;

  Mix_OpenAudio(rate, AUDIO_S32LSB, 2, size);
  int nChunk = Mix_GetNumChunkDecoders();
  int nMusic = Mix_GetNumMusicDecoders();

  sfx.chunk.length = nChunk;
  sfx.music.length = nMusic;

  for(int i = 0; i < nChunk; ++i){ sfx.chunk[i] = Mix_GetChunkDecoder(i); } ;
  for(int i = 0; i < nMusic; ++i){ sfx.music[i] = Mix_GetMusicDecoder(i); } ;

  Mix_QuerySpec(&sfx.audioRate, &sfx.audioFmt, &sfx.audioChannels);
  if(verbose) SDL_Log("Decoders chunks|music %d|%d", nChunk, nMusic);
  if(verbose) SDL_Log("Audio @ %d Hz %d bit %s with %d bits audio buffer\n", sfx.audioRate, sfx.bits, sfx.audioChannels > 1?"stereo".ptr:"mono".ptr, size);
}

/** Load a WAV formatted file
 */
WavFMT loadWav(const(char)* path, float pitch = 1.0, float gain = 0.5, bool looping = false) {
  WavFMT sfx = { path: path, 
                 chunk: Mix_LoadWAV(path),
                 pitch: pitch, gain: gain, loaded: false, looping: looping
                };
  if (!sfx.chunk) {
    SDL_Log("Unable to create buffer for '%s' cause '%s'\n", path, SDL_GetError());
    return sfx;
  }
  sfx.loaded = true;
  Mix_VolumeChunk(sfx.chunk, cast(int)(sfx.gain * SDL_MIX_MAXVOLUME));
  return(sfx);
}

/** Load all CasualGameSounds WAV sound effects
 */
void loadAllSoundEffect(ref App app, const(char)* path = "assets/sfx/CasualGameSounds", float pitch = 1.0, float gain = 0.5, bool looping = false, bool play = false) {
  auto files = dir(to!string(path), "*.wav");
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

