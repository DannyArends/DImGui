import engine;

App initializeSDL() {
  App app;
  SDL_Init(SDL_INIT_VIDEO);
  SDL_WindowFlags window_flags = (SDL_WindowFlags)(SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
  app.window = SDL_CreateWindow("ImGUI", SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), SDL_WINDOWPOS_UNDEFINED_DISPLAY(0), 1280, 720, window_flags);
  SDL_Log("SDL_CreateWindow: %p", app.window);
  return(app);
}
