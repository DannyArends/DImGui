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
import matrix : degree, translate;

enum LMode : uint { Global = 0, Lights = 1, LightsAndShadows = 2 }

struct Light {
  Matrix lightSpaceMatrix;
  float[4] position   = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light Position
  float[4] intensity  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light intensity
  float[4] direction  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light direction
  float[4] properties = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light properties [ambient, attenuation, angle, unused]
  
  float pitch(){ 
    auto d = [direction[0], direction[1], direction[2]].normalize();
    return degree(asin(-d[1])); 
  }
  float yaw(){ 
    auto d = [direction[0], direction[1], direction[2]].normalize();
    return degree(atan2(d[0], d[2])); 
  }
}

enum Lights : Light {
  Sun  = Light(Matrix.init, [50.0f, 80.0f, 50.0f, 0.0f], [0.7f, 0.6f, 0.45f, 1.0f], [-1.0f, -2.0f, -1.0f, 0.0f], [0.08f, 0.0001f, 89.0f, 0.0f]),
  Fill = Light(Matrix.init, [-30.0f, 40.0f, -30.0f, 0.0f], [0.1f, 0.15f, 0.3f, 1.0f], [1.0f, -1.0f, 1.0f, 0.0f], [0.04f, 0.0f, 90.0f, 0.0f]),
  Red    = Light(Matrix.init, [ 10.0f, 20.0f, 10.0f, 1.0f], [ 400.0f,  20.0f,    0.0f, 1.0f], [ 2.0f, -10.0f, -0.5f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Green  = Light(Matrix.init, [ 10.0f, 20.0f,  0.0f, 1.0f], [   0.0f, 400.0f,   20.0f, 1.0f], [-3.0f,  -9.0f,  3.0f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Blue   = Light(Matrix.init, [ 0.0f,  10.0f, 10.0f, 1.0f], [  20.0f,   0.0f,  400.0f, 1.0f], [ 0.5f,  -2.0f,  1.5f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Bright = Light(Matrix.init, [ 0.0f, 100.0f,  0.0f, 1.0f], [1000.0f,1000.0f, 1000.0f, 1.0f], [ 0.2f,  -1.0f,  0.2f, 0.0f], [0.0f, 0.1f, 90.0f, 0.0f])
};

struct Lighting {
  Light[] lights;
  float sunTime = 12.0f;
  alias lights this;
}

/** Compute lightspace for the provided light */
void computeLightSpace(const App app, ref Light light, bool directional = false, float nearPlane = 0.1f, float farPlane = 500.0f) {
  float[3] lightPos = light.position[0..3];
  float[3] lightDir = light.direction[0..3].normalize();
  float[3] lightTarget = lightPos.vAdd(lightDir);
  float[3] upVector = [0.0f, 1.0f, 0.0f];

  Matrix lightView = lookAt(lightPos, lightTarget, upVector);

  Matrix lightProjection;
  if(directional) {
    lightProjection = orthogonal(-60.0f, 60.0f, -60.0f, 60.0f, nearPlane, farPlane);
  } else {
    float fovY = (2 * light.properties[2]);
    lightProjection = perspective(fovY, 1.0f, nearPlane, farPlane);
  }
  light.lightSpaceMatrix = lightProjection.multiply(lightView);
}

void updateLightGeometries(ref App app) {
  if(!app.showLights) return;
  int sunIdx = 0;
  foreach(o; app.objects) {
    if(o.geometry() == "SunGeometry") {
      o.position(app.lights[0].position[0..3]);
      o.setColor([1.0f, 0.95f, 0.6f, 1.0f]);
    } else if(o.geometry() == "LightCone") {
      if(sunIdx + 1 < app.lights.length) {
        auto light = app.lights[sunIdx + 1];
        o.instances[0].matrix = Matrix.init;
        o.position(light.position[0..3]);
        o.rotate([light.yaw(), 1.0f, light.pitch()]);
        o.setColor(light.intensity);
      }
      sunIdx++;
    }
  }
}

float sunAzimuth(float sunTime) { return (sunTime / 24.0f) * 360.0f;}

float sunElevation(float sunTime, float sunriseH = 8.0f, float sunsetH = 20.0f) {
  float dayFrac = (sunTime - sunriseH) / (sunsetH - sunriseH);
  return (dayFrac >= 0.0f && dayFrac <= 1.0f) ? sin(dayFrac * PI) * 60.0f : -10.0f;
}

void updateSunFromTime(ref App app) { app.updateSun(sunAzimuth(app.lights.sunTime), sunElevation(app.lights.sunTime)); }

/** Show Lights as cones */
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
      app.objects[$-1].scale([5.0f, 5.0f, 5.0f]);
      app.objects[$-1].position(light.position[0..3]);
      app.objects[$-1].setColor([1.0f, 0.95f, 0.6f, 1.0f]);
      app.objects[$-1].texture("2k_sun");
      app.mapTextures(app.objects[$-1]);
    } else {
      app.objects ~= new Cone();
      app.objects[$-1].geometry = (){ return "LightCone"; };
      app.objects[$-1].rotate([light.yaw(), 1.0f, light.pitch()]);
      app.objects[$-1].position(light.position[0..3]);
      app.objects[$-1].setColor(light.intensity);
    }
  }
}

/** Update time of day / sun */
void updateSun(ref App app, float azimuth, float elevation) {
  float azRad = radian(azimuth);
  float elRad = radian(elevation);
  float[3] dir = [ -cos(elRad) * sin(azRad), -sin(elRad), -cos(elRad) * cos(azRad) ];
  SDL_Log("sun dir: %f %f %f elevation: %f", dir[0], dir[1], dir[2], elevation);

  app.lights[0].direction[0..3] = dir;
  app.lights[0].position = [-dir[0]*100.0f, -dir[1]*100.0f, -dir[2]*100.0f, 0.0f];  // w=0 = directional

  // t: 0=night, 1=full day
  float t     = clamp(sin(elRad), 0.0f, 1.0f);          // 0=night, 1=full day
  float dawn  = clamp(1.0f - abs(elevation - 8.0f) / 15.0f, 0.0f, 1.0f);  // peak at 8deg

  float[4] night  = [0.02f, 0.02f, 0.08f, 1.0f];
  float[4] dawn_c = [0.7f,  0.35f, 0.15f, 1.0f];
  float[4] day    = [0.4f,  0.65f, 0.9f,  1.0f];

  // blend: night->dawn->day as three-way lerp, not additive
  float[4] sky;
  if(t < 0.3f) {
    float f = t / 0.3f;
    foreach(i; 0..3) sky[i] = night[i] + f * (dawn_c[i] - night[i]);
  } else {
    float f = (t - 0.3f) / 0.7f;
    foreach(i; 0..3) sky[i] = dawn_c[i] + f * (day[i] - dawn_c[i]);
  }
  sky[3] = 1.0f;
  app.clearValue[0].color.float32 = sky;

  // sun intensity: off at night, warm at dawn/dusk, white at noon
  float[4] sunNight = [0.0f,  0.0f,  0.0f,  1.0f];
  float[4] sunDawn  = [0.9f,  0.5f,  0.1f,  1.0f];
  float[4] sunNoon  = [5.0f,  3.8f,  3.4f, 1.0f];

  float[4] sunColor;
  if(t < 0.3f) {
    float f = t / 0.3f;
    foreach(i; 0..3) sunColor[i] = sunNight[i] + f * (sunDawn[i] - sunNight[i]);
  } else {
    float f = (t - 0.3f) / 0.7f;
    foreach(i; 0..3) sunColor[i] = sunDawn[i] + f * (sunNoon[i] - sunDawn[i]);
  }
  sunColor[3] = 1.0f;
  app.lights[0].intensity = sunColor;
  app.lights[0].properties[0] = t * 0.1f;
  app.lights[1].intensity[0..3] = [t * 0.15f, t * 0.2f, t * 0.25f];  // blue fill, fades at night
  app.lights[1].properties[0] = t * 0.05f;  // ambient also fades

  app.buffers["LightMatrices"].dirty[] = true;
  app.shadows.dirty = true;
}

/** Transfer the lighting into the SSBO for buffer */
void updateLighting(ref App app, VkCommandBuffer buffer, Descriptor descriptor) {
  if(!app.buffers[descriptor.base].dirty[app.syncIndex]) return;
  foreach(i, ref light; app.lights) { app.computeLightSpace(light, i == 0); }
  app.updateSSBO!Light(buffer, app.lights, descriptor, app.syncIndex);
}

float beam(float t, float speed, float freq, float phase) { return abs(sin(t * speed * freq + phase)) * 500.0f; }

/** Disco mode 🕺 🪩 💃 */
void updateDisco(ref App app) {
  if (!app.disco || app.lights.length < 3) return;
  float t = (SDL_GetTicks() - app.time[STARTUP]) / 1000.0f;
  foreach (i; 2 .. app.lights.length) {
    float fi     = cast(float)i;
    float speed  = 0.5f + fmod(fi * 0.61803f, 1.0f) * 1.8f;       /// golden ratio spread
    float radius = 12.0f + fmod(fi * 0.31415f, 1.0f) * 22.0f;
    float height = 12.0f + fmod(fi * 0.71828f, 1.0f) * 25.0f;
    float phase  = fi * 2.39996f;                                 /// golden angle

    float a = t * speed + phase;
    float[3] orbit = [radius * cos(a), height, radius * sin(a)];
    float[3] wobble = [sin(t * 3.1f + phase) * 0.3f, 0.0f, cos(t * 2.7f + phase) * 0.3f];
    app.lights[i].position[0..3]  = orbit;
    app.lights[i].direction[0..3] = orbit.negate().vMul(1.0f / radius).vAdd(wobble);
    app.lights[i].direction[1]    = -1.5f;
    app.lights[i].intensity[0..3] = [beam(t, speed, 4.0f, phase), beam(t, speed, 3.0f, phase), beam(t, speed, 5.0f, phase + 1.0f)];
    app.lights[i].properties[2]   = 25.0f + sin(t * speed) * 10.0f;
  }
  app.buffers["LightMatrices"].dirty[] = true;
  app.shadows.dirty = true;
}

