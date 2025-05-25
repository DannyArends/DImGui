/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import std.stdio : writefln;
import std.string : toStringz, fromStringz;

import io : readFile;

/** Create the ShaderC compiler
 */
void createCompiler(ref App app) {
  app.compiler = shaderc_compiler_initialize();
  if(!app.compiler) { SDL_Log("Failed to initialize shaderc compiler."); abort(); }

  app.options = shaderc_compile_options_initialize();
  if (!app.options) {
    SDL_Log("Failed to initialize shaderc compiler options.");
    shaderc_compiler_release(app.compiler);
    abort();
  }
  shaderc_compile_options_set_generate_debug_info(app.options);
}

/** Load GLSL, compile to SpirV, and create the vulkan shaderModule
 */
VkShaderModule createShaderModule(App app, const(char)* path, shaderc_shader_kind type = shaderc_glsl_vertex_shader) {
  auto source = readFile(path, app.verbose);
  auto result = shaderc_compile_into_spv(app.compiler, &(cast(char[])source)[0], source.length, type, path, "main", app.options);

  if (shaderc_result_get_compilation_status(result) != shaderc_compilation_status_success) {
    SDL_Log("Shader '%s' compilation failed:\n%s", path, shaderc_result_get_error_message(result));
    shaderc_result_release(result);
    shaderc_compile_options_release(app.options);
    shaderc_compiler_release(app.compiler);
    abort();
  }

  auto code = shaderc_result_get_bytes(result);
  auto codeSize = shaderc_result_get_length(result);
  VkShaderModuleCreateInfo createInfo = {
    sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    codeSize: codeSize,
    pCode: &(cast(const(uint)*)(code))[0]
  };
  VkShaderModule shaderModule;
  enforceVK(vkCreateShaderModule(app.device, &createInfo, null, &shaderModule));

  shaderc_result_release(result); // Release the compilation result
  return(shaderModule);
}

/** createShaderStageInfo helper function, since the VkPipelineShaderStageCreateInfo contains a variable "module"
 */
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

/** Load vertex and fragment shaders, and create the shaderStages array
 */
void createShadersStages(ref App app, const(char)* vertPath = "assets/shaders/vertex.glsl", 
                                      const(char)* fragPath = "assets/shaders/fragment.glsl"){
  auto vShader = app.createShaderModule(vertPath, shaderc_glsl_vertex_shader);
  auto fShader = app.createShaderModule(fragPath, shaderc_glsl_fragment_shader);
  app.shaders = [ vShader, fShader ];

  VkPipelineShaderStageCreateInfo vInfo = createShaderStageInfo(VK_SHADER_STAGE_VERTEX_BIT, vShader);
  VkPipelineShaderStageCreateInfo fInfo = createShaderStageInfo(VK_SHADER_STAGE_FRAGMENT_BIT, fShader);
  app.shaderStages = [ vInfo, fInfo ];

  app.mainDeletionQueue.add(() {
    vkDestroyShaderModule(app.device, app.shaders[0], app.allocator);
    vkDestroyShaderModule(app.device, app.shaders[1], app.allocator);
  });
}
