package com.adbmanage.companion;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** 可见的授权、共享开关和手动预览入口；统计读取放在工作线程。 */
public final class MainActivity extends Activity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private UsageRepository repository;
    private TextView status;
    private Button preview;
    private LocationControls locationControls;
    private CheckBox notifSharing;
    private TextView notifStatus;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        repository = new UsageRepository(this);
        ScrollView scroll = new ScrollView(this);
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        int pad = Math.round(24 * getResources().getDisplayMetrics().density);
        column.setPadding(pad, pad, pad, pad);
        // Android 15+ edge-to-edge：保留状态栏与导航栏空间。
        column.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(pad + insets.getSystemWindowInsetLeft(),
                    pad + insets.getSystemWindowInsetTop(),
                    pad + insets.getSystemWindowInsetRight(),
                    pad + insets.getSystemWindowInsetBottom());
            return insets;
        });
        TextView title = new TextView(this);
        title.setText(R.string.app_name);
        title.setTextSize(24);
        column.addView(title);
        TextView description = new TextView(this);
        description.setText(R.string.description);
        description.setPadding(0, pad, 0, pad);
        column.addView(description);
        CheckBox sharing = new CheckBox(this);
        sharing.setText(R.string.allow_sharing);
        sharing.setChecked(repository.preferences().getBoolean("sharing", false));
        sharing.setOnCheckedChangeListener((button, checked) -> {
            repository.preferences().edit().putBoolean("sharing", checked).apply();
            UsageArchiveJob.schedule(this);
            updateStatus();
        });
        column.addView(sharing);
        CheckBox archive = new CheckBox(this);
        archive.setText(R.string.usage_auto);
        archive.setChecked(repository.preferences().getBoolean("usageAuto", false));
        archive.setOnCheckedChangeListener((button, checked) -> {
            repository.preferences().edit().putBoolean("usageAuto", checked).apply();
            UsageArchiveJob.schedule(this);
        });
        column.addView(archive);
        Button permission = new Button(this);
        permission.setText(R.string.permission);
        permission.setOnClickListener(view -> startActivity(new Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)));
        column.addView(permission);
        preview = new Button(this);
        preview.setText(R.string.preview);
        preview.setOnClickListener(this::preview);
        column.addView(preview);
        status = new TextView(this);
        status.setPadding(0, pad, 0, 0);
        column.addView(status);
        locationControls = new LocationControls(this, column);

        TextView notifTitle = new TextView(this);
        notifTitle.setText(R.string.notification_title);
        notifTitle.setTextSize(20);
        notifTitle.setPadding(0, pad, 0, pad / 2);
        column.addView(notifTitle);

        TextView notifDesc = new TextView(this);
        notifDesc.setText(R.string.notification_description);
        notifDesc.setPadding(0, 0, 0, pad / 2);
        column.addView(notifDesc);

        notifSharing = new CheckBox(this);
        notifSharing.setText(R.string.notification_share);
        notifSharing.setChecked(NotificationForwardingService.isShared(this));
        notifSharing.setOnCheckedChangeListener((button, checked) -> {
            repository.preferences().edit().putBoolean("notificationSharing", checked).apply();
            updateNotificationStatus();
        });
        column.addView(notifSharing);

        Button notifPermission = new Button(this);
        notifPermission.setText(R.string.notification_permission);
        notifPermission.setOnClickListener(view ->
                startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)));
        column.addView(notifPermission);

        notifStatus = new TextView(this);
        notifStatus.setPadding(0, pad / 2, 0, 0);
        column.addView(notifStatus);

        scroll.addView(column);
        setContentView(scroll);
    }

    @Override protected void onResume() {
        super.onResume();
        updateStatus();
        updateNotificationStatus();
        UsageArchiveJob.schedule(this);
        if (locationControls != null) locationControls.refresh();
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        locationControls.permissionsResult(requestCode);
    }

    private void updateStatus() {
        if (status == null) return;
        status.setText(statusResource(repository.status()));
    }

    private void updateNotificationStatus() {
        if (notifStatus == null) return;
        boolean granted = NotificationForwardingService.isPermissionGranted(this);
        notifStatus.setText(granted ? R.string.notification_ready : R.string.notification_permission_required);
    }

    private int statusResource(String code) {
        switch (code) {
            case "ok": return R.string.ready;
            case "sharing_disabled": return R.string.sharing_disabled;
            case "permission_required": return R.string.permission_required;
            case "user_locked": return R.string.user_locked;
            case "no_data": return R.string.no_data;
            default: return R.string.internal_error;
        }
    }

    private void preview(View view) {
        preview.setEnabled(false);
        status.setText(R.string.loading);
        worker.execute(() -> {
            String message;
            try {
                JSONObject report = repository.snapshot();
                String code = report.getString("status");
                message = getString(statusResource(code));
                if (code.equals("ok")) {
                    JSONArray apps = report.getJSONArray("apps");
                    long sum = 0;
                    for (int i = 0; i < apps.length(); i++) sum += apps.getJSONObject(i).getLong("foregroundMs");
                    message = getString(R.string.summary, apps.length(), sum / 60000);
                }
            } catch (Exception error) {
                message = getString(R.string.internal_error);
            }
            final String result = message;
            runOnUiThread(() -> {
                if (isDestroyed()) return;
                preview.setEnabled(true);
                status.setText(result);
            });
        });
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
