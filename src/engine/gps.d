/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

version(Android) {

  /** A single GPS fix delivered asynchronously from Android */
  struct LocationFix {
    double lat;  /// Latitude in degrees
    double lon;  /// Longitude in degrees
    float acc;   /// Horizontal accuracy in metres (-1 if unknown)
    long time;   /// Fix wall-clock time (ms since epoch)
  }

  private __gshared uint _locationEvent; /// SDL event type for async permission + GPS (see initLocation)

  enum : int { PERM_DENIED = 0, PERM_GRANTED = 1, LOCATION_FIX = 2 } /// UserEvent codes

  /** Register the async permission / GPS event type; call once after SDL_Init */
  void initLocation() { _locationEvent = SDL_RegisterEvents(1); }

  /** Push a UserEvent onto the SDL queue (thread-safe); frees data1 if the queue rejects it */
  private void pushLocationEvent(int code, void* data1 = null) nothrow @nogc {
    SDL_Event e;
    e.type = _locationEvent;
    e.user.code = code;
    e.user.data1 = data1;
    if(!SDL_PushEvent(&e) && data1) SDL_free(data1);
  }

  /** SDL permission callback: signals the decision to the main loop (no polling) */
  extern(C) void onPermission(void* userdata, const(char)* permission, bool granted) nothrow @nogc {
    SDL_Log("[PERM] %s = %d", permission, cast(int)granted);
    pushLocationEvent(granted ? PERM_GRANTED : PERM_DENIED);
  }

  /** Request an Android runtime permission by manifest name (async, result via onPermission) */
  bool requestPermission(const(char)* permission) {
    return(SDL_RequestAndroidPermission(permission, &onPermission, null));
  }

  /** JNI entry: Android delivers a fix on its own thread; marshal it to the main loop via SDL */
  export extern(C) void Java_nl_dannyarends_app_GPS_nativeLocation(JNIEnv* env, jclass clazz, jdouble lat, jdouble lon, jfloat acc, jlong time) nothrow @nogc {
    LocationFix* fix = cast(LocationFix*)SDL_malloc(LocationFix.sizeof);
    if(!fix) return;
    *fix = LocationFix(lat, lon, acc, time);
    pushLocationEvent(LOCATION_FIX, fix);
  }

  /** Start GPS + network updates on the Android UI thread (fixes arrive via app.onLocation) */
  void startLocation(long minMs = 1000, float minMeters = 1.0f) {
    auto j = JNI(cast(JNIEnv*)SDL_GetAndroidJNIEnv());
    auto c = j.FindClass("nl/dannyarends/app/GPS".toStringz);
    auto m = j.GetStaticMethodID(c, "start".toStringz, "(JF)V".toStringz);
    j.CallStaticVoidMethod(c, m, cast(jlong)minMs, cast(jfloat)minMeters);
    j.DeleteLocalRef(c);
  }

  /** Stop GPS + network updates */
  void stopLocation() {
    auto j = JNI(cast(JNIEnv*)SDL_GetAndroidJNIEnv());
    auto c = j.FindClass("nl/dannyarends/app/GPS".toStringz);
    auto m = j.GetStaticMethodID(c, "stop".toStringz, "()V".toStringz);
    j.CallStaticVoidMethod(c, m);
    j.DeleteLocalRef(c);
  }

  /** Drain a permission / GPS UserEvent on the main thread; true if it was ours */
  bool handleLocationEvent(ref App app, ref SDL_Event e) {
    if(e.type != _locationEvent) return(false);
    switch(e.user.code) {
      case PERM_GRANTED: SDL_Log("[GPS] granted, starting updates"); startLocation(); break;
      case PERM_DENIED:  SDL_Log("[GPS] denied"); break;
      case LOCATION_FIX: {
        LocationFix* fix = cast(LocationFix*)e.user.data1;
        if(app.onLocation) app.onLocation(*fix);
        SDL_free(fix);
        break;
      }
      default: break;
    }
    return(true);
  }

  void initGPS() {
    initLocation();
    requestPermission("android.permission.ACCESS_FINE_LOCATION".toStringz);
  }
}
