/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import std.stdio : writefln;
import std.string : toStringz, fromStringz;

import descriptor : Descriptor, DescriptorLayoutBuilder;
import io : readFile;

struct Shader {
  const(char)* path;
  VkShaderStageFlagBits stage;
  VkShaderModule shaderModule;

  const(uint)* code;
  size_t codeSize;
  @property size_t nwords(){ return(codeSize / uint.sizeof); };

  uint[3] groupCount;
  Descriptor[] descriptors;
  alias shaderModule this;
}

enum spvc_resource_type[const(char)*] types = [
  "Uniform Buffer" : SPVC_RESOURCE_TYPE_UNIFORM_BUFFER,
  "Storage Buffer" : SPVC_RESOURCE_TYPE_STORAGE_BUFFER,
  "Sampled Image" : SPVC_RESOURCE_TYPE_SAMPLED_IMAGE,
  "Storage Image" : SPVC_RESOURCE_TYPE_STORAGE_IMAGE
];

void createReflectionContext(ref App app){
  spvc_result result = spvc_context_create(&app.context);
  if(result != SPVC_SUCCESS) {
    SDL_Log("Failed to create SPIRV-Cross context: %s", spvc_context_get_last_error_string(app.context));
    abort();
  }
  app.mainDeletionQueue.add((){ spvc_context_destroy(app.context); });
}

VkShaderStageFlagBits convert(shaderc_shader_kind kind) {
  switch (kind) {
    case shaderc_vertex_shader: return VK_SHADER_STAGE_VERTEX_BIT; break;
    case shaderc_fragment_shader: return VK_SHADER_STAGE_FRAGMENT_BIT; break;
    case shaderc_compute_shader: return VK_SHADER_STAGE_COMPUTE_BIT; break;
    case shaderc_geometry_shader: return VK_SHADER_STAGE_GEOMETRY_BIT; break;
    default: SDL_Log("Error: ShaderStage not recognized"); return cast(VkShaderStageFlagBits)(0);
  }
}

VkDescriptorType convert(spvc_resource_type type) {
  switch (type) {
    case SPVC_RESOURCE_TYPE_UNIFORM_BUFFER: return VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER; break;
    case SPVC_RESOURCE_TYPE_STORAGE_BUFFER: return VK_DESCRIPTOR_TYPE_STORAGE_BUFFER; break;
    case SPVC_RESOURCE_TYPE_SAMPLED_IMAGE: return VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER; break;
    case SPVC_RESOURCE_TYPE_STORAGE_IMAGE: return VK_DESCRIPTOR_TYPE_STORAGE_IMAGE; break;
    default: SDL_Log("Error: ShaderResource not recognized"); return cast(VkDescriptorType)(0);
  }
}

const(char)* check(const(char)* inp){ return((strcmp(inp, "")==0?"(none)":inp)); }

void reflectShader(ref App app, ref Shader shader) {
  //if(app.verbose) 
  SDL_Log("Reflect: %s", shader.path);
  shader.descriptors = [];
  spvc_parsed_ir ir = null;
  spvc_compiler compiler_glsl = null;
  spvc_resources resources = null;

  app.enforceSPIRV(spvc_context_parse_spirv(app.context, shader.code, shader.nwords, &ir));
  app.enforceSPIRV(spvc_context_create_compiler(app.context, SPVC_BACKEND_GLSL, ir, SPVC_CAPTURE_MODE_TAKE_OWNERSHIP, &compiler_glsl));
  app.enforceSPIRV(spvc_compiler_create_shader_resources(compiler_glsl, &resources));
  app.enforceSPIRV(spvc_compiler_create_shader_resources(compiler_glsl, &resources));

  // Phase 1 Get Entry Points to determine compute groupSizes for x, y, z
  spvc_entry_point* entry_points = null;
  size_t num_entry_points = 0;
  app.enforceSPIRV(spvc_compiler_get_entry_points(compiler_glsl, &entry_points, &num_entry_points));
  for (size_t i = 0; i < num_entry_points; ++i) {
    if(entry_points[i].execution_model == SpvExecutionModelGLCompute) {
      app.enforceSPIRV(spvc_compiler_set_entry_point(compiler_glsl, entry_points[i].name, entry_points[i].execution_model));
      shader.groupCount[0] = spvc_compiler_get_execution_mode_argument_by_index(compiler_glsl, SpvExecutionModeLocalSize, 0);
      shader.groupCount[1] = spvc_compiler_get_execution_mode_argument_by_index(compiler_glsl, SpvExecutionModeLocalSize, 1);
      shader.groupCount[2] = spvc_compiler_get_execution_mode_argument_by_index(compiler_glsl, SpvExecutionModeLocalSize, 2);
      //if(app.verbose) 
      SDL_Log("*Compute Entry: [%d, %d, %d]", shader.groupCount[0], shader.groupCount[1], shader.groupCount[2]);
    }
  }

  // Phase 2 Find ShaderResource sets & bindings
  foreach(type; types.byKey) {
    spvc_reflected_resource* list = null;
    size_t count = 0;
    app.enforceSPIRV(spvc_resources_get_resource_list_for_type(resources, types[type], &list, &count));
    for(size_t i = 0; i < count; ++i) {
      auto descr = Descriptor(convert(types[type]));
      spvc_type_id type_id = list[i].type_id;
      spvc_type_id base_type_id = list[i].base_type_id;
      
      descr.name = spvc_compiler_get_name(compiler_glsl, list[i].id);
      descr.base = spvc_compiler_get_name(compiler_glsl, base_type_id);
      descr.set = spvc_compiler_get_decoration(compiler_glsl, list[i].id, SpvDecorationDescriptorSet);
      descr.binding = spvc_compiler_get_decoration(compiler_glsl, list[i].id, SpvDecorationBinding);
            
      spvc_type resource_type = spvc_compiler_get_type_handle(compiler_glsl, type_id);
      uint array_dimensions = spvc_type_get_num_array_dimensions(resource_type);
      descr.count = 1; // Default
      for(uint x = 0; x < array_dimensions; ++x) {
        if (spvc_type_array_dimension_is_literal(resource_type, x)) {
          descr.count *= spvc_type_get_array_dimension(resource_type, x);
        }
      }
      if(!descr.count) descr.count = cast(uint)app.textures.length;
      shader.descriptors ~= descr;
      //if(app.verbose){
        SDL_Log(" - %d x %s: %s of %s layout(set=%u, binding = %u)", 
                descr.count, type, check(descr.name), check(descr.base), descr.set, descr.binding);
      //}
    }
  }
}

VkDescriptorSetLayout createDescriptorSetLayout(ref App app, Shader[] shaders){
  DescriptorLayoutBuilder builder;
  foreach(shader; shaders) {
    foreach(descriptor; shader.descriptors) {
      builder.add(descriptor.binding, descriptor.count, shader.stage, descriptor.type);
    }
  }
  return(builder.build(app.device));
}

VkDescriptorPoolSize[] createPoolSizes(ref App app, Shader[] shaders){
  VkDescriptorPoolSize[] poolSizes;
  foreach(shader; shaders) {
    foreach(descriptor; shader.descriptors) {
      poolSizes ~= VkDescriptorPoolSize(descriptor.type, descriptor.count * cast(uint)(app.framesInFlight));
    }
  }
  return(poolSizes);
}

void reflectShaders(ref App app, ref Shader[] shaders) {
  for(uint i = 0; i < shaders.length; i++) { app.reflectShader(shaders[i]); }
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
  auto result = shaderc_compile_into_spv(app.compiler, &(cast(char[])source)[0], source.length, type, path, "main", app.options);

  Shader shader = {path, convert(type)};

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
