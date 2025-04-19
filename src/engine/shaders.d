// Copyright Danny Arends 2025
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

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

void createShadersStages(ref App app, const(char)* vertPath = "assets/shaders/vert.spv", const(char)* fragPath = "assets/shaders/frag.spv"){
  auto vShader = app.createShaderModule(vertPath);
  auto fShader = app.createShaderModule(fragPath);
  app.shaders = [ vShader, fShader ];

  VkPipelineShaderStageCreateInfo vInfo = createShaderStageInfo(VK_SHADER_STAGE_VERTEX_BIT, vShader);
  VkPipelineShaderStageCreateInfo fInfo = createShaderStageInfo(VK_SHADER_STAGE_FRAGMENT_BIT, fShader);
  app.shaderStages = [ vInfo, fInfo ];
}

