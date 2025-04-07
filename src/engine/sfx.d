import includes;

struct Audio {
  const(char)*[] chunk;
  const(char)*[] music;

  ushort audioFmt;
  int audioRate, audioChannels;

  @property int bits(){ return(audioFmt & 0xFF); }
  @property int sampleSize(){ return((bits / 8) + audioChannels); }
}

void openAudio(int rate = 44100, int size = 1024) {
  Audio sfx;

  Mix_OpenAudio(rate, AUDIO_S32LSB, 2, size);
  int nChunk = Mix_GetNumChunkDecoders();
  int nMusic = Mix_GetNumMusicDecoders();

  sfx.chunk.length = nChunk;
  sfx.music.length = nMusic;

  for(int i = 0; i < nChunk; ++i){ sfx.chunk[i] = Mix_GetChunkDecoder(i); } ;
  for(int i = 0; i < nMusic; ++i){ sfx.music[i] = Mix_GetMusicDecoder(i); } ;

  Mix_QuerySpec(&sfx.audioRate, &sfx.audioFmt, &sfx.audioChannels);
  SDL_Log("Decoders chunks|music %d|%d", nChunk, nMusic);
  SDL_Log("Audio @ %d Hz %d bit %s with %d bits audio buffer\n", sfx.audioRate, sfx.bits, sfx.audioChannels > 1?"stereo".ptr:"mono".ptr, size);
}
