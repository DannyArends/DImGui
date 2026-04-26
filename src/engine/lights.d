/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry;
import icosahedron : refineIcosahedron;
import matrix : orthogonal, radian, perspective, multiply, lookAt;
import ssbo : updateSSBO;
import textures : mapTextures;
import vector : normalize, vAdd, vSub, negate, vMul, xyz;
import quaternion : xyzw, w;
import matrix : degree, translate;

enum LMode : uint { Global = 0, Lights = 1, LightsAndShadows = 2 }

struct Light {
  Matrix lightSpaceMatrix;
  float[4] position   = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light Position
  float[4] intensity  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light intensity
  float[4] direction  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light direction
  float[4] properties = [0.0f, 0.0f, 0.0f, 1.0f];    /// Light properties [ambient, attenuation, angle, enabled]

  @property @nogc pure void angle(float v) nothrow { properties[2] = v; }
  @property @nogc pure float angle() nothrow { return properties[2]; }
  @property @nogc pure void enabled(bool v) nothrow { properties[3] = v?1.0f:0.0f; }
  @property @nogc pure bool enabled() nothrow { return(properties.w == 1.0f); }
  @property @nogc pure bool directional() nothrow { return(position.w == 0.0f); }
  @property @nogc pure float pitch() nothrow { return(degree(asin(-direction.xyz.normalize()[1]))); }
  @property @nogc pure float yaw() nothrow { return(degree(atan2(direction.xyz.normalize()[0], direction.xyz.normalize()[2]))); }
}

enum Lights : Light {
  Sun  = Light(Matrix.init, [50.0f, 80.0f, 50.0f, 0.0f], [0.7f, 0.6f, 0.45f, 1.0f], [-1.0f, -2.0f, -1.0f, 0.0f], [0.08f, 0.0001f, 89.0f, 1.0f]),
  Fill = Light(Matrix.init, [-30.0f, 40.0f, -30.0f, 0.0f], [0.1f, 0.15f, 0.3f, 1.0f], [1.0f, -1.0f, 1.0f, 0.0f], [0.04f, 0.0f, 90.0f, 0.0f]),
  Red = Light(Matrix.init, [10.0f, 20.0f, 10.0f, 1.0f], [400.0f, 20.0f, 0.0f, 1.0f], [2.0f, -10.0f, -0.5f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Green  = Light(Matrix.init, [10.0f, 20.0f, 0.0f, 1.0f], [0.0f, 400.0f, 20.0f, 1.0f], [-3.0f, -9.0f, 3.0f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Blue   = Light(Matrix.init, [0.0f, 10.0f, 10.0f, 1.0f], [20.0f, 0.0f, 400.0f, 1.0f], [0.5f, -2.0f, 1.5f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Bright = Light(Matrix.init, [0.0f, 100.0f, 0.0f, 1.0f], [1000.0f,1000.0f, 1000.0f, 1.0f], [0.2f, -1.0f, 0.2f, 0.0f], [0.0f, 0.1f, 90.0f, 0.0f])
};

struct Lighting {
  Light[] lights;
  float sunTime = 8.0f;
  float sunBearing = 135.0f;
  alias lights this;
}

/** Compute lightspace for the provided light */
@nogc void computeLightSpace(const World world, ref Light light, float nearPlane = 0.1f, float farPlane = 500.0f) nothrow {
  float[3] lightDir = light.direction.xyz.normalize();
  float[3] upVector = [0.0f, 1.0f, 0.0f];
  float[3] worldCenter = [0.0f, world.height * 0.5f, 0.0f];
  float[3] lightEye = worldCenter.vSub(lightDir.vMul(farPlane * 0.5f));

  Matrix lightView = lookAt(lightEye, worldCenter, upVector);
  Matrix lightProjection = light.directional
    ? orthogonal(-world.radius, world.radius, -world.radius, world.radius, -world.height, farPlane)
    : perspective(2 * light.properties[2], 1.0f, nearPlane, farPlane);

  light.lightSpaceMatrix = lightProjection.multiply(lightView);
}

/** Update light geometries for rendering */
void updateLightGeometries(ref App app, float minsPerTick = 2.0f) {
  app.lights.sunTime = fmod(app.lights.sunTime + (minsPerTick / 60.0f), 24.0f);
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
@nogc pure float sunElevation(float sunTime, float sunriseH = 4.0f, float sunsetH = 22.0f) nothrow {
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
void updateSun(ref App app, float azimuth, float elevation, float dawnThreshold = 0.55f, float ambientScale = 0.1f, float sunDistance = 100.0f,
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

  app.buffers["LightMatrices"].dirty[] = true;
  app.shadows.dirty = true;
}

/** Transfer the lighting into the SSBO for buffer */
void updateLighting(ref App app, VkCommandBuffer buffer, Descriptor descriptor) {
  if(!app.buffers[descriptor.base].dirty[app.syncIndex]) return;
  foreach(i, ref light; app.lights) { app.world.computeLightSpace(light); }
  app.updateSSBO!Light(buffer, app.lights, descriptor, app.syncIndex);
}

/** Disco beam */
@nogc pure float beam(float t, float speed, float freq, float phase) nothrow { return abs(sin(t * speed * freq + phase)) * 500.0f; }

/** Disco mode 🕺 🪩 💃 */
void updateDisco(ref App app) {
  if (!app.disco || app.lights.length < 3) return;
  float t = (SDL_GetTicks() - app.time[STARTUP]) / 1000.0f;
  foreach (i; 1 .. app.lights.length) {
    if(!app.lights[i].enabled) continue;
    float fi = cast(float)i;
    float speed  = 0.5f + fmod(fi * 0.61803f, 1.0f) * 1.8f;
    float radius = 12.0f + fmod(fi * 0.31415f, 1.0f) * 22.0f;
    float height = 12.0f + fmod(fi * 0.71828f, 1.0f) * 25.0f;
    float phase  = fi * 2.39996f;
    float a = t * speed + phase;

    float[3] orbit = [radius * cos(a), height, radius * sin(a)];
    float[3] wobble = [sin(t * 3.1f + phase) * 0.3f, 0.0f, cos(t * 2.7f + phase) * 0.3f];
    float[3] dir = orbit.negate().vMul(1.0f / radius).vAdd(wobble);
    dir[1] = -1.5f;

    app.lights[i].position = orbit.xyzw(1.0f);
    app.lights[i].direction = dir.xyzw(0.0f);
    app.lights[i].intensity = [beam(t, speed, 4.0f, phase), beam(t, speed, 3.0f, phase), beam(t, speed, 5.0f, phase + 1.0f)].xyzw;
    app.lights[i].properties[2] = 25.0f + sin(t * speed) * 10.0f;
  }
  app.buffers["LightMatrices"].dirty[] = true;
  app.shadows.dirty = true;
}
