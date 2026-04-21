/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry;
import matrix : orthogonal, perspective, multiply, lookAt;
import ssbo : updateSSBO;
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
  Sun  = Light(Matrix.init, [50.0f, 80.0f, 50.0f, 1.0f], [0.7f, 0.6f, 0.45f, 1.0f], [-1.0f, -2.0f, -1.0f, 0.0f], [0.08f, 0.0001f, 89.0f, 0.0f]),
  Fill = Light(Matrix.init, [-30.0f, 40.0f, -30.0f, 0.0f], [0.3f, 0.35f, 0.5f, 1.0f], [1.0f, -1.0f, 1.0f, 0.0f], [0.04f, 0.0f, 90.0f, 0.0f]),
  Red    = Light(Matrix.init, [ 10.0f, 20.0f, 10.0f, 1.0f], [ 400.0f,  20.0f,    0.0f, 1.0f], [ 2.0f, -10.0f, -0.5f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Green  = Light(Matrix.init, [ 10.0f, 20.0f,  0.0f, 1.0f], [   0.0f, 400.0f,   20.0f, 1.0f], [-3.0f,  -9.0f,  3.0f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Blue   = Light(Matrix.init, [ 0.0f,  10.0f, 10.0f, 1.0f], [  20.0f,   0.0f,  400.0f, 1.0f], [ 0.5f,  -2.0f,  1.5f, 0.0f], [0.0f, 0.001f, 45.0f, 0.0f]),
  Bright = Light(Matrix.init, [ 0.0f, 100.0f,  0.0f, 1.0f], [1000.0f,1000.0f, 1000.0f, 1.0f], [ 0.2f,  -1.0f,  0.2f, 0.0f], [0.0f, 0.1f, 90.0f, 0.0f])
};

struct Lighting {
  Light[] lights;
  alias lights this;
}

/** Compute lightspace for the provided light
 */
void computeLightSpace(const App app, ref Light light, float nearPlane = 0.1f, float farPlane = 100.0f) {
  float[3] lightPos = light.position[0 .. 3];
  float[3] lightDir = light.direction[0 .. 3].normalize();
  float[3] lightTarget = lightPos.vAdd(lightDir);
  float[3] upVector = [0.0f, 1.0f, 0.0f];

  Matrix lightView = lookAt(lightPos, lightTarget, upVector);

  float fovY = (2 * light.properties[2]);
  Matrix lightProjection = perspective(fovY, 1.0f, nearPlane, farPlane);
  light.lightSpaceMatrix = lightProjection.multiply(lightView);
}


/** Show Lights as cones
 */
void toggleLightGeometries(ref App app) {
  foreach (o; app.objects) {
    if (cast(Cone)o !is null && o.geometry() == "LightCone") o.deAllocate = true;
  }
  if (!app.showLights) return;
  foreach (ref light; app.lights) {
    app.objects ~= new Cone();
    SDL_Log("direction: %f %f %f", light.direction[0], light.direction[1], light.direction[2]);
    app.objects[$-1].geometry = (){ return "LightCone"; };
    app.objects[$-1].rotate([light.yaw(), 1.0f, light.pitch()]);
    app.objects[$-1].position(light.position[0..3]);
    app.objects[$-1].setColor(light.intensity);
  }
}

/** Transfer the lighting into the SSBO for buffer
 */
void updateLighting(ref App app, VkCommandBuffer buffer, Descriptor descriptor) {
  if(!app.buffers[descriptor.base].dirty[app.syncIndex]) return;
  foreach(ref light; app.lights) { app.computeLightSpace(light); }
  app.updateSSBO!Light(buffer, app.lights, descriptor, app.syncIndex);
}

float beam(float t, float speed, float freq, float phase) { return abs(sin(t * speed * freq + phase)) * 500.0f; }

/** Disco mode 🕺 🪩 💃
 */
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

