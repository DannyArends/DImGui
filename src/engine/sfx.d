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
  MIX_Audio* chunk;
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

  MIX_Mixer* mixer;
  MIX_Track*[] activeTracks;

  SDL_AudioFormat audioFmt;
  int audioRate, audioChannels;

  @property int bits(){ return(audioFmt & 0xFF); }
  @property int sampleSize(){ return((bits / 8) + audioChannels); }
}

string[] listAudioDevices() {
  int nDevices;
  SDL_AudioDeviceID* deviceIDs = SDL_GetAudioPlaybackDevices(&nDevices);
  if(deviceIDs == null || nDevices == 0){ SDL_Log("Error: No audio output devices found"); return([]); }
  string[] devices;
  devices.length = nDevices;
  for (int i = 0; i < nDevices; ++i) {
    const char* device_name = SDL_GetAudioDeviceName(deviceIDs[i]);
    if (device_name != null) {
      devices[i] = to!string(fromStringz(device_name));
    } else { SDL_Log("Error: Could not get device name for index %d, Error: %s", i, SDL_GetError()); }
  }
  SDL_free(deviceIDs);
  return(devices);
}

/** Initialize audio and open an audio channel
 */
void openAudio(ref App app, int rate = 44100, int size = 1024, bool verbose = false) {
  Audio sfx;
  auto devices = listAudioDevices();
  SDL_AudioSpec spec;
  spec.freq = rate;
  spec.format = SDL_AUDIO_S32LE;
  spec.channels = 2;
  app.audio.mixer = MIX_CreateMixerDevice(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec);
  if(app.audio.mixer == null){ SDL_Log("Error: MIX_CreateMixerDevice failed: %s", SDL_GetError()); return; }
  int nDecoders = MIX_GetNumAudioDecoders();
  app.audio.chunk.length = nDecoders; // chunk/music merged in SDL3
  app.audio.music.length = 0;
  for(int i = 0; i < nDecoders; ++i){ app.audio.chunk[i] = MIX_GetAudioDecoder(i); }
  SDL_AudioSpec actual;
  MIX_GetMixerFormat(app.audio.mixer, &actual);
  app.audio.audioRate = actual.freq;
  app.audio.audioFmt = actual.format;
  app.audio.audioChannels = actual.channels;
  if(verbose) {
    SDL_Log(toStringz(format("Audio Devices: %s", devices)));
    SDL_Log("Audio @ %d Hz, Decoders: %d", app.audio.audioRate, nDecoders);
    SDL_Log("Audio %d bit %s with %d bits audio buffer\n", app.audio.bits, app.audio.audioChannels > 1?"stereo".ptr:"mono".ptr, size);
  }
}

/** Load a WAV formatted file
 */
WavFMT loadWav(MIX_Mixer* mixer, string path, float pitch = 1.0, float gain = 0.5, bool looping = false) {
  WavFMT sfx = { path: path,
                 chunk: MIX_LoadAudio(mixer, toStringz(path), true),
                 pitch: pitch, gain: gain, loaded: false, looping: looping
                };
  if (!sfx.chunk) {
    SDL_Log("Unable to create buffer for '%s' cause '%s'", toStringz(path), SDL_GetError());
    return sfx;
  }
  sfx.loaded = true;
  return(sfx);
}

/** Load all CasualGameSounds WAV sound effects
 */
void loadAllSoundEffect(ref App app, const(char)* path = "data/sfx/CasualGameSounds", float pitch = 1.0, float gain = 0.5, bool looping = false, bool play = false) {
  auto files = dir(path, "*.wav");
  foreach(file; files) {
    app.soundfx ~= loadWav(app.audio.mixer, file, pitch, gain, looping);
  }
  SDL_Log("Loaded %d sounds effects from: %s", app.soundfx.length, path);
}

/** Play a sound effect
 */
int play(ref App app, WavFMT sfx) {
  if(!sfx.loaded) return(-1);
  MIX_Track* track = MIX_CreateTrack(app.audio.mixer);
  if(!track) return(-1);
  MIX_SetTrackGain(track, sfx.gain * app.soundEffectGain);
  MIX_SetTrackAudio(track, sfx.chunk);
  if(!MIX_PlayTrack(track, 0)) { MIX_DestroyTrack(track); return(-1); }
  app.audio.activeTracks ~= track;
  return(0);
}

/** Check sound effects for completion
 */
void updateTracks(ref App app) {
  size_t[] done;
  foreach(i, track; app.audio.activeTracks) {
    if(!MIX_TrackPlaying(track)) { MIX_DestroyTrack(track); done ~= i; }
  }
  foreach_reverse(i; done) { app.audio.activeTracks = app.audio.activeTracks.remove(i); }
}

