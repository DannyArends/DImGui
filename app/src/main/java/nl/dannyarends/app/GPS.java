package nl.dannyarends.app;

import android.app.Activity;
import android.content.Context;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;

import org.libsdl.app.SDLActivity;

/** Bridges Android location updates to native code via a JNI callback. */
public class GPS implements LocationListener {
  private static GPS instance;
  private final LocationManager manager;

  private GPS(Context ctx) { manager = (LocationManager) ctx.getSystemService(Context.LOCATION_SERVICE); }

  /** Native sink for each fix; implemented in libmain.so. */
  private static native void nativeLocation(double lat, double lon, float acc, long time);

  /** Start GPS + network updates on the UI thread; called from native. */
  public static void start(final long minMs, final float minM) {
    final Activity ctx = SDLActivity.getContext();
    ctx.runOnUiThread(new Runnable() {
        public void run() {
        if (instance == null) instance = new GPS(ctx);
        instance.begin(minMs, minM);
      }
    });
  }

  private void begin(long minMs, float minM) {
    try {
      seed(manager.getLastKnownLocation(LocationManager.GPS_PROVIDER));
      seed(manager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER));
      if (manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, minMs, minM, this);
      if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) manager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, minMs, minM, this);
    } catch (SecurityException e) { /* permission not granted yet */ }
  }

  private void seed(Location l) { if (l != null) onLocationChanged(l); }

  /** Stop updates; called from native. */
  public static void stop() {
    final GPS g = instance;
    if (g == null) return;
    ((Activity) SDLActivity.getContext()).runOnUiThread(new Runnable() {
      public void run() { try { g.manager.removeUpdates(g); } catch (SecurityException e) {} }
    });
  }

  @Override public void onLocationChanged(Location l) {
    nativeLocation(l.getLatitude(), l.getLongitude(), l.hasAccuracy() ? l.getAccuracy() : -1.0f, l.getTime());
  }
}