import engine;

void initializeImGui(ref App app){
  igCreateContext(null);
  app.io = igGetIO_Nil();
  app.io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
  igStyleColorsDark(null);
  if(app.verbose) SDL_Log("ImGuiIO: %p", app.io);
  ImGui_ImplSDL2_InitForVulkan(app.window);

  ImGui_ImplVulkan_InitInfo imguiInit = {
    Instance : app.instance,
    PhysicalDevice : app.physicalDevice,
    Device : app.device,
    QueueFamily : app.queueFamily,
    Queue : app.queue,
    DescriptorPool : app.imguiPool,
    Allocator : app.allocator,
    MinImageCount : app.capabilities.minImageCount,
    ImageCount : cast(uint)app.imageCount,
    RenderPass : app.imguiPass,
    CheckVkResultFn : &enforceVK
  };
  ImGui_ImplVulkan_Init(&imguiInit);
  if(app.verbose) SDL_Log("ImGui initialized");
}
