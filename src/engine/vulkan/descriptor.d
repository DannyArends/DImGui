/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import descriptorupdate : updateDescriptorSet;
import validation : nameVulkanObject;

enum DescriptorTarget { None, Textures, Shadow, HDR, Compute, Depth, SSAO, WBOITAccum, WBOITReveal }

struct Descriptor {
  VkDescriptorType type;    /// Type of Descriptor
  DescriptorTarget target;  /// Image target (resolved at load time, avoids per-frame string dispatch)

  string name;              /// Name
  string base;              /// Base / Struct Name
  size_t bytes;             /// Size  of the structure

  uint set;                 /// DescriptorSet
  uint binding;             /// DescriptorSet Binding
  uint count;               /// Descriptor count
}

struct DescriptorProvider {
  void delegate(ref App, ref Descriptor) create; /// once, at resource creation
  void delegate(ref App, ref Descriptor, VkCommandBuffer) onFrame; /// per pass per frame (null = none)
  size_t lastFrame = size_t.max;
}

struct DescriptorLayoutBuilder {
  VkDescriptorSetLayoutBinding[] bindings;

  void add(uint binding, uint count, VkShaderStageFlags shaderStage, VkDescriptorType type){
    foreach(ref b; bindings) { // Check if the binding already exists in another stage
      if(b.binding == binding) {
        b.stageFlags |= shaderStage;  // If yes, add the stageflag to the binding
        return;
      }
    }
    VkDescriptorSetLayoutBinding layout = { binding: binding, stageFlags: shaderStage, descriptorCount: count, descriptorType: type };
    bindings ~= layout;
  }

  void clear(){ bindings = []; }

  VkDescriptorSetLayout build(VkDevice device, VkDescriptorSetLayoutCreateFlags flags = 0, void* pNext = null){
    VkDescriptorBindingFlags[] bindingFlags;
    bindingFlags.length = bindings.length;
    foreach(i, ref b; bindings) { 
      bindingFlags[i] = (b.descriptorCount > 1) ? VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT : 0;
    }

    VkDescriptorSetLayoutBindingFlagsCreateInfo bindingFlagsInfo = {
      sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
      bindingCount: cast(uint)bindingFlags.length,
      pBindingFlags: &bindingFlags[0]
    };

    VkDescriptorSetLayoutCreateInfo info = {
      sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      pBindings: &bindings[0],
      bindingCount: cast(uint)bindings.length,
      flags: flags,
      pNext: &bindingFlagsInfo
    };

    VkDescriptorSetLayout set;
    enforceVK(vkCreateDescriptorSetLayout(device, &info, null, &set));
    return set;
  }
};

VkDescriptorSetLayout createDescriptorSetLayout(ref App app, Shader[] shaders) {
  DescriptorLayoutBuilder builder;
  foreach(shader; shaders) {
    foreach(descriptor; shader.descriptors) {
      if(app.verbose) SDL_Log(cstr("[%d] cnt: %d = %s %s", descriptor.binding, descriptor.count, shader.stage, descriptor.type));
      builder.add(descriptor.binding, descriptor.count, shader.stage, descriptor.type);
    }
  }
  auto layout = builder.build(app.device);
  return(layout);
}

VkDescriptorPoolSize[] createPoolSizes(ref App app, Shader[] shaders) {
  VkDescriptorPoolSize[] poolSizes;
  foreach(shader; shaders) {
    foreach(descriptor; shader.descriptors) {
      poolSizes ~= VkDescriptorPoolSize(descriptor.type, descriptor.count * cast(uint)(app.framesInFlight));
    }
  }
  return(poolSizes);
}

void createDSPool(ref App app, string poolID, VkDescriptorPoolSize[] poolSizes, uint maxSets = 1024) {
  if(app.verbose) SDL_Log("Creating DescriptorPool[%s]", toStringz(poolID));
  app.pools[poolID] = VkDescriptorPool();
  VkDescriptorPoolCreateInfo createPool = {
    sType : VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    flags : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    maxSets : maxSets, /// Allocate maxSets (Default: 1024 Sets)
    poolSizeCount : cast(uint)poolSizes.length,
    pPoolSizes : &poolSizes[0]
  };
  enforceVK(vkCreateDescriptorPool(app.device, &createPool, app.allocator, &app.pools[poolID]));
  app.nameVulkanObject(app.pools[poolID], toStringz("[POOL] " ~ fromStringz(poolID)), VK_OBJECT_TYPE_DESCRIPTOR_POOL);
  if(app.verbose) SDL_Log("Created %s DescriptorPool: %p", toStringz(poolID), app.pools[poolID]);
}

/** ImGui DescriptorPool (Images) */
void createImGuiDescriptorPool(ref App app) {
  VkDescriptorPoolSize[] poolSizes = [{
    type : VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount : 1000 ///IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE
  }];
  app.createDSPool(Stage.IMGUI, poolSizes);
  app.mainDeletionQueue.add((){ vkDestroyDescriptorPool(app.device, app.pools[Stage.IMGUI], app.allocator); });
}

/** ImGui DescriptorSetLayout (1000 * Combined Image Samplers) */
void createImGuiDescriptorSetLayout(ref App app) {
  if(app.verbose) SDL_Log("Creating ImGui DescriptorSetLayout");
  DescriptorLayoutBuilder builder;
  builder.add(0, 1, VK_SHADER_STAGE_FRAGMENT_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
  app.layouts[Stage.IMGUI] = builder.build(app.device);
  app.nameVulkanObject(app.layouts[Stage.IMGUI], cstr("[DESCRIPTOR] Layout %s", Stage.IMGUI), VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT);

  app.mainDeletionQueue.add((){ vkDestroyDescriptorSetLayout(app.device, app.layouts[Stage.IMGUI], app.allocator); });
}

/** Create a descriptor pool based on the shaders provided */
void createDSPool(ref App app, string poolID, Shader[] shaders) {
  uint nShaders = 1;
  if(poolID == Stage.COMPUTE){ nShaders = cast(uint)shaders.length; }
  if(app.verbose) SDL_Log("createDSPool by shader: %s, with %d shader size", toStringz(poolID), nShaders);
  VkDescriptorPoolSize[] poolSizes = app.createPoolSizes(shaders);
  app.createDSPool(poolID, poolSizes, nShaders * app.framesInFlight);
  app.swapDeletionQueue.add((){ 
    vkDestroyDescriptorPool(app.device, app.pools[poolID], app.allocator); 
  });
}

/** Allocate a Descriptor Set */
VkDescriptorSet[] createDescriptorSet(VkDevice device, VkDescriptorPool pool, VkDescriptorSetLayout layout, uint size){
  VkDescriptorSetLayout[] layouts;
  VkDescriptorSet[] set;
  layouts.length = set.length = size;
  layouts[] = layout;

  VkDescriptorSetAllocateInfo allocInfo = {
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    descriptorPool: pool,
    descriptorSetCount: size,
    pSetLayouts: &layouts[0]
  };
  enforceVK(vkAllocateDescriptorSets(device, &allocInfo, &set[0]));
  return(set);
}

/** Create our DescriptorSet (UBO and Combined image sampler) */
void createDescriptors(ref App app, Shader[] shaders, Stage stage = Stage.RENDER) {
  if(app.verbose) SDL_Log("createDescriptors: %d pipeline", stage);
  app.layouts[stage] = app.createDescriptorSetLayout(shaders);
  app.nameVulkanObject(app.layouts[stage], cstr("[DESCRIPTORLAYOUT] %s", stage), VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT);
  app.sets[stage] = createDescriptorSet(app.device, app.pools[stage], app.layouts[stage],  app.framesInFlight);

  for (uint i = 0; i < app.framesInFlight; i++) {
    app.updateDescriptorSet(shaders, app.sets[stage], i);
    app.nameVulkanObject(app.sets[stage][i], cstr("[DESCRIPTORSET] %s #%d", stage, i), VK_OBJECT_TYPE_DESCRIPTOR_SET);
  }

  app.swapDeletionQueue.add((){ 
    vkDestroyDescriptorSetLayout(app.device, app.layouts[stage], app.allocator); 
  });
}

unittest {
  import commandpool : createCommandPool, createCommandBuffer;
  import devices : createLogicalDevice;
  import instance : createInstance;
  import reflection : createReflectionContext, reflectShader;
  import shaders : createCompiler, compileShader;

  App app;
  app.enableValidation = false;
  app.createInstance();
  app.createLogicalDevice();
  if(app.device is null) return;                 // no device on this runner
  scope(exit) { vmaDestroyAllocator(app.vma); vkDestroyDevice(app.device, app.allocator); vkDestroyInstance(app.instance, app.allocator); }

  // --- End-to-end: GLSL -> SPIR-V -> reflect -> build a real VkDescriptorSetLayout ---
  app.createCompiler();
  app.createReflectionContext();
  auto vs = app.compileShader(q{
    #version 450
    layout(set = 0, binding = 0) uniform UBO { mat4 mvp; } ubo;
    void main() { gl_Position = ubo.mvp * vec4(0.0); }
  }, "layout_test.glsl", shaderc_glsl_vertex_shader);
  vs.stage = VK_SHADER_STAGE_VERTEX_BIT;
  app.reflectShader(vs);
  assert(vs.descriptors.length == 1, "expected one reflected descriptor");

  auto layout = app.createDescriptorSetLayout([vs]);
  assert(layout != VK_NULL_HANDLE, "createDescriptorSetLayout returned null");
  vkDestroyDescriptorSetLayout(app.device, layout, app.allocator);

  // --- DescriptorLayoutBuilder builds a layout from hand-specified bindings ---
  DescriptorLayoutBuilder builder;
  builder.add(0, 1, VK_SHADER_STAGE_VERTEX_BIT,   VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
  builder.add(1, 4, VK_SHADER_STAGE_FRAGMENT_BIT, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
  auto l2 = builder.build(app.device);
  assert(l2 != VK_NULL_HANDLE, "builder.build returned null");
  vkDestroyDescriptorSetLayout(app.device, l2, app.allocator);

  // --- add() merges stage flags when the same binding appears twice ---
  DescriptorLayoutBuilder merged;
  merged.add(0, 1, VK_SHADER_STAGE_VERTEX_BIT,   VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
  merged.add(0, 1, VK_SHADER_STAGE_FRAGMENT_BIT, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
  assert(merged.bindings.length == 1, "duplicate binding not merged");
  assert(merged.bindings[0].stageFlags == (VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT), "stage flags not OR-merged");

  // --- Command pool + buffer allocation on the graphics queue family ---
  auto pool = app.createCommandPool(app.queues.graphics.family);
  assert(pool != VK_NULL_HANDLE, "createCommandPool returned null");
  auto cmds = app.createCommandBuffer(pool, 2);
  assert(cmds.length == 2 && cmds[0] != VK_NULL_HANDLE, "command buffer allocation failed");
  vkDestroyCommandPool(app.device, pool, app.allocator);
}
