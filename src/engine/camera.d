/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import frustum : aabbInFrustum, extractFrustum;
import matrix : inverse, lookAt, radian, multiply, perspective, rotate, transpose;
import quaternion : angleAxis, normalize, qMul, rotate;
import vector : normalize, vAdd, vSub, vMul, xyz, magnitude;

enum CameraMode { fps, follow }

/** Camera structure holding everything camera and movement related
  nearfar[1]: Could be defined from the voxels = (renderDistance + 1) * chunkSize * tileSize * √2f; */
struct Camera {
  VkSurfaceCapabilitiesKHR capabilities;
  alias capabilities this;
  float[3]        fpsEye        = [-15.0f, 5.0f, 0.0f];     /// FPS eye position (authoritative in FPS mode)
  float[3]        lookat        = [0.0f, 5.0f, 0.0f];       /// Position in the middle of the screen
  float[2]        nearfar       = [1.0f, 500.0f];           /// View distances, near [0], far [1]
  float[3]        up            = [0.0f, 1.0f, 0.0f];       /// Defined up vector
  float           fov           = 45.0f;                    /// Field of view
  float           speed         = 30.0f;                    /// Movement speed, units/second
  float[3]        rotation      = [90.0f, 0.0f, 0.0f];      /// Horizontal [0], Vertical [1]
  float           distance      = 15.0f;                    /// Distance of camera to lookat
  bool[2]         isdrag        = [false, false];           /// Mouse dragging
  SDL_FingerID[2] fingerIDs     = [-1, -1];                 /// Android FingerIDs
  float[2][2]     fingerPos     = [[0,0],[0,0]];            /// normalized positions of finger 0 and 1
  float[2]        pressPos      = [0, 0];                   /// Where the current press started (tap-vs-drag test, either button)
  bool[2]         wasDown       = [false, false];           /// [primary, secondary] pointer state LAST frame (edge detection)
  float           lastPinchDist = -1.0f;                    /// -1 = no active pinch
  bool            isDirty       = true;                     /// Camera moved/rotated this frame
  bool            godMode       = true;                     /// Move through walls
  CameraMode      mode          = CameraMode.fps;          /// Active camera mode
  bool delegate(ref float[3] target) follow;               /// Follow-target supplier; returns false when the target is gone
  float[3]        followOffset  = [0.0f, 0.0f, 0.0f];      /// User pan applied on top of the followed target
  float           turn          = 90.0f;                   /// Rotation speed, degrees/second

  @property @nogc float[3] forward() const nothrow { return orientation.multiply([0.0f, 0.0f, -1.0f]); }
  @property @nogc float[3] right() const nothrow { return orientation.multiply([1.0f, 0.0f,  0.0f]); }
  @property @nogc uint width() const nothrow { return(currentExtent.width); };
  @property @nogc uint height() const nothrow { return(currentExtent.height); };
  @property @nogc float aspectRatio() const nothrow { return(width / cast(float) height); }
  @nogc Matrix orientation() const nothrow {
    float[4] qYaw = angleAxis!float(rotation[0], [0.0f, 1.0f, 0.0f]);
    float[4] qPitch = angleAxis!float(-rotation[1], [1.0f, 0.0f, 0.0f]);
    return qMul(qPitch, qYaw).normalize().rotate().transpose();
  }
  @property @nogc Matrix proj() const nothrow { return perspective(fov, width / cast(float)height, nearfar[0], nearfar[1]); }
  @property @nogc Matrix view() const nothrow { return(lookAt(position, lookat, up)); }
  @property @nogc bool fps() const nothrow { return(mode == CameraMode.fps); }
  @nogc float[3] position() const nothrow { return fps ? fpsEye : vAdd(lookat, orientation.multiply([0.0f, 0.0f, distance])); }
  @nogc void syncLookat() nothrow { lookat = vAdd(fpsEye, orientation.multiply([0.0f, 0.0f, -distance])); }
  @nogc void enterFPS() nothrow { fpsEye = vAdd(lookat, orientation.multiply([0.0f, 0.0f, distance])); syncLookat(); }
  @property @nogc float visibleRadius() const nothrow {
    float fov2 = tan(radian(fov) * 0.5f), far = nearfar[1];
    float[2] s = [far - distance, far * fov2 * sqrt(1.0f + aspectRatio * aspectRatio)];
    return s.magnitude();
  }
  bool delegate(float[3] pos) canMoveTo;
}

/** Per-frame camera update: poll held keys (dt-scaled), then track the follow target. */
void updateCamera(ref App app, float dt) {
  auto k = SDL_GetKeyboardState(null);
  float[3] pan = [0.0f, 0.0f, 0.0f];
  if(k[SDL_SCANCODE_W] || k[SDL_SCANCODE_UP]) pan = pan.vAdd(app.camera.forward);
  if(k[SDL_SCANCODE_S] || k[SDL_SCANCODE_DOWN]) pan = pan.vSub(app.camera.forward);
  if(k[SDL_SCANCODE_D] || k[SDL_SCANCODE_RIGHT]) pan = pan.vAdd(app.camera.right);
  if(k[SDL_SCANCODE_A] || k[SDL_SCANCODE_LEFT]) pan = pan.vSub(app.camera.right);
  if(k[SDL_SCANCODE_PAGEUP]) pan[1] += 1.0f;
  if(k[SDL_SCANCODE_PAGEDOWN]) pan[1] -= 1.0f;
  if(pan.magnitude() > 1e-6f) {
    if(app.camera.mode == CameraMode.follow) app.camera.stopFollow();
    app.tryMove(pan.normalize().vMul(app.camera.speed * dt));
  }

  float yaw = (k[SDL_SCANCODE_E] ? 1.0f : 0.0f) - (k[SDL_SCANCODE_Q] ? 1.0f : 0.0f);
  if(yaw != 0.0f) app.camera.drag(yaw * app.camera.turn * dt, 0.0f);

  if(app.camera.mode == CameraMode.follow) {
    float[3] target;
    if(app.camera.follow !is null && app.camera.follow(target)) {
      float a = 1.0f - exp(-12.0f * dt);   // framerate-independent smoothing
      float[3] want = target.vAdd(app.camera.followOffset);
      app.camera.lookat = app.camera.lookat.vAdd(want.vSub(app.camera.lookat).vMul(a));
      app.camera.isDirty = true;
    } else { app.camera.stopFollow(); }
  }
}

/** Engine keyboard: camera navigation + pause. */
void handleCameraKeys(ref App app, SDL_Event e) {
  if(e.type != SDL_EVENT_KEY_DOWN) return;                 // held-key pan/rotate now polled in updateCamera
  if(e.key.key == SDLK_P || e.key.key == SDLK_SPACE) app.paused = !app.paused;
}

/** Leave follow mode, freezing the free-fly eye at the current view. */
@nogc void stopFollow(ref Camera camera) nothrow {
  camera.mode = CameraMode.fps;
  camera.follow = null;
  camera.followOffset = [0.0f, 0.0f, 0.0f];
  camera.enterFPS();
}

/** tryMove (checks God-mode) */
void tryMove(ref App app, float[3] direction) {
  if(!app.camera.fps) { app.camera.fpsEye = app.camera.position(); app.camera.mode = CameraMode.fps; app.camera.syncLookat(); }
  auto oldEye = app.camera.fpsEye; auto oldLook = app.camera.lookat;
  app.camera.move(direction);
  if(!app.camera.godMode && app.camera.canMoveTo && !app.camera.canMoveTo(app.camera.position)) {
    app.camera.fpsEye = oldEye; app.camera.lookat = oldLook; app.camera.syncLookat();
  }
}

/** tryDrag (checks God-mode) */
void tryDrag(ref App app, float xrel, float yrel) {
  auto old = app.camera.rotation;
  app.camera.drag(xrel, yrel);
  if(!app.camera.godMode  && app.camera.canMoveTo && !app.camera.canMoveTo(app.camera.position)) app.camera.rotation = old;
}

/** tryZoom (checks God-mode) */
void tryZoom(ref App app, float delta) {
  auto old = app.camera.distance;
  app.camera.zoom(delta);
  if(!app.camera.godMode  && app.camera.canMoveTo && !app.camera.canMoveTo(app.camera.position)) app.camera.distance = old;
}

/** Create a position/rotation matrix through 3D space starting from xy */
float[3][2] castRay(const ref Camera camera, float x, float y) nothrow {
  float[2] ndc = [(2.0f * x) / cast(float)camera.width  - 1.0f, (2.0f * y) / cast(float)camera.height - 1.0f];
  float[4] clip = [ndc[0], ndc[1], -1.0f, 1.0f];
  float[4] eye  = multiply(camera.proj().inverse(), clip);
  float[3] dir  = multiply(camera.view.inverse(), [eye[0], eye[1], eye[2], 0.0f]).xyz;
  return [camera.position.vAdd(dir), dir.normalize()];
}

/** Move the position the camera looks at */
@nogc void move(ref Camera camera, float[3] movement) nothrow {
  if(camera.fps) { camera.fpsEye = vAdd(camera.fpsEye, movement); camera.syncLookat();
  } else { camera.lookat = vAdd(camera.lookat, movement); }
  camera.isDirty = true;
}

/** Drag the camera in the x/y directions, causes camera rotation */
@nogc void drag(ref Camera camera, float xrel, float yrel) nothrow {
  camera.rotation[0] = fmod(camera.rotation[0] - xrel + 360.0f, 360.0f);
  camera.rotation[1] = clamp(camera.rotation[1] -= yrel, -65.0f, 65.0f);
  if(camera.fps) camera.syncLookat();
  camera.isDirty = true;
}

/** Zoom the distance of the camera to the position the camera looks at */
@nogc void zoom(ref Camera camera, float delta) nothrow {
  camera.distance = clamp(camera.distance + delta, 2.0f, 60.0f);
  camera.isDirty = true;
}
