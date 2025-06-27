/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import vector : normalize, vMul,vSub, vAdd, negate, xyz;
import matrix : Matrix, multiply, inverse, rotate, radian, perspective, lookAt;
import quaternion : xyzw;

/** Camera
 */
struct Camera {
  VkSurfaceCapabilitiesKHR capabilities;
  alias capabilities this;

  float[3]     lookat      = [0.0f, 0.0f, 0.0f];    // Position in the middle of the screen
  float[2]     nearfar     = [0.1f, 100.0f];        // View distances, near [0], far [1]
  float[3]     up          = [0.0f, 1.0f, 0.0f];    // Defined up vector
  float        fov         = 45.0f;                 // Field of view

  float[3]     rotation    = [0.0f, 0.0f, 0.0f];    // Horizontal [0], Vertical [1]
  version (Android) {
    float        distance    = 10.0f;               // Distance of camera to lookat
  }else{
    float        distance    = 3.0f;                // Distance of camera to lookat
  }
  bool[2]      isdrag        = [false, false];

  // Move the camera forward
  @property @nogc float[3] forward() const nothrow { 
    float[3] direction = rotation.direction().normalize();
    direction = direction.vMul(-0.1f);
    return(direction);
  }

  // Move the camera backward
  @property @nogc float[3] back() const nothrow { 
    float[3] back = -forward()[];
    return(back);
  }

  @property uint width() { return(currentExtent.width); };
  @property uint height() { return(currentExtent.height); };
  @property float aspectRatio() { return(this.width / cast(float) this.height); }

  @property Matrix proj() { return(perspective(fov, aspectRatio, nearfar[0], nearfar[1])); }

  @property @nogc Matrix view() nothrow { return(lookAt(position, lookat, up)); }

  // Move the camera to the left of the view direction
  @property @nogc float[3] left() const nothrow {
    float[3] left = -right()[];
    return(left);
  }

  // Move the camera to the right of the view direction
  @property @nogc float[3] right() const nothrow { 
    float[3] direction = forward();
    direction[1] = 0.0f;
    return(multiply(rotate(Matrix.init, [90.0f, 0.0f, 0.0f]), direction.xyzw()).xyz);
  }

  @nogc float[3] position() const nothrow { return(vAdd(lookat, vMul(rotation.direction(), distance))); }
}

/* Create a position/rotation matrix through 3D space starting from xy */
float[3][2] castRay(Camera camera, uint x, uint y) {
  float[2] ndc = [(2.0f * x) / cast(float) camera.width  - 1.0f,                            // Normalized device X
                  (2.0f * y) / cast(float) camera.height - 1.0f];                           // Normalized device Y
  float[4] clip = [ndc[0], ndc[1], -1.0f, 1.0f];                                            // Homogeneous clip coordinates
  float[4] eye = multiply(inverse(camera.proj), clip);                                      // Eye coordinates
  float[3] world = multiply(inverse(camera.view), [ eye[0], eye[1], eye[2], 0.0f]).xyz;     // World coordinates (offset to camera position)
  float[3] direction = multiply(inverse(camera.view), [ eye[0], eye[1], eye[2], 0.0f]).xyz; // Ray direction
  return([camera.position.vAdd(world), direction.normalize()]);
}

/* Get the normalized direction of the xy camera rotation (gimbal lock) */
@nogc float[3] direction(const float[3] rotation) nothrow {
  float[3] direction = [
      cos(radian(rotation[1])) * cos(radian(rotation[0])),
      sin(radian(rotation[1])),
      cos(radian(rotation[1])) * sin(radian(rotation[0])),
  ];
  return(direction.normalize().negate());
}

@nogc void move(ref Camera camera, float[3] movement) nothrow {
  camera.lookat = vAdd(camera.lookat, movement);
}

/* Drag the camera in the x/y directions, causes camera rotation */
@nogc void drag(ref Camera camera, float xrel, float yrel) nothrow {
  camera.rotation[0] -= xrel; 
  if(camera.rotation[0]  > 360) camera.rotation[0] = 0;
  if(camera.rotation[0]  < 0) camera.rotation[0] = 360;

  camera.rotation[1] -= yrel;
  if(camera.rotation[1]  > 65) camera.rotation[1] = 65;
  if(camera.rotation[1]  < -65) camera.rotation[1] = -65;
}

