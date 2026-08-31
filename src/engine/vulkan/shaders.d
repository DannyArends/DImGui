/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import devices : getMSAASamples;
import io : readFile;
import reflection : convert, reflectShader;
import ssao : SSAO_KERNEL;
import shadow : MAX_SHADOW_MAPS;
import validation : nameVulkanObject;

struct Shader {
  string path;                            /// Path of the shader
  VkShaderStageFlagBits stage;            /// Shader Stage (Vertex, Fragment, Compute)
  VkShaderModule shaderModule;            /// Vulkan Shader Module
  VkPipelineShaderStageCreateInfo info;   /// Shader Stage Create Info Object

  const(char)[] source;                   /// Source code
  const(uint)* code;                      /// Compiled Code
  size_t codeSize;                        /// Size of the compiled code
  @property size_t nwords(){ return(codeSize / uint.sizeof); };

  uint[3] groupCount;
  Descriptor[] descriptors;
  alias shaderModule this;
}

struct Specialization {
  bool alpha = true;
  bool instanced = false;
  bool sdf = false;
  bool ssao = true;
  bool animated = false;
  bool depthPass = false;
  bool wboit = false;
  bool normalMapping = false;
}

struct ShaderDef {
  string path;
  shaderc_shader_kind type;
}

ShaderDef[] RenderShaders = [ShaderDef("data/shaders/vertex.glsl", shaderc_glsl_vertex_shader), 
                             ShaderDef("data/shaders/fragment.glsl", shaderc_glsl_fragment_shader)];
ShaderDef[] PostProcessShaders = [ShaderDef("data/shaders/vertex.post.glsl", shaderc_glsl_vertex_shader), 
                                  ShaderDef("data/shaders/fragment.post.glsl", shaderc_glsl_fragment_shader)];

struct IncluderContext {
  char[][string] includedFiles;
  bool verbose = false;
}

/** Check result of SpirV-Compiler call and print if an error occured */
@nogc void enforceSPIRV(App app, spvc_result err) nothrow { if(err != SPVC_SUCCESS) stop("enforceSPIRV", spvc_context_get_last_error_string(app.context)); }

/** Add a single compiler macro */
void addCompileMacro(ref App app, string name, string value) {
  shaderc_compile_options_add_macro_definition(app.options, toStringz(name), name.length, toStringz(value), value.length);
}

/** Add our default macros (SSAO_KERNEL, MAX_SHADOW_MAPS, MSAA) */
void addShaderMacros(ref App app) {
  app.addCompileMacro("SSAO_KERNEL", to!string(SSAO_KERNEL));
  app.addCompileMacro("MAX_SHADOW_MAPS", to!string(MAX_SHADOW_MAPS));
  if(app.getMSAASamples() != VK_SAMPLE_COUNT_1_BIT) { app.addCompileMacro("MSAA", "1"); }
}

/** Create the ShaderC compiler */
void createCompiler(ref App app) {
  app.compiler = shaderc_compiler_initialize();

  if(!app.compiler) { stop("ShaderC Unavailable", "Failed to initialize shaderc compiler"); }

  app.options = shaderc_compile_options_initialize();
  if(!app.options) { stop("ShaderC Error", "Failed to initialize shaderc compiler options"); }

  shaderc_compile_options_set_target_env(app.options, shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_2);
  shaderc_compile_options_set_target_spirv(app.options, shaderc_spirv_version_1_5);
  shaderc_compile_options_set_generate_debug_info(app.options);
  shaderc_compile_options_set_optimization_level(app.options, shaderc_optimization_level_performance);
  shaderc_compile_options_set_include_callbacks(app.options, &includeResolve, &includeRelease, cast(void*)&app.includeContext);

  app.mainDeletionQueue.add((){
    shaderc_compile_options_release(app.options);
    shaderc_compiler_release(app.compiler);
  });
}

/** Callback to resolve shader file includes using our own I/O */
extern (C) shaderc_include_result* includeResolve(void* userData, const(char)* source, int type, const(char)* reqSource, size_t depth){
  auto context = cast(IncluderContext*)userData;
  char[] code;
  string path;

  if (type == shaderc_include_type_relative) {
    path = format("%s/%s", dirName(fromStringz(reqSource)), fromStringz(source));
    if(context.verbose) SDL_Log(cstr("Shader include: %s", path));
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

/** Callback to release shader files included */
extern (C) void includeRelease(void* userData, shaderc_include_result* result) {
  auto context = cast(IncluderContext*)userData;
  if (result) {
    string path = to!string(result.source_name[0..result.source_name_length]);
    if(context.verbose) SDL_Log(cstr("Shader release: %s", path));
    context.includedFiles.remove(path);
    free(result);
  }
}

/** Compile GLSL source to SPIR-V (no device) */
Shader compileShader(ref App app, const(char)[] source, string path, shaderc_shader_kind type) {
  auto result = shaderc_compile_into_spv(app.compiler, &source[0], source.length, type, toStringz(path), "main", app.options);
  if (shaderc_result_get_compilation_status(result) != shaderc_compilation_status_success) {
    stop("ShaderC Error", toStringz(format("Shader '%s' failed: '%s'", path, fromStringz(shaderc_result_get_error_message(result)))));
  }
  Shader shader = { path: path, stage: convert(type), source: source };
  shader.code = cast(const(uint)*)shaderc_result_get_bytes(result);
  shader.codeSize = shaderc_result_get_length(result);
  app.mainDeletionQueue.add((){ shaderc_result_release(result); });
  return(shader);
}

/** Load GLSL, compile to SpirV, and create the vulkan shaderModule */
Shader createShaderModule(App app, string path, shaderc_shader_kind type = shaderc_glsl_vertex_shader) {
  auto shader = app.compileShader(readFile(toStringz(path), app.verbose), path, type);

  VkShaderModuleCreateInfo createInfo = {
    sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    codeSize: shader.codeSize, pCode: &shader.code[0]
  };

  enforceVK(vkCreateShaderModule(app.device, &createInfo, null, &shader.shaderModule));
  app.nameVulkanObject(shader.shaderModule, cstr("[SHADER] %s", fromStringz(path)), VK_OBJECT_TYPE_SHADER_MODULE);

  shader.info = createShaderStageInfo(convert(type), shader);
  return(shader);
}

/** createShaderStageInfo helper function, since the VkPipelineShaderStageCreateInfo contains a variable "module" */
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

/** Build non-specialized pipeline stage infos from shaders (for shadow, post, and the default scene call) */
VkPipelineShaderStageCreateInfo[] createStageInfo(Shader[] shaders) {
  VkPipelineShaderStageCreateInfo[] info;
  foreach(shader; shaders){ info ~= shader.info; }
  return(info);
}

struct ShaderStage {
  uint[] flags;
  VkSpecializationMapEntry[] mapEntry;
  VkSpecializationInfo* specInfo;
  VkPipelineShaderStageCreateInfo[] info;
}

/** Build pipeline stage infos from shaders, using pipeline Topology and Specialization structure */
ShaderStage createStageInfo(ref App app, Shader[] shaders, VkPrimitiveTopology topology, Specialization s) {
  ShaderStage stage;
  stage.flags = [ topology, s.alpha ? VK_TRUE : VK_FALSE, 
                  s.instanced ? VK_TRUE : VK_FALSE, 
                  LIGHT_GRID[0], LIGHT_GRID[1], LIGHT_GRID[2], 
                  s.sdf ? VK_TRUE : VK_FALSE,
                  s.ssao ? VK_TRUE : VK_FALSE,
                  s.animated ? VK_TRUE : VK_FALSE,
                  s.depthPass ? VK_TRUE : VK_FALSE,
                  s.wboit ? VK_TRUE : VK_FALSE,
                  s.normalMapping ? VK_TRUE : VK_FALSE,
                  cast(uint)app.getMSAASamples()
                  ];
  stage.mapEntry = [
    VkSpecializationMapEntry(0, 0*uint.sizeof, uint.sizeof),    // LINE : fragment
    VkSpecializationMapEntry(1, 1*uint.sizeof, uint.sizeof),    // ALPHA_TEST : fragment
    VkSpecializationMapEntry(2, 2*uint.sizeof, uint.sizeof),    // INSTANCED  : vertex
    VkSpecializationMapEntry(3, 3*uint.sizeof, uint.sizeof),    // GRID_X : compute & fragment
    VkSpecializationMapEntry(4, 4*uint.sizeof, uint.sizeof),    // GRID_Y : compute & fragment
    VkSpecializationMapEntry(5, 5*uint.sizeof, uint.sizeof),    // GRID_Z : compute & fragment
    VkSpecializationMapEntry(6, 6*uint.sizeof, uint.sizeof),    // SDF : fragment
    VkSpecializationMapEntry(7, 7*uint.sizeof, uint.sizeof),    // SSAO : post fragment
    VkSpecializationMapEntry(8, 8*uint.sizeof, uint.sizeof),    // ANIMATED : vertex
    VkSpecializationMapEntry(9, 9*uint.sizeof, uint.sizeof),    // DEPTHPASS : vertex
    VkSpecializationMapEntry(10, 10*uint.sizeof, uint.sizeof),  // WBOIT : fragment
    VkSpecializationMapEntry(11, 11*uint.sizeof, uint.sizeof),  // NORMAL_MAPPED : fragment
    VkSpecializationMapEntry(12, 12*uint.sizeof, uint.sizeof),  // MSAA_SAMPLES
  ];
  stage.specInfo = new VkSpecializationInfo(cast(uint)stage.mapEntry.length, stage.mapEntry.ptr, stage.flags.length * uint.sizeof, stage.flags.ptr);

  foreach(shader; shaders) {
    auto spec = shader.info;
    spec.pSpecializationInfo = stage.specInfo;
    stage.info ~= spec;
  }
  return(stage);
}

/** Load shaders to dst using the specified shader definitions */
void loadShaders(ref App app, ref Shader[] dst, ShaderDef[] defs) {
  foreach(def; defs) { dst ~= app.createShaderModule(def.path, def.type); }

  app.mainDeletionQueue.add(() {
    for(uint i = 0; i < dst.length; i++) { vkDestroyShaderModule(app.device, dst[i], app.allocator); }
  });
}

unittest {
  App app;
  app.createCompiler();

  // Shader compilation: trivial vertex shader compiles to non-empty SPIR-V
  auto sh = app.compileShader(q{
    #version 450
    void main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); }
  }, "test.glsl", shaderc_glsl_vertex_shader);
  assert(sh.nwords > 4, "SPIR-V too small to be valid");
  assert(sh.code[0] == 0x07230203, "missing SPIR-V magic number");   // SPIR-V magic
}
