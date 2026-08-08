/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import devices : getMSAASamples;
import geometry : setColor;
import matrix : orthogonal, radian, perspective, multiply, lookAt;
import ssbo : growSSBO, updateSSBO;
import shadow : assignShadowSlots, NUM_CASCADES, updateShadowSlotMatrices, pickStaticRebuilds;
import vector : dot, cross, normalize, vAdd, vSub, negate, vMul, xyz, magnitude;
import quaternion : aimMatrix, xyzw, w;
import matrix : degree, translate, inverse;

enum LMode : uint { Global = 0, Lights, LightsAndShadows, Normals, nLights, UV, Cascades }

enum TORCH_HEIGHT = 5.0f;
enum uint[4] LIGHT_GRID = [16, 9, 16, 0];
enum uint CLUSTER_COUNT = LIGHT_GRID[0] * LIGHT_GRID[1] * LIGHT_GRID[2];  // 3456
enum uint NIL = 0xFFFFFFFF;

struct Light {
  float[4] position   = [0.0f, 0.0f, 0.0f, 0.0f];    /// Position of the light; w==0: directional, w!=0: point/spot
  float[4] intensity  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light intensity
  float[4] direction  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light direction (must be normalized)
  float[4] properties = [0.0f, 0.0f, 0.0f, 1.0f];    /// Light properties [ambient, attenuation, cone half-angle, enabled]
  float[4] cull       = [0.0f,-1.0f, 0.0f, 0.0f];    /// [radius, shadow map index (-1 = none), cosOuter, cosInner]

  @property @nogc pure void angle(float v) nothrow { properties[2] = v; }
  @property @nogc pure float angle() nothrow { return properties[2]; }
  @property @nogc pure void enabled(bool v) nothrow { properties[3] = v?1.0f:0.0f; }
  @property @nogc pure bool enabled() nothrow { return(properties.w == 1.0f); }
  @property @nogc pure bool directional() nothrow { return(position.w == 0.0f); }
  @property @nogc pure float radius() nothrow { return cull[0]; }
  @property @nogc pure float pitch() nothrow { return(degree(asin(-direction.xyz.normalize()[1]))); }
  @property @nogc pure float yaw() nothrow { return(degree(atan2(direction.xyz.normalize()[0], direction.xyz.normalize()[2]))); }
  @nogc pure void computeCone() nothrow {
    cull[2] = cos(properties[2] * cast(float)(PI / 180.0)); // cosOuter
    cull[3] = cos(properties[2] * 0.5f * cast(float)(PI / 180.0)); // cosInner
  }
}

enum Lights : Light {
  Sun  = Light([50.0f, 80.0f, 50.0f, 0.0f], [0.7f, 0.6f, 0.45f, 1.0f], [-1.0f, -2.0f, -1.0f, 0.0f], [0.08f, 0.0001f, 89.0f, 1.0f]),
  Fill = Light([-30.0f, 40.0f, -30.0f, 0.0f], [0.1f, 0.15f, 0.3f, 1.0f], [1.0f, -1.0f, 1.0f, 0.0f], [0.04f, 0.0f, 90.0f, 0.0f]),
  Red = Light([10.0f, 20.0f, 10.0f, 1.0f], [200.0f, 20.0f, 0.0f, 1.0f], [2.0f, -10.0f, -0.5f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Green = Light([10.0f, 20.0f, 0.0f, 1.0f], [0.0f, 200.0f, 20.0f, 1.0f], [-3.0f, -9.0f, 3.0f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Blue = Light([0.0f, 10.0f, 10.0f, 1.0f], [20.0f, 0.0f, 200.0f, 1.0f], [0.5f, -2.0f, 1.5f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Bright = Light([0.0f, 100.0f, 0.0f, 1.0f], [1000.0f,1000.0f, 1000.0f, 1.0f], [0.2f, -1.0f, 0.2f, 0.0f], [0.0f, 0.1f, 90.0f, 0.0f])
};

struct Lighting {
  SSBOList!Light lights;
  float[] scoreBuf;
  bool staticDirty = false;
  float sunTime = 13.0f;
  float discoTime = 0.0f;
  float sunBearing = 135.0f;
  alias lights this;
}

// TODO: torches are downward SPOT lights, true omni shadows need cube maps (engine uses one 2D map per light)
Light torchLight(float[3] pos, float[4] color) {
  Light l;
  l.position   = [pos[0], pos[1] + TORCH_HEIGHT, pos[2], 1.0f];
  l.intensity  = [color[0] * 10.0f, color[1] * 10.0f, color[2] * 10.0f, 1.0f];
  l.direction  = [0.0f, -1.0f, 0.0f, 0.0f];
  l.properties = [0.0f, 0.01f, 35.0f, 1.0f];
  l.computeRadius();
  return l;
}

void addLight(ref App app, Light light) {
  app.lights ~= light;
  if(app.lights.scoreBuf.length != app.lights.length) app.lights.scoreBuf.length = app.lights.length;
  app.buffers["LightMatrices"].invalidate();
}

/** Swap-remove to keep Light packed/GPU-friendly */
size_t removeLight(ref App app, size_t index) {
  size_t moved = app.lights.items.removeAt(index);
  app.lights.scoreBuf.length = app.lights.length;
  app.buffers["LightMatrices"].invalidate();
  size_t last = (moved != size_t.max) ? moved : index;
  foreach(ref slot; app.shadows.slots) {
    if(slot.owner == cast(int)index) { slot.owner = -1; }else if(slot.owner == cast(int)last) { slot.owner = cast(int)index; }
  }
  return(moved);
}

/** Point/spot cull radius: distance where intensity attenuates to cutoff */
void computeRadius(ref Light l, float cutoff = 0.05f) {
  if (l.directional) { l.cull[0] = float.infinity; return; }
  float maxI = max(l.intensity[0], l.intensity[1], l.intensity[2]);
  l.cull[0]  = sqrt(fmax(0.0f, maxI / cutoff - l.properties[1]));
}

/** Cascade split distances over [near,far], blended uniform<->log by CASCADE_LAMBDA (0=uniform, 1=log). */
@nogc pure float[NUM_CASCADES + 1] cascadeSplitDistances(float near, float far, float lambda) nothrow {
  float[NUM_CASCADES + 1] d;
  d[0] = near;
  foreach(i; 1 .. NUM_CASCADES + 1) {
    float p = cast(float)i / NUM_CASCADES;
    float uni = near + (far - near) * p;
    float log = near * pow(far / near, p);
    d[i] = uni + (log - uni) * lambda;
  }
  return d;
}

/** World-space bounding sphere of the view-frustum slice [dn,df]; centre on the view axis, radius covers all 8 corners. */
@nogc float[4] frustumSliceSphere(ref Camera cam, float dn, float df) nothrow {
  Matrix invVP = cam.proj.multiply(cam.view).inverse();
  float[3] centre = [0,0,0]; float[3][8] corner; uint k;
  foreach(z; [dn, df]) foreach(y; [-1.0f, 1.0f]) foreach(x; [-1.0f, 1.0f]) {
    // NDC corner at this slice depth; unproject to world. Depth as NDC z = (df/(df-near))*(1 - near/z)... use clip-space directly:
    float[4] ndc = [x, y, 0.0f, 1.0f];
    // place the corner at world distance z along the view by unprojecting near&far then lerping:
    float[4] wn = invVP.multiply([x, y, 0.0f, 1.0f]);   // near plane point (NDC z=0)
    float[4] wf = invVP.multiply([x, y, 1.0f, 1.0f]);   // far plane point  (NDC z=1)
    float[3] pn = [wn[0]/wn[3], wn[1]/wn[3], wn[2]/wn[3]];
    float[3] pf = [wf[0]/wf[3], wf[1]/wf[3], wf[2]/wf[3]];
    float tn = (z - cam.nearfar[0]) / (cam.nearfar[1] - cam.nearfar[0]);   // fraction along the ray for distance z
    corner[k] = pn.vAdd(pf.vSub(pn).vMul(tn));
    centre = centre.vAdd(corner[k]); k++;
  }
  centre = centre.vMul(1.0f / 8.0f);
  float r = 0.0f; foreach(i; 0 .. 8) { float dsq = corner[i].vSub(centre).magnitude(); if(dsq > r) r = dsq; }
  return [centre[0], centre[1], centre[2], r];
}

/** Compute lightspace for the provided light. Builds a cascade's light-space matrix: ortho box centred on lookat */
@nogc Matrix computeLightSpace(ref Camera cam, ref Light light, float[2] size, uint shadowDimension, float[4] sphere = [0,0,0,0]) nothrow {
  float[3] lightDir = light.direction.xyz.normalize();
  light.direction = lightDir.xyzw(light.direction[3]); // Store normalized dir, GLSL illuminate() can skip a per-pixel normalize

  if(!light.directional) {
    Matrix v = lookAt(light.position.xyz, light.position.xyz.vAdd(lightDir), cam.up);
    return perspective(2 * light.properties[2], 1.0f, 0.1f, size[1]).multiply(v);
  }

  // CSM: cascades stash their half-extent in properties[2] (unused for directional). 0 => full bounds.
  float radius = (sphere[3] > 0.0f) ? sphere[3] : size[1];
  float depth = size[0] + 2.0f * radius;
  float[3] centre = (sphere[3] > 0.0f) ? [sphere[0], sphere[1], sphere[2]] : [cam.lookat[0], size[0] * 0.5f, cam.lookat[2]];
  float[3] s = lightDir.cross(cam.up).normalize();
  float[3] v = s.cross(lightDir).normalize();
  float texelSize = 2.0f * radius / cast(float)shadowDimension;
  float du = centre.dot(s), dv = centre.dot(v);
  centre = centre.vAdd(s.vMul(floor(du / texelSize) * texelSize - du)).vAdd(v.vMul(floor(dv / texelSize) * texelSize - dv));
  // pull eye a full radius toward light so casters above the sphere aren't near-clipped
  float[3] eye = centre.vSub(lightDir.vMul(depth * 0.5f + radius));
  Matrix lightView = lookAt(eye, centre, cam.up);
  return orthogonal(-radius, radius, -radius, radius, 0.0f, depth + 2.0f * radius).multiply(lightView);
}

/** Update light geometries for rendering */
void updateLightGeometries(ref App app, float dt, float minsPerSec = 0.3f) {
  app.lights.sunTime = fmod(app.lights.sunTime + (minsPerSec * dt / 60.0f), 24.0f);
  if(!app.showLights) return;
  foreach(o; app.objects) {
    if(o.geometry() == "SunGeometry") {
      o.position(app.lights[0].position.xyz);
      o.setColor([1.0f, 0.95f, 0.6f, 1.0f]);
    } else if(o.geometry() == "LightCones") {
      o.instances.reset();
      foreach(i, ref light; app.lights) {
        if(i == 0) continue;
        o.instances ~= DrawInstance(aimMatrix(light.position.xyz, light.direction.xyz.negate), -1, light.intensity.xyz.normalize.xyzw);
      }
      o.syncInstances();
    }
  }
}

/** Compute Azimuth of the sun */
@nogc pure float sunAzimuth(float sunTime, float bearing = 0.0f) nothrow { return (sunTime / 24.0f) * 360.0f + bearing;}

/** Compute Elevation of the sun */
@nogc pure float sunElevation(float sunTime, float sunriseH = 5.0f, float sunsetH = 23.0f) nothrow {
  float dayFrac = (sunTime - sunriseH) / (sunsetH - sunriseH);
  return (dayFrac >= 0.0f && dayFrac <= 1.0f) ? sin(dayFrac * PI) * 60.0f : -10.0f;
}

/** Helper to update sun to time */
void updateSun(ref App app) { app.updateSun(sunAzimuth(app.lights.sunTime, app.lights.sunBearing), sunElevation(app.lights.sunTime)); }

/** Toggle the rendering of Lights */
void toggleLightGeometries(ref App app) {
  foreach(o; app.objects) {
    if(o.geometry() == "LightCones" || o.geometry() == "SunGeometry") o.deAllocate = true;
  }
  if(!app.showLights) return;

  auto sun = new Sphere();
  sun.geometry = (){ return "SunGeometry"; };
  sun.castShadow = false;
  app.objects ~= sun;

  auto cones = new Cone();
  cones.initInstanced((){ return "LightCones"; });   // instancedMesh = true, instances = []
  cones.castShadow = false;
  app.objects ~= cones;
}

/** Color lerp */
@nogc pure float[4] lerpColor(float[4] a, float[4] b, float t) nothrow { return vAdd(a.xyz, vMul(vSub(b.xyz, a.xyz), t)).xyzw; }

/** Blending dawn & day */
@nogc pure float[4] dawnDayBlend(float[4] night, float[4] dawn, float[4] day, float t, float dawnThreshold = 0.55f) nothrow {
  if(t < dawnThreshold) { return lerpColor(night, dawn, t / dawnThreshold); }
  return lerpColor(dawn, day, (t - dawnThreshold) / (1.0f - dawnThreshold));
}

/** Update time of day / sun */
void updateSun(ref App app, float azimuth, float elevation, float dawnThreshold = 0.55f, float ambientScale = 0.1f, float sunDistance = 200.0f,
               float[4] skyNight = Colors.skyNight, float[4] skyDawn = Colors.skyDawn, float[4] skyDay = Colors.skyDay,
               float[4] sunNight = Colors.sunNight, float[4] sunDawn = Colors.sunDawn, float[4] sunNoon = Colors.sunNoon) {
  float azRad = radian(azimuth);
  float elRad = radian(elevation);
  float[3] dir = [-cos(elRad) * sin(azRad), -sin(elRad), -cos(elRad) * cos(azRad)];

  app.lights[0].direction = dir.xyzw(0.0f);
  app.lights[0].position = dir.negate().vMul(sunDistance).xyzw(0.0f);

  float t = clamp(sin(elRad), 0.0f, 1.0f);

  app.clearValue[0].color = VkClearColorValue(dawnDayBlend(skyNight, skyDawn, skyDay, t, dawnThreshold));
  if((app.getMSAASamples() == VK_SAMPLE_COUNT_1_BIT)) {
    app.clearValue[1].color = app.clearValue[0].color;   // MSAA 1x: SP0 renders into attachment 1, which clears to the sky color
  }
  app.lights[0].intensity = dawnDayBlend(sunNight, sunDawn, sunNoon, t, dawnThreshold);
  app.lights[0].properties[0] = t * ambientScale;
}

/** Disco beam */
@nogc pure float beam(float t, float speed, float freq, float phase) nothrow { return abs(sin(t * speed * freq + phase)) * 500.0f; }

/** Grow the cluster-light SSBO if last frame overflowed it. */
void growClusterBufferIfNeeded(ref App app) {
  if(app.hasCompute && "ClusterCounter" in app.buffers) {
    uint used = *cast(uint*)app.buffers["ClusterCounter"][app.syncIndex].data;
    if(used > app.clusterCapacity) { app.clusterCapacity = used * 2; app.growSSBO("ClusterLights", app.clusterCapacity); }
  }
}

/** Assign shadow slots, update matrices, flag static rebuilds, and finalise the light SSBO for this frame. */
void computeActiveLighting(ref App app) {
  if(app.lights.staticDirty) {
    foreach(ref slot; app.shadows.slots) { slot.dirty = true; }
    app.lights.staticDirty = false;
  }
  app.assignShadowSlots();
  app.updateShadowSlotMatrices();
  app.shadows.pickStaticRebuilds();
  foreach(ref light; app.lights) light.direction = light.direction.xyz.normalize().xyzw(light.direction[3]);
  app.buffers["LightMatrices"].invalidate();
  app.growClusterBufferIfNeeded();
}

/** Disco mode 🕺 🪩 💃 */
void updateDisco(ref App app, float dt) {
  if (!app.disco || app.lights.length < 3) return;
  auto t = app.lights.discoTime += dt;
  foreach (i; 1 .. app.lights.length) {
    if(!app.lights[i].enabled) continue;
    float fi = cast(float)i;
    float speed  = 0.5f + fmod(fi * 0.61803f, 1.0f) * 1.8f;
    float radius = 12.0f + fmod(fi * 0.31415f, 1.0f) * 22.0f;
    float height = 12.0f + fmod(fi * 0.71828f, 1.0f) * 25.0f;
    float phase  = fi * 2.39996f;
    float a = app.lights.discoTime * speed + phase;

    float[3] orbit = [radius * cos(a), height, radius * sin(a)];
    float[3] wobble = [sin(t * 3.1f + phase) * 0.3f, 0.0f, cos(t * 2.7f + phase) * 0.3f];
    float[3] dir = orbit.negate().vMul(1.0f / radius).vAdd(wobble);
    dir[1] = -1.5f;

    app.lights[i].position = orbit.xyzw(1.0f);
    app.lights[i].direction = dir.xyzw(0.0f);
    app.lights[i].intensity = [beam(t, speed, 4.0f, phase), beam(t, speed, 3.0f, phase), beam(t, speed, 5.0f, phase + 1.0f)].xyzw;
    app.lights[i].properties[2] = 25.0f + sin(t * speed) * 10.0f;
  }
}

