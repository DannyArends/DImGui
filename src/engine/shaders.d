import engine;

import io : readFile;

VkShaderModule createShaderModule(App app, const(char)* path) {
  auto code = readFile(path, app.verbose);
  VkShaderModuleCreateInfo createInfo = {
    sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    codeSize: cast(uint) code.length,
    pCode: &code[0]
  };
  VkShaderModule shaderModule;
  enforceVK(vkCreateShaderModule(app.device, &createInfo, null, &shaderModule));
  return(shaderModule);
}

VkPipelineShaderStageCreateInfo createShaderStageInfo(VkShaderStageFlagBits stage, VkShaderModule shaderModule, const(char)* name = "main") {
  return(VkPipelineShaderStageCreateInfo(
    VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,    //sType
    null,                                                   //pNext
    VkPipelineShaderStageCreateFlags.init,                  //flags
    stage,                                                  //stage
    shaderModule,                                           //module
    name,                                                   //pName
    null                                                    //pSpecializationInfo
  ));
}

