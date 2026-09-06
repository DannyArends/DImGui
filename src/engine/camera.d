/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import frustum : aabbInFrustum, extractFrustum;
import matrix : inverse, viewFrom, radian, multiply, perspective, rotate, transpose;
import quaternion : angleAxis, normalize, qMul, rotate;
import vector : normalize, vAdd, vSub, vMul, xyz, magnitude;

enum CameraMode { fps, follow }

/** Camera structure holding everything camera and movement related
  nearfar[1]: Could be defined from the voxels = (renderDistance + 1) * chunkSize * tileSize * √2f; */
struct Camera {
  VkSurfaceCapabilitiesKHR capabilities;
  alias capabilities this;
  float[3]        lookat        = [0.0f, 5.0f, 0.0f];       /// Position in the middle of the screen
  float[3]        eye           = [-15.0f, 5.0f, 0.0f];     /// FPS eye anchor (rotation pivots here, pivot = 0)
  float[2]        nearfar       = [1.0f, 500.0f];           /// View distances, near [0], far [1]
  float[3]        up            = [0.0f, 1.0f, 0.0f];       /// Defined up vector
  float           fov           = 45.0f;                    /// Field of view
  float           speed         = 30.0f;                    /// Movement speed, units/second
  float[3]        rotation      = [90.0f, 0.0f, 0.0f];      /// Horizontal [0], Vertical [1]
  float           distance      = 15.0f;                    /// Distance of camera to lookat
  bool[2]         isdrag        = [false, false];           /// Mouse dragging
  float[2]        dragAccum     = [0.0f, 0.0f];             /// Mouse motion accumulated this frame, applied once in updateCamera
  float           sensitivity   = 0.35;                     /// Mouse look: degrees of rotation per pixel of motion
  SDL_FingerID[2] fingerIDs     = [-1, -1];                 /// Android FingerIDs
  float[2][2]     fingerPos     = [[0,0],[0,0]];            /// normalized positions of finger 0 and 1
  float[2]        pressPos      = [0, 0];                   /// Where the current press started (tap-vs-drag test, either button)
  bool[2]         wasDown       = [false, false];           /// [primary, secondary] pointer state LAST frame (edge detection)
  float           lastPinchDist = -1.0f;                    /// -1 = no active pinch
  bool            isDirty       = true;                     /// Camera moved/rotated this frame
  bool            godMode       = true;                     /// Move through walls
  CameraMode      mode          = CameraMode.fps;           /// Active camera mode
  bool delegate(ref float[3] target) follow;                /// Follow-target supplier; returns false when the target is gone

  @property @nogc float[3] forward() const nothrow { return orientation.multiply([0.0f, 0.0f, -1.0f]); }
  @property @nogc float[3] right() const nothrow { return orientation.multiply([1.0f, 0.0f,  0.0f]); }
  @property @nogc uint width() const nothrow { return(currentExtent.width); };
  @property @nogc uint height() const nothrow { return(currentExtent.height); };
  @property @nogc float aspectRatio() const nothrow { return(width / cast(float) height); }
  @nogc Matrix orientation() const nothrow {
    float[4] qYaw = angleAxis!float(rotation[0], [0.0f, 1.0f, 0.0f]);
    float[4] qPitch = angleAxis!float(-rotation[1], [1.0f, 0.0f, 0.0f]);
    return qMul(qPitch, qYaw).normalize().rotate();
  }
  @property @nogc Matrix proj() const nothrow { return(perspective(fov, width / cast(float)height, nearfar[0], nearfar[1])); }
  @property @nogc Matrix view() const nothrow { return(orientation.viewFrom(position)); }
  @property @nogc bool fps() const nothrow { return(mode == CameraMode.fps); }
  @nogc float[3] position() const nothrow { return fps ? eye : vAdd(lookat, orientation.multiply([0.0f, 0.0f, distance])); }
  @nogc void stopFollow() nothrow { eye = position(); mode = CameraMode.fps; follow = null; }
  @property @nogc float visibleRadius() const nothrow {
    float fov2 = tan(radian(fov) * 0.5f), far = nearfar[1];
    float[2] s = [far - distance, far * fov2 * sqrt(1.0f + aspectRatio * aspectRatio)];
    return s.magnitude();
  }
  bool delegate(float[3] pos) canMoveTo;
}

/** Run a camera mutation, reverting the whole pose if it lands the eye in blocked space. */
void guarded(ref Camera camera, scope void delegate() act) {
  auto snap = camera; act(); if(!camera.godMode && camera.canMoveTo && !camera.canMoveTo(camera.position)) { camera = snap; }
}

/** Translate the active anchor, blocked by collision unless in god mode. */
void tryMove(ref Camera camera, float[3] direction) { if(!camera.fps) camera.stopFollow(); camera.guarded({ camera.move(direction); }); }

/** Rotate from a screen-space drag delta. */
void tryDrag(ref Camera camera, float xrel, float yrel) { camera.guarded({ camera.drag(xrel, yrel); }); }

/** Zoom the eye-to-focus distance. */
void tryZoom(ref Camera camera, float delta) { camera.guarded({ camera.zoom(delta); }); }

/** Create a position/rotation matrix through 3D space starting from xy */
float[3][2] castRay(const ref Camera camera, float x, float y) nothrow {
  float[2] ndc = [(2.0f * x) / cast(float)camera.width  - 1.0f, (2.0f * y) / cast(float)camera.height - 1.0f];
  float[4] clip = [ndc[0], ndc[1], -1.0f, 1.0f];
  float[4] eye = multiply(camera.proj().inverse(), clip);
  float[3] dir = multiply(camera.view.inverse(), [eye[0], eye[1], eye[2], 0.0f]).xyz;
  return([camera.position.vAdd(dir), dir.normalize()]);
}

/** Move the position the camera looks at */
@nogc void move(ref Camera camera, float[3] movement) nothrow {
  if(camera.fps) camera.eye = vAdd(camera.eye, movement); else camera.lookat = vAdd(camera.lookat, movement);
  camera.isDirty = true;
}

/** Drag the camera in the x/y directions, causes camera rotation */
@nogc void drag(ref Camera camera, float xrel, float yrel) nothrow {
  camera.rotation[0] = fmod(camera.rotation[0] - xrel, 360.0f);
  camera.rotation[1] = clamp(camera.rotation[1] - yrel, -85.0f, 85.0f);
  camera.isDirty = true;
}

/** Zoom the distance of the camera to the position the camera looks at */
@nogc void zoom(ref Camera camera, float delta) nothrow {
  camera.distance = clamp(camera.distance + delta, 2.0f, 60.0f);
  camera.isDirty = true;
}
