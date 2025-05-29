/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import descriptor : Descriptor, createDSPool;
import compute : createStorageImage;
import ssbo : createSSBO;
import uniforms : createUBO;
import shaders : Shader;

enum spvc_resource_type[const(char)*] types = [
  "Uniform Buffer" : SPVC_RESOURCE_TYPE_UNIFORM_BUFFER,
  "Storage Buffer" : SPVC_RESOURCE_TYPE_STORAGE_BUFFER,
  "Sampled Image" : SPVC_RESOURCE_TYPE_SAMPLED_IMAGE,
  "Storage Image" : SPVC_RESOURCE_TYPE_STORAGE_IMAGE
];

void reflectShader(ref App app, ref Shader shader) {
  if(app.verbose) SDL_Log("Reflect: %s", shader.path);
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
      if(app.verbose) SDL_Log("*Compute Entry: [%d, %d, %d]", shader.groupCount[0], shader.groupCount[1], shader.groupCount[2]);
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

      descr.name      = spvc_compiler_get_name(compiler_glsl, list[i].id);
      descr.base      = spvc_compiler_get_name(compiler_glsl, base_type_id);
      descr.set       = spvc_compiler_get_decoration(compiler_glsl, list[i].id, SpvDecorationDescriptorSet);
      descr.binding   = spvc_compiler_get_decoration(compiler_glsl, list[i].id, SpvDecorationBinding);

      spvc_type type_handle = spvc_compiler_get_type_handle(compiler_glsl, type_id);
      spvc_type base_handle = spvc_compiler_get_type_handle(compiler_glsl, base_type_id);

      // UBO: Get the size of the UBO
      if(types[type] == SPVC_RESOURCE_TYPE_UNIFORM_BUFFER) {
        app.enforceSPIRV(spvc_compiler_get_declared_struct_size(compiler_glsl, base_handle, &descr.size));
      }

      // SSBO: Get the size of the SSBO element
      if (types[type] == SPVC_RESOURCE_TYPE_STORAGE_BUFFER) {
          spvc_type_id element_id = spvc_type_get_member_type(type_handle, 0);
          spvc_type element_handle = spvc_compiler_get_type_handle(compiler_glsl, element_id);
          app.enforceSPIRV(spvc_compiler_get_declared_struct_size(compiler_glsl, element_handle, &descr.size));
      }

      // Figure out the descriptor count in a round-about way
      uint array_dimensions = spvc_type_get_num_array_dimensions(type_handle);
      descr.count = 1; // Default
      for(uint x = 0; x < array_dimensions; ++x) {
        if (spvc_type_array_dimension_is_literal(type_handle, x)) {
          descr.count *= spvc_type_get_array_dimension(type_handle, x);
        }
      }
      if(!descr.count) descr.count = cast(uint)app.textures.length;
      shader.descriptors ~= descr;
      if(app.verbose){
        SDL_Log(" - %d x %s: %s of %s layout(set=%u, binding = %u), size: %d", 
                descr.count, type, check(descr.name), check(descr.base), descr.set, descr.binding, descr.size);
      }
    }
  }
}

void reflectShaders(ref App app, ref Shader[] shaders) {
  for(uint i = 0; i < shaders.length; i++) { app.reflectShader(shaders[i]); }
}

void createResources(ref App app, ref Shader[] shaders, const(char)* poolID) {
  SDL_Log("Creating Shader Resources: %d shaders at pool %d", app.shaders.length, poolID);
  app.createDSPool(poolID, shaders);
  for(uint s = 0; s < shaders.length; s++) {
    shaders[s].poolID = poolID;
    for(uint d = 0; d < shaders[s].descriptors.length; d++) {
      if(shaders[s].descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) app.createStorageImage(shaders[s].descriptors[d]);
      if(shaders[s].descriptors[d].type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) app.createSSBO(shaders[s].descriptors[d]);
      if(shaders[s].descriptors[d].type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) app.createUBO(shaders[s].descriptors[d]);
    }
  }
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

void createReflectionContext(ref App app){
  spvc_result result = spvc_context_create(&app.context);
  if(result != SPVC_SUCCESS) {
    SDL_Log("Failed to create SPIRV-Cross context: %s", spvc_context_get_last_error_string(app.context));
    abort();
  }
  app.mainDeletionQueue.add((){ spvc_context_destroy(app.context); });
}

