package com.adbmanage.companion;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.SystemClock;
import org.json.JSONObject;

/** 用户在可见页面开启的位置记录；持续通知可停止，进程被杀或重启后不自动恢复。 */
public final class LocationRecordingService extends Service implements LocationListener {
    private static final String CHANNEL = "location_recording";
    private static final int NOTIFICATION_ID = 4102;
    public static volatile boolean running;
    private HandlerThread worker;
    private LocationManager manager;
    private volatile boolean active;

    public static boolean hasAccess(Context context) {
        return context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
                == PackageManager.PERMISSION_GRANTED
                || context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
    }

    public static boolean isShared(Context context) {
        return context.getSharedPreferences("usage", 0).getBoolean("locationSharing", false);
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null || "stop".equals(intent.getAction())) {
            stopSelf(); return START_NOT_STICKY;
        }
        if (active) return START_NOT_STICKY;
        if (!hasAccess(this) || !isShared(this)
                || !getSystemService(NotificationManager.class).areNotificationsEnabled()) {
            fail("location_permission"); return START_NOT_STICKY;
        }
        NotificationManager notifications = getSystemService(NotificationManager.class);
        notifications.createNotificationChannel(new NotificationChannel(CHANNEL,
                getString(R.string.location_title), NotificationManager.IMPORTANCE_LOW));
        NotificationChannel channel = notifications.getNotificationChannel(CHANNEL);
        if (channel.getImportance() == NotificationManager.IMPORTANCE_NONE) {
            fail("location_permission"); return START_NOT_STICKY;
        }
        PendingIntent open = PendingIntent.getActivity(this, 0,
                new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);
        PendingIntent stop = PendingIntent.getService(this, 1,
                new Intent(this, LocationRecordingService.class).setAction("stop"),
                PendingIntent.FLAG_IMMUTABLE);
        startForeground(NOTIFICATION_ID, new Notification.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle(getString(R.string.location_recording))
                .setContentText(getString(R.string.location_notification))
                .setContentIntent(open).setOngoing(true)
                .addAction(new Notification.Action.Builder(null, getString(R.string.location_stop), stop).build())
                .build());
        manager = getSystemService(LocationManager.class);
        worker = new HandlerThread("companion-location");
        worker.start();
        active = true;
        running = true;
        getSharedPreferences("usage", 0).edit().putString("locationStatus", "location_waiting").apply();
        int providers = 0;
        // 同时支持设备网络定位和 GNSS；不依赖 Google Play services。
        for (String provider : new String[]{LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER}) {
            try {
                if (!manager.isProviderEnabled(provider)) continue;
                manager.requestLocationUpdates(provider, 5 * 60000L, 50f, this, worker.getLooper());
                providers++;
            } catch (SecurityException | IllegalArgumentException ignored) { }
        }
        if (providers == 0) fail("location_unavailable");
        return START_NOT_STICKY;
    }

    @Override public void onLocationChanged(Location location) {
        if (!active || !isShared(this) || !hasAccess(this)) return;
        long age = SystemClock.elapsedRealtimeNanos() - location.getElapsedRealtimeNanos();
        // 旧缓存不能冒充当前位置；只接受最近两分钟的真实系统回调。
        if (age < 0 || age > 120000000000L || !location.hasAccuracy()
                || !Double.isFinite(location.getLatitude()) || !Double.isFinite(location.getLongitude())) return;
        try {
            boolean mock = Build.VERSION.SDK_INT >= 31 ? location.isMock() : location.isFromMockProvider();
            JSONObject point = new JSONObject()
                    .put("capturedAtMs", location.getTime())
                    .put("receivedAtMs", System.currentTimeMillis())
                    .put("latitude", location.getLatitude()).put("longitude", location.getLongitude())
                    .put("accuracyMeters", location.getAccuracy()).put("provider", location.getProvider())
                    .put("mock", mock).put("coordinateSystem", "WGS84");
            CompanionStore.get(this).append("location", point);
            getSharedPreferences("usage", 0).edit().putString("locationStatus", "location_saved").apply();
        } catch (Exception error) { fail("location_failed"); }
    }

    private void fail(String status) {
        getSharedPreferences("usage", 0).edit().putString("locationStatus", status).apply();
        stopSelf();
    }

    @Override public void onProviderEnabled(String provider) { }
    @Override public void onProviderDisabled(String provider) {
        getSharedPreferences("usage", 0).edit().putString("locationStatus", "location_unavailable").apply();
    }
    @Override public void onStatusChanged(String provider, int status, Bundle extras) { }
    @Override public IBinder onBind(Intent intent) { return null; }

    @Override public void onDestroy() {
        active = false;
        running = false;
        if (manager != null) {
            try { manager.removeUpdates(this); } catch (SecurityException ignored) { }
        }
        if (worker != null) worker.quitSafely();
        stopForeground(STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }
}
