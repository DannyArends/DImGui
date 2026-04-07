/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import io : readFile;
import reflection : convert, reflectShader;
import validation : nameVulkanObject;

struct Shader {
  string path;                      /// Path of the shader
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

struct ShaderDef {
  string path;
  shaderc_shader_kind type;
}

ShaderDef[] RenderShaders = [ShaderDef("data/shaders/vertex.glsl", shaderc_glsl_vertex_shader), 
                             ShaderDef("data/shaders/fragment.glsl", shaderc_glsl_fragment_shader)];
ShaderDef[] PostProcessShaders = [ShaderDef("data/shaders/postvertex.glsl", shaderc_glsl_vertex_shader), 
                                  ShaderDef("data/shaders/postfragment.glsl", shaderc_glsl_fragment_shader)];

struct IncluderContext {
  char[][string] includedFiles;
  bool verbose = false;
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
  shaderc_compile_options_set_include_callbacks(app.options, &includeResolve, &includeRelease, cast(void*)&app.includeContext);

  app.mainDeletionQueue.add((){
    shaderc_compile_options_release(app.options);
    shaderc_compiler_release(app.compiler);
  });
}

/** Callback to resolve shader file includes using our own I/O
 */
extern (C) shaderc_include_result* includeResolve(void* userData, const(char)* source, int type, const(char)* reqSource, size_t depth){
  auto context = cast(IncluderContext*)userData;
  char[] code;
  string path;

  if (type == shaderc_include_type_relative) {
    path = format("%s/%s", dirName(fromStringz(reqSource)), fromStringz(source));
    if(context.verbose) SDL_Log(toStringz(format("Shader include: %s", path)));
    code = readFile(toStringz(path), context.verbose);
  }
  context.includedFiles[path] = code;
  char[]* storedContentRef = &(context.includedFiles[path]); 

  shaderc_include_result* result = cast(shaderc_include_result*) malloc(shaderc_include_result.sizeof);
  result.source_name = toStringz(path);
  result.source_name_length = path.length;
  result.content = &((*storedContentRef)[0]);
  result.content_length = context.includedFiles[path].length;
  return(result);
}

/** Callback to release shader files included
 */
extern (C) void includeRelease(void* userData, shaderc_include_result* result) {
  auto context = cast(IncluderContext*)userData;
  if (result) {
    string path = to!string(result.source_name[0..result.source_name_length]);
    if(context.verbose) SDL_Log(toStringz(format("Shader release: %s", path)));
    context.includedFiles.remove(path);
    free(result);
  }
}

/** Load GLSL, compile to SpirV, and create the vulkan shaderModule
 */
Shader createShaderModule(App app, string path, shaderc_shader_kind type = shaderc_glsl_vertex_shader) {
  auto source = readFile(toStringz(path), app.verbose);
  auto result = shaderc_compile_into_spv(app.compiler, &source[0], source.length, type, toStringz(path), "main", app.options);

  Shader shader = {path : path, stage : convert(type), source : source};

  if (shaderc_result_get_compilation_status(result) != shaderc_compilation_status_success) {
    SDL_Log("Shader '%s' compilation failed: '%s'", toStringz(path), shaderc_result_get_error_message(result));
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
  app.nameVulkanObject(shader.shaderModule, toStringz(format("[SHADER] %s", fromStringz(path))), VK_OBJECT_TYPE_SHADER_MODULE);

  shader.info = createShaderStageInfo(convert(type), shader);

  app.mainDeletionQueue.add((){ shaderc_result_release(result); });
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

/** Load shaders to dst using the specified shader definitions
 */
void loadShaders(ref App app, ref Shader[] dst, ShaderDef[] defs) {
  foreach(def; defs) { dst ~= app.createShaderModule(def.path, def.type); }

  app.mainDeletionQueue.add(() {
    for(uint i = 0; i < dst.length; i++) {
      vkDestroyShaderModule(app.device, dst[i], app.allocator);
    }
  });
}

