package com.adbmanage.companion;

import android.Manifest;
import android.app.Activity;
import android.app.NotificationManager;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.util.ArrayList;

/** 定位授权及开始/停止控件；启动只来自手机端用户点击，不接受 ADB 远程启动。 */
public final class LocationControls {
    private static final int REQUEST = 4102;
    private final Activity activity;
    private final TextView state;

    public LocationControls(Activity activity, LinearLayout column) {
        this.activity = activity;
        state = new TextView(activity);
        TextView explanation = new TextView(activity);
        explanation.setText(R.string.location_description);
        column.addView(explanation);
        CheckBox share = new CheckBox(activity);
        share.setText(R.string.location_share);
        share.setChecked(LocationRecordingService.isShared(activity));
        share.setOnCheckedChangeListener((button, checked) -> {
            activity.getSharedPreferences("usage", 0).edit().putBoolean("locationSharing", checked).apply();
            if (!checked) activity.stopService(new Intent(activity, LocationRecordingService.class));
            refresh();
        });
        column.addView(share);
        Button start = new Button(activity);
        start.setText(R.string.location_start);
        start.setOnClickListener(view -> start());
        column.addView(start);
        Button stop = new Button(activity);
        stop.setText(R.string.location_stop);
        stop.setOnClickListener(view -> {
            activity.stopService(new Intent(activity, LocationRecordingService.class));
            state.setText(R.string.location_stopped);
        });
        column.addView(stop);
        column.addView(state);
    }

    private void start() {
        if (!LocationRecordingService.isShared(activity)) {
            state.setText(R.string.location_share_required); return;
        }
        ArrayList<String> permissions = new ArrayList<>();
        if (!LocationRecordingService.hasAccess(activity)) {
            permissions.add(Manifest.permission.ACCESS_FINE_LOCATION);
            permissions.add(Manifest.permission.ACCESS_COARSE_LOCATION);
        }
        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) permissions.add(Manifest.permission.POST_NOTIFICATIONS);
        if (!permissions.isEmpty()) {
            activity.requestPermissions(permissions.toArray(new String[0]), REQUEST);
            return;
        }
        if (!activity.getSystemService(NotificationManager.class).areNotificationsEnabled()) {
            state.setText(R.string.location_permission); return;
        }
        try {
            activity.startForegroundService(new Intent(activity, LocationRecordingService.class));
            state.setText(R.string.location_waiting);
        } catch (RuntimeException error) { state.setText(R.string.location_failed); }
    }

    public void permissionsResult(int requestCode) {
        if (requestCode != REQUEST) return;
        // 授权后由用户再次点击开始，避免权限弹窗返回时 Activity 尚未前台。
        state.setText(LocationRecordingService.hasAccess(activity)
                ? R.string.location_press_start : R.string.location_permission);
    }

    public void refresh() {
        String code = activity.getSharedPreferences("usage", 0).getString("locationStatus", "location_stopped");
        if (!LocationRecordingService.running
                && (code.equals("location_waiting") || code.equals("location_saved"))) code = "location_stopped";
        int id = activity.getResources().getIdentifier(code, "string", activity.getPackageName());
        state.setText(id == 0 ? R.string.location_stopped : id);
    }
}
