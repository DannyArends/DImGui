import engine;

void initializeImGui(ref App app){
  igCreateContext(null);
  ImGuiIO* io = igGetIO_Nil();
  io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
  igStyleColorsDark(null);
  SDL_Log("ImGuiIO: %p", io);
  ImGui_ImplSDL2_InitForVulkan(app.window);

  ImGui_ImplVulkan_InitInfo imguiInit = {
    Instance : app.instance,
    PhysicalDevice : app.physicalDevice,
    Device : app.device,
    QueueFamily : app.queueFamily,
    Queue : app.queue,
    DescriptorPool : app.descriptorPool,
    Allocator : app.allocator,
    MinImageCount : app.capabilities.minImageCount,
    ImageCount : cast(uint)app.imageCount,
    RenderPass : app.imguiPass,
    CheckVkResultFn : &enforceVK
  };
  ImGui_ImplVulkan_Init(&imguiInit);
  SDL_Log("ImGui initialized");
}
