import engine;

void handleEvents(ref App app){
  SDL_Event event;
  while (SDL_PollEvent(&event)) {
    ImGui_ImplSDL2_ProcessEvent(&event);
    if(event.type == SDL_QUIT) app.finished = true;
    if(event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_CLOSE && event.window.windowID == SDL_GetWindowID(app)) app.finished = true;
  }
}
