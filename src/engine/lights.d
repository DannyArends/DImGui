/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import matrix : orthogonal, perspective, multiply, lookAt;
import ssbo : updateSSBO;
import vector : normalize, vAdd;

struct Light {
  Matrix lightSpaceMatrix;
  float[4] position   = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light Position
  float[4] intensity  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light intensity
  float[4] direction  = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light direction
  float[4] properties = [0.0f, 0.0f, 0.0f, 0.0f];    /// Light properties [ambient, attenuation, angle, unused]
}

enum Lights : Light {
  Red    = Light(Matrix.init, [ 4.0f, 10.0f,-10.0f, 1.0f], [15.0f, 2.5f,  0.0f, 1.0f], [ 2.0f, -10.0f, -0.5f, 0.0f], [0.0f, 0.001f, 40.0f, 0.0f]),
  Green  = Light(Matrix.init, [ 3.0f,  6.0f, -5.0f, 1.0f], [ 0.0f, 15.0f, 2.5f, 1.0f], [-3.0f,  -9.0f,  3.0f, 0.0f], [0.0f, 0.001f, 40.0f, 0.0f]),
  Blue   = Light(Matrix.init, [ 0.0f, 10.0f, -3.5f, 1.0f], [ 2.5f, 0.0f, 15.0f, 1.0f], [ 0.5f,  -2.0f,  1.5f, 0.0f], [0.0f, 0.001f, 40.0f, 0.0f]),
  Bright = Light(Matrix.init, [-0.5f,  4.0f,  1.0f, 1.0f], [ 1.0f, 1.0f,  1.0f, 1.0f], [ 0.1f,  -1.0f,  0.1f, 0.0f], [0.0f, 0.001f, 75.0f, 0.0f])
};

struct Lighting {
  Light[] lights;
  alias lights this;
}

/** Compute lightspace for the provided light
 */
void computeLightSpace(const App app, ref Light light){
  float[3] lightPos = light.position[0 .. 3];
  float[3] lightDir = light.direction[0 .. 3].normalize();
  float[3] lightTarget = lightPos.vAdd(lightDir);
  float[3] upVector = [0.0f, 1.0f, 0.0f];

  Matrix lightView = lookAt(lightPos, lightTarget, upVector);

  float fovY = (2 * light.properties[2]);
  float nearPlane = 0.1f;
  float farPlane = 100.0f;
  Matrix lightProjection = perspective(fovY, 1.0f, nearPlane, farPlane);
  light.lightSpaceMatrix = lightProjection.multiply(lightView);
}

/** Transfer the lighting into the SSBO for buffer
 */
void updateLighting(ref App app, VkCommandBuffer buffer, Descriptor descriptor){
  app.buffers[descriptor.base].dirty[] = true;  // TODO: We only need to update lights when they change (imgui)
  foreach(ref light; app.lights) { app.computeLightSpace(light); }
  app.updateSSBO!Light(buffer, app.lights, descriptor, app.syncIndex);
}

