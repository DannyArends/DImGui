/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import vector : normalize, vMul,vSub, vAdd, negate, xyz;
import matrix : multiply, inverse, rotate, radian, perspective, transpose, lookAt;
import quaternion : xyzw, normalize, rotate, qMul, angleAxis;
import frustum : extractFrustum, aabbInFrustum;

/** Camera
 */
struct Camera {
  VkSurfaceCapabilitiesKHR capabilities;
  alias capabilities this;

  float[3]        lookat        = [0.0f, 0.0f, 0.0f];     /// Position in the middle of the screen
  float[2]        nearfar       = [0.1f, 500.0f];         /// View distances, near [0], far [1]
  float[3]        up            = [0.0f, 1.0f, 0.0f];     /// Defined up vector
  float           fov           = 45.0f;                  /// Field of view
  float           speed         =  0.5f;                  /// Movement speed
  float[3]        rotation      = [0.0f, 0.0f, 0.0f];     /// Horizontal [0], Vertical [1]
  float           distance      = 15.0f;                  /// Distance of camera to lookat
  bool[2]         isdrag        = [false, false];         /// Mouse dragging
  SDL_FingerID[2] fingerIDs     = [-1, -1];               /// Android FingerIDs
  float[2][2]     fingerPos     = [[0,0],[0,0]];          /// normalized positions of finger 0 and 1
  float           lastPinchDist = -1.0f;                  /// -1 = no active pinch
  bool            isDirty       = true;                   /// Camera moved/rotated this frame

  @property @nogc float[3] forward() const nothrow { return orientation.multiply([0.0f, 0.0f, -speed]); }
  @property @nogc float[3] back() const nothrow { return orientation.multiply([0.0f, 0.0f,  speed]); }
  @property @nogc float[3] right() const nothrow { return orientation.multiply([ speed, 0.0f, 0.0f]); }
  @property @nogc float[3] left() const nothrow { return orientation.multiply([-speed, 0.0f, 0.0f]); }
  @property @nogc uint width() const nothrow { return(currentExtent.width); };
  @property @nogc uint height() const nothrow { return(currentExtent.height); };
  @property float aspectRatio() const nothrow { return(this.width / cast(float) this.height); }
  @nogc Matrix orientation() const nothrow {
    float[4] qYaw = angleAxis!float(rotation[0] + 90.0f, [0.0f, 1.0f, 0.0f]);
    float[4] qPitch = angleAxis!float(-rotation[1], [1.0f, 0.0f, 0.0f]);
    return qMul(qPitch, qYaw).normalize().rotate().transpose();
  }
  @property @nogc Matrix proj() const nothrow { return perspective(fov, width / cast(float)height, nearfar[0], nearfar[1]); }
  @property @nogc Matrix view() const nothrow { return(lookAt(position, lookat, up)); }
  @nogc float[3] position() const nothrow { return vAdd(lookat, orientation.multiply([0.0f, 0.0f, distance])); }
}

/* Create a position/rotation matrix through 3D space starting from xy */
float[3][2] castRay(const ref Camera camera, float x, float y) nothrow {
  float[2] ndc = [(2.0f * x) / cast(float)camera.width  - 1.0f, (2.0f * y) / cast(float)camera.height - 1.0f];
  float[4] clip = [ndc[0], ndc[1], -1.0f, 1.0f];
  float[4] eye  = multiply(camera.proj().inverse(), clip);
  float[3] dir  = multiply(camera.view.inverse(), [eye[0], eye[1], eye[2], 0.0f]).xyz;
  return [camera.position.vAdd(dir), dir.normalize()];
}

/* Move the position the camera looks at */
@nogc void move(ref Camera camera, float[3] movement) nothrow { camera.lookat = vAdd(camera.lookat, movement); camera.isDirty = true; }

/* Drag the camera in the x/y directions, causes camera rotation */
@nogc void drag(ref Camera camera, float xrel, float yrel) nothrow {
  camera.rotation[0] = fmod(camera.rotation[0] - xrel + 360.0f, 360.0f);
  camera.rotation[1] = clamp(camera.rotation[1] -= yrel, -65.0f, 65.0f);
  camera.isDirty = true;
}

/* Zoom the distance of the camera to the position the camera looks at */
@nogc void zoom(ref Camera camera, float delta) nothrow {
  camera.distance = clamp(camera.distance + delta, 2.0f, 60.0f);
  camera.isDirty = true;
}
