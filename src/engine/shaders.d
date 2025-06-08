/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import std.stdio : writefln;
import std.string : toStringz, fromStringz;

import descriptor : Descriptor, DescriptorLayoutBuilder;
import io : readFile;
import reflection : convert, reflectShader;

struct Shader {
  const(char)* path;                      /// Path of the shader
  VkShaderStageFlagBits stage;            /// Shader Stage (Vertex, Fragment, Compute)
  VkShaderModule shaderModule;            /// Vulkan Shader Module
  VkPipelineShaderStageCreateInfo info;   /// Shader Stage Create Info Object

  char[] source;                          /// Source code
  const(uint)* code;                      /// Compiled Code
  size_t codeSize;                        /// Size of the compiled code
  @property size_t nwords(){ return(codeSize / uint.sizeof); };

  uint[3] groupCount;
  Descriptor[] descriptors;
  alias shaderModule this;
}

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

  app.mainDeletionQueue.add((){
    shaderc_compile_options_release(app.options);
    shaderc_compiler_release(app.compiler);
  });
}

/** Load GLSL, compile to SpirV, and create the vulkan shaderModule
 */
Shader createShaderModule(App app, const(char)* path, shaderc_shader_kind type = shaderc_glsl_vertex_shader) {
  auto source = readFile(path, app.verbose);
  auto result = shaderc_compile_into_spv(app.compiler, &source[0], source.length, type, path, "main", app.options);

  Shader shader = {path : path, stage : convert(type), source : source};

  if (shaderc_result_get_compilation_status(result) != shaderc_compilation_status_success) {
    SDL_Log("Shader '%s' compilation failed:\n%s", path, shaderc_result_get_error_message(result));
    shaderc_result_release(result);
    shaderc_compile_options_release(app.options);
    shaderc_compiler_release(app.compiler);
    abort();
  }

  shader.code = cast(const(uint)*)(shaderc_result_get_bytes(result));
  shader.codeSize = shaderc_result_get_length(result);
  VkShaderModuleCreateInfo createInfo = {
    sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    codeSize: shader.codeSize,
    pCode: &shader.code[0]
  };

  enforceVK(vkCreateShaderModule(app.device, &createInfo, null, &shader.shaderModule));
  shader.info = createShaderStageInfo(convert(type), shader);

  app.mainDeletionQueue.add((){
    shaderc_result_release(result); // Release the compilation result
  });
  return(shader);
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

VkPipelineShaderStageCreateInfo[] createStageInfo(Shader[] shaders) {
  VkPipelineShaderStageCreateInfo[] info;
  foreach(shader; shaders){ info ~= shader.info; }
  return(info);
}

/** Load vertex and fragment shaders, and create the shaderStages array
 */
void createRenderShaders(ref App app, const(char)* vertPath = "data/shaders/vertex.glsl", 
                                      const(char)* fragPath = "data/shaders/fragment.glsl") {
  auto vShader = app.createShaderModule(vertPath, shaderc_glsl_vertex_shader);
  auto fShader = app.createShaderModule(fragPath, shaderc_glsl_fragment_shader);

  app.shaders = [ vShader, fShader ];

  app.mainDeletionQueue.add(() {
    for(uint i = 0; i < app.shaders.length; i++) {
      vkDestroyShaderModule(app.device, app.shaders[i], app.allocator);
    }
  });
}

