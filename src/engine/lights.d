/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : setColor;
import icosahedron : refineIcosahedron;
import matrix : orthogonal, radian, perspective, multiply, lookAt;
import ssbo : growSSBO, updateSSBO;
import shadow : resizeShadowMap, addShadowMap;
import textures : mapTextures;
import vector : dot, normalize, vAdd, vSub, negate, vMul, xyz;
import quaternion : xyzw, w;
import matrix : degree, translate;

enum LMode : uint { Global = 0, Lights = 1, LightsAndShadows = 2 }

enum TORCH_HEIGHT = 5.0f;

struct Light {
  Matrix lightSpaceMatrix;
  float[4] position   = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light Position
  float[4] intensity  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light intensity
  float[4] direction  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light direction
  float[4] properties = [0.0f, 0.0f, 0.0f, 1.0f];    /// Light properties [ambient, attenuation, cone half-angle, enabled]
  float[4] cull       = [0.0f,-1.0f, 0.0f, 0.0f];    /// [radius, shadowSlot, reserved, reserved]

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
  Sun  = Light(Matrix.init, [50.0f, 80.0f, 50.0f, 0.0f], [0.7f, 0.6f, 0.45f, 1.0f], [-1.0f, -2.0f, -1.0f, 0.0f], [0.08f, 0.0001f, 89.0f, 1.0f]),
  Fill = Light(Matrix.init, [-30.0f, 40.0f, -30.0f, 0.0f], [0.1f, 0.15f, 0.3f, 1.0f], [1.0f, -1.0f, 1.0f, 0.0f], [0.04f, 0.0f, 90.0f, 0.0f]),
  Red = Light(Matrix.init, [10.0f, 20.0f, 10.0f, 1.0f], [400.0f, 20.0f, 0.0f, 1.0f], [2.0f, -10.0f, -0.5f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Green = Light(Matrix.init, [10.0f, 20.0f, 0.0f, 1.0f], [0.0f, 400.0f, 20.0f, 1.0f], [-3.0f, -9.0f, 3.0f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Blue = Light(Matrix.init, [0.0f, 10.0f, 10.0f, 1.0f], [20.0f, 0.0f, 400.0f, 1.0f], [0.5f, -2.0f, 1.5f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Bright = Light(Matrix.init, [0.0f, 100.0f, 0.0f, 1.0f], [1000.0f,1000.0f, 1000.0f, 1.0f], [0.2f, -1.0f, 0.2f, 0.0f], [0.0f, 0.1f, 90.0f, 0.0f])
};

struct Lighting {
  SSBOList!Light lights;
  uint[] shadowIdle;
  float sunTime = 7.0f;
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
  app.buffers["LightMatrices"].dirty[] = true;
  app.addShadowMap();
}

/** Compute the size of the light radius */
void computeRadius(ref Light l, float cutoff = 0.01f) {
  if (l.directional) { l.cull[0] = float.infinity; return; }
  float maxI = max(l.intensity[0], l.intensity[1], l.intensity[2]);
  l.cull[0]  = sqrt(fmax(0.0f, maxI / cutoff - l.properties[1]));
}

/** Compute lightspace for the provided light */
@nogc void computeLightSpace(ref Camera cam, ref Light light, float[2] size, uint shadowDimension = 4096) nothrow {
  float[3] lightDir = light.direction.xyz.normalize();

  if(!light.directional) {
    Matrix v = lookAt(light.position.xyz, light.position.xyz.vAdd(lightDir), cam.up);
    light.lightSpaceMatrix = perspective(2 * light.properties[2], 1.0f, 0.1f, size[1]).multiply(v);
    return;
  }

  float depth = size[0] + 2.0f * size[1];
  float[3] centre = [cam.lookat[0], size[0] * 0.5f, cam.lookat[2]];

  float texelsPerUnit = cast(float)shadowDimension / (2.0f * size[1]);
  centre[0] = floor(centre[0] * texelsPerUnit) / texelsPerUnit;
  centre[2] = floor(centre[2] * texelsPerUnit) / texelsPerUnit;

  float[3] eye = centre.vSub(lightDir.vMul(depth * 0.5f));
  Matrix lightView = lookAt(eye, centre, cam.up);
  light.lightSpaceMatrix = orthogonal(-size[1], size[1], -size[1], size[1], 0.0f, depth).multiply(lightView);
}

/** Update light geometries for rendering */
void updateLightGeometries(ref App app, float dt, float minsPerSec = 0.3f) {
  app.lights.sunTime = fmod(app.lights.sunTime + (minsPerSec * dt / 60.0f), 24.0f);
  app.updateSun();
  if(!app.showLights) return;
  int l = 1;
  foreach(o; app.objects) {
    if(o.geometry() == "SunGeometry") {
      o.position(app.lights[0].position.xyz);
      o.setColor([1.0f, 0.95f, 0.6f, 1.0f]);
    } else if(o.geometry() == "LightCone" && l < app.lights.length) {
      auto light = app.lights[l++];
      o.instances[0].matrix = Matrix.init;
      o.position(light.position.xyz);
      o.rotate([light.yaw(), 1.0f, light.pitch()]);
      o.setColor(light.intensity);
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
    if(o.geometry() == "LightCone" || o.geometry() == "SunGeometry") o.deAllocate = true;
  }
  if(!app.showLights) return;
  foreach(i, ref light; app.lights) {
    if(i == 0) { // Sun — large icosahedron far away
      app.objects ~= new Icosahedron();
      app.objects[$-1].refineIcosahedron(3);
      app.objects[$-1].geometry = (){ return "SunGeometry"; };
    } else {
      app.objects ~= new Cone();
      app.objects[$-1].geometry = (){ return "LightCone"; };
      app.objects[$-1].rotate([light.yaw(), 1.0f, light.pitch()]);
    }
    app.objects[$-1].castShadow = false;
    app.objects[$-1].position(light.position.xyz);
    app.objects[$-1].setColor(light.intensity);
  }
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
  app.lights[0].intensity = dawnDayBlend(sunNight, sunDawn, sunNoon, t, dawnThreshold);
  app.lights[0].properties[0] = t * ambientScale;
}

/** Transfer the lighting into the SSBO for buffer */
void updateLighting(ref App app, VkCommandBuffer buffer, Descriptor descriptor) {
  foreach(i, ref light; app.lights) {
    light.computeRadius(); 
    app.camera.computeLightSpace(light, app.shadows.bounds, app.shadows.dimension);
  }
  app.updateSSBO!Light(buffer, app.lights, descriptor, app.syncIndex);
}

/** Disco beam */
@nogc pure float beam(float t, float speed, float freq, float phase) nothrow { return abs(sin(t * speed * freq + phase)) * 500.0f; }

/** Shadow importance: brighter & nearer scores higher; <=0 means ineligible. */
@nogc float shadowScore(ref Light light, float[3] eye) nothrow {
  if(light.directional || !light.enabled) return -1.0f;
  float[3] d = vSub(light.position.xyz, eye);
  return max(light.intensity[0], light.intensity[1], light.intensity[2]) / (dot(d, d) + 1.0f);
}

/** Select shadow casters this frame: sun always casts (unbudgeted); point lights compete by importance. */
void computeActiveLighting(ref App app) {
  auto score = new float[app.lights.length];   // >0 eligible point light, <=0 ineligible/taken
  foreach(i, ref light; app.lights) {
    light.computeCone();
    light.cull[1] = (light.directional && light.enabled) ? 1.0f : -1.0f;
    score[i] = light.shadowScore(app.camera.position);
  }

  for(uint picked = 0; picked < app.shadows.budget; picked++) {
    size_t best = size_t.max;
    foreach(i; 0 .. app.lights.length) { if(score[i] > 0.0f && (best == size_t.max || score[i] > score[best])) best = i; }
    if(best == size_t.max) break;
    app.lights[best].cull[1] = 1.0f;
    score[best] = -1.0f;
  }

  if(app.lights.shadowIdle.length != app.lights.length){ app.lights.shadowIdle.length = app.lights.length; }
  foreach(l, ref light; app.lights) {
    bool active = light.cull[1] > 0.0f;
    if(active) {
      app.lights.shadowIdle[l] = 0;
      app.resizeShadowMap(l, light.directional ? 4096u : 1024u);
    } else if(++app.lights.shadowIdle[l] > app.shadows.shrinkDelay) { app.resizeShadowMap(l, 32u); }
  }

  if(app.hasCompute && "ClusterCounter" in app.buffers) {
    uint used = *cast(uint*)app.buffers["ClusterCounter"][0].data;
    if(used > app.clusterCapacity) {
      app.clusterCapacity = used * 2;
      app.growSSBO("ClusterLights", app.clusterCapacity);
    }
  }
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

