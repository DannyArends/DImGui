/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import deletion : deAllocate;
import framebuffer : createFramebuffer;
import images : createNamedImage;
import shadow : CASCADE_RADIUS;
import vector : xyz, vSub, dot;

enum uint MIN_SHADOW_DIM = 512;

/** Per-slot shadow state (one per shadow map slot). */
struct ShadowMap {
  ImageBuffer image;                        /// Per-slot shadow map images (layer 0 static, layer 1 static+dynamic composite)
  alias image this;

  bool dirty;                               /// Rebuild layer 0 this frame
  bool pending;                             /// Content changed (e.g. terrain edit): rebuild, drained one/frame via round-robin
  bool hadDynamic;                          /// Dynamic casters were in frustum last frame (recompose once when they leave)
  int owner = -1;                           /// Light index that owns this slot (-1 = none); reassignment forces an immediate rebuild
  Matrix desired;                           /// Desired light-space matrix this frame (pre-commit)
  Matrix committed;                         /// Light-space matrix layer 0 was actually rendered with (committed)

  @property @nogc nothrow bool outOfDate() const { return(desired != committed); }
}

/** Create shadow image+view+framebuffer for slot l at the given square size */
void initShadowMap(ref App app, ref Shadows map, size_t s, uint size) {
  VkImageUsageFlags usage;
  usage |= VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
  usage |= VK_IMAGE_USAGE_SAMPLED_BIT;
  usage |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  usage |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;

  app.createNamedImage(map.slots[s], size, size, map.format, VK_IMAGE_ASPECT_DEPTH_BIT, format("ShadowImage #%d", s),
                       VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL, usage, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 1, 2);
  map.cmd.pass(0).framebuffers[s] = app.createFramebuffer(map.cmd.pass(0), [map.slots[s].view(0)], size, size, "Static Shadow", s);
  map.cmd.pass(1).framebuffers[s] = app.createFramebuffer(map.cmd.pass(1), [map.slots[s].view(1)], size, size, "Dynamic Shadow", s);
}

/** Resize shadow map in slot s to 'size'; defers old resources, re-points the descriptor next safe frame */
void resizeShadowMap(ref App app, size_t s, uint size) {
  if(app.shadows.slots[s].extent.width == size) return;
  app.deAllocate(app.shadows.cmd.pass(0).framebuffers[s]);
  app.deAllocate(app.shadows.cmd.pass(1).framebuffers[s]);
  app.deAllocate(app.shadows.slots[s]);
  app.initShadowMap(app.shadows, s, size);
  app.shadows.shadowDescriptorsDirty[] = true;
}

/** Shadow importance: brighter & nearer scores higher; <=0 means ineligible. */
@nogc float shadowScore(ref Light light, float[3] eye) nothrow {
  if(light.directional || !light.enabled) return -1.0f;
  float[3] d = vSub(light.position.xyz, eye);
  return max(light.intensity[0], light.intensity[1], light.intensity[2]) / (dot(d, d) + 1.0f);
}

/** Directional: size by coverage (near = full res), but cap far cascades to save memory. Point/spot: half. */
@nogc uint shadowResolution(ref Shadows shadows, ref Light light, float radius) nothrow {
  if(!light.directional) return clampPow2(shadows.dimension / 2, MIN_SHADOW_DIM, shadows.dimension);
  uint want = cast(uint)(radius / CASCADE_RADIUS[0] * shadows.dimension + 0.5f); // = 2*radius/texel0
  return clampPow2(want, MIN_SHADOW_DIM, shadows.dimension);   // no per-cascade cap
}

/** Bind slot s to light index owner; a change of owner forces an immediate static rebuild (bypasses round-robin) */
@nogc nothrow void assignSlot(ref Shadows shadows, uint s, int owner) {
  if(shadows.slots[s].owner != owner) { shadows.slots[s].owner = owner; shadows.slots[s].dirty = true; }
}
