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
  Red    = Light(Matrix.init, [ 4.0f, 10.0f,10.0f, 1.0f], [15.0f, 2.5f,  0.0f, 1.0f], [ 2.0f, -10.0f, -0.5f, 0.0f], [0.0f, 0.001f, 40.0f, 0.0f]),
  Green  = Light(Matrix.init, [ 3.0f,  6.0f, 5.0f, 1.0f], [ 0.0f,15.0f,  2.5f, 1.0f], [-3.0f,  -9.0f,  3.0f, 0.0f], [0.0f, 0.001f, 40.0f, 0.0f]),
  Blue   = Light(Matrix.init, [ 0.0f, 10.0f, 3.5f, 1.0f], [ 2.5f, 0.0f, 15.0f, 1.0f], [ 0.5f,  -2.0f,  1.5f, 0.0f], [0.0f, 0.001f, 40.0f, 0.0f]),
  Bright = Light(Matrix.init, [ 0.0f, 20.0f,  0.0f, 1.0f], [50.0f,50.0f, 50.0f, 1.0f], [ 0.1f,  -1.0f,  0.1f, 0.0f], [0.0f, 0.001f, 75.0f, 0.0f])
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
    if (cast(Cone)o !is null && o.name() == "LightCone") o.deAllocate = true;
  }
  if (!app.showLights) return;
  foreach (ref light; app.lights) {
    app.objects ~= new Cone();
    SDL_Log("direction: %f %f %f", light.direction[0], light.direction[1], light.direction[2]);
    app.objects[$-1].name = (){ return "LightCone"; };
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

float beam(float t, float speed, float freq, float phase) { return abs(sin(t * speed * freq + phase)) * 15.0f; }

/** Disco mode 🕺 🪩 💃
 */
void updateDisco(ref App app) {
  if(!app.disco || app.lights.length < 4) return;
  float t = (SDL_GetTicks() - app.time[STARTUP]) / 1000.0f;
  float[4] speeds = [1.3f, 0.7f, 1.7f, 2.3f];
  float[4] radii = [20.0f, 15.0f, 25.0f, 18.0f];
  float[4] heights = [15.0f, 12.0f, 20.0f, 10.0f];
  float[4] phases = [0.0f, PI/2, PI, 3*PI/2];
  foreach(i; 0..min(4, app.lights.length)) {
    float a = t * speeds[i] + phases[i];
    float[3] orbit = [radii[i] * cos(a), heights[i], radii[i] * sin(a)];
    float[3] wobble = [sin(t * 3.1f + phases[i]) * 0.3f, 0.0f, cos(t * 2.7f + phases[i]) * 0.3f];
    app.lights[i].position[0..3] = orbit;
    app.lights[i].direction[0..3] = orbit.negate().vMul(1.0f / radii[i]).vAdd(wobble);
    app.lights[i].direction[1] = -1.5f;
    app.lights[i].intensity[0..3] = [beam(t, speeds[i], 4.0f, phases[i]), beam(t, speeds[i], 3.0f, phases[i]), beam(t, speeds[i], 5.0f, phases[i] + 1.0f)];
    app.lights[i].properties[2] = 25.0f + sin(t * speeds[i]) * 10.0f;
  }
  app.buffers["LightMatrices"].dirty[] = true;
  app.shadows.dirty = true;
}

