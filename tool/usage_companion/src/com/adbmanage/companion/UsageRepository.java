package com.adbmanage.companion;

import android.app.AppOpsManager;
import android.app.usage.EventStats;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStats;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Process;
import android.os.UserManager;
import android.util.AtomicFile;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Calendar;
import java.util.List;
import java.util.Map;
import java.util.TimeZone;
import java.util.TreeMap;
import java.util.UUID;

/** 按需读取系统日桶并原子保存快照，不创建采集服务或重复获取 App 图标。 */
public final class UsageRepository {
    private static final Object SNAPSHOT_LOCK = new Object();
    private final Context context;

    public UsageRepository(Context context) {
        this.context = context.getApplicationContext();
    }

    public SharedPreferences preferences() {
        return context.getSharedPreferences("usage", Context.MODE_PRIVATE);
    }

    public boolean hasAccess() {
        AppOpsManager ops = context.getSystemService(AppOpsManager.class);
        return ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(), context.getPackageName()) == AppOpsManager.MODE_ALLOWED;
    }

    public String status() {
        if (!context.getSystemService(UserManager.class).isUserUnlocked()) return "user_locked";
        if (!preferences().getBoolean("sharing", false)) return "sharing_disabled";
        return hasAccess() ? "ok" : "permission_required";
    }

    /** Binder 请求在清除调用身份后进入；锁用于串行化安装标识和快照写入。 */
    public JSONObject snapshot() throws Exception {
        synchronized (SNAPSHOT_LOCK) {
            return createSnapshot();
        }
    }

    private JSONObject createSnapshot() throws Exception {
        String status = status();
        if (!status.equals("ok")) return new JSONObject().put("status", status);
        long now = System.currentTimeMillis();
        Calendar day = Calendar.getInstance();
        day.set(Calendar.HOUR_OF_DAY, 0);
        day.set(Calendar.MINUTE, 0);
        day.set(Calendar.SECOND, 0);
        day.set(Calendar.MILLISECOND, 0);
        long requestedStart = day.getTimeInMillis();
        UsageStatsManager manager = context.getSystemService(UsageStatsManager.class);
        List<UsageStats> stats = manager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY, requestedStart, now);
        if (stats == null || stats.isEmpty()) return new JSONObject().put("status", "no_data");

        // 保留每个包实际区间，不能把扩展后的系统日桶伪装成精确自然日。
        Map<String, UsageStats> byPackage = new TreeMap<>();
        for (UsageStats item : stats) {
            UsageStats previous = byPackage.get(item.getPackageName());
            if (previous == null) byPackage.put(item.getPackageName(), new UsageStats(item));
            else previous.add(item);
        }
        JSONArray apps = new JSONArray();
        long rangeStart = now;
        long rangeEnd = 0;
        for (UsageStats item : byPackage.values()) {
            rangeStart = Math.min(rangeStart, item.getFirstTimeStamp());
            rangeEnd = Math.max(rangeEnd, item.getLastTimeStamp());
            if (item.getTotalTimeInForeground() <= 0) continue;
            apps.put(new JSONObject()
                    .put("packageName", item.getPackageName())
                    .put("foregroundMs", item.getTotalTimeInForeground())
                    .put("rangeStartMs", item.getFirstTimeStamp())
                    .put("rangeEndMs", item.getLastTimeStamp()));
        }
        String installId = preferences().getString("installId", null);
        if (installId == null) {
            installId = UUID.randomUUID().toString();
            if (!preferences().edit().putString("installId", installId).commit()) {
                throw new IllegalStateException("Could not persist installation identity");
            }
        }
        JSONObject report = new JSONObject()
                .put("status", "ok").put("schemaVersion", 1)
                .put("installationId", installId).put("androidUserId", Process.myUid() / 100000)
                .put("generatedAtMs", now).put("requestedStartMs", requestedStart)
                .put("rangeStartMs", rangeStart).put("rangeEndMs", rangeEnd)
                .put("timeZone", TimeZone.getDefault().getID())
                .put("utcOffsetMinutes", TimeZone.getDefault().getOffset(now) / 60000)
                .put("apps", apps);
        // 屏幕交互时长独立于 App 时长，不累加多窗口前台时间作为整机时长。
        List<EventStats> events = android.os.Build.VERSION.SDK_INT >= 28
                ? manager.queryEventStats(UsageStatsManager.INTERVAL_DAILY, requestedStart, now)
                : null;
        long screenMs = 0, screenStart = now, screenEnd = 0;
        boolean hasScreen = false;
        if (events != null) for (EventStats item : events) {
            if (item.getEventType() != UsageEvents.Event.SCREEN_INTERACTIVE) continue;
            hasScreen = true;
            screenMs += item.getTotalTime();
            screenStart = Math.min(screenStart, item.getFirstTimeStamp());
            screenEnd = Math.max(screenEnd, item.getLastTimeStamp());
        }
        if (hasScreen) report.put("screenInteractiveMs", screenMs)
                .put("screenRangeStartMs", screenStart).put("screenRangeEndMs", screenEnd);
        // 权限/共享状态在查询期间撤回时，不再保存或导出新的结果。
        status = status();
        if (!status.equals("ok")) return new JSONObject().put("status", status);
        byte[] encoded = report.toString().getBytes(StandardCharsets.UTF_8);
        // Base64 经 Bundle 按 UTF-16 传输，预留 Binder 事务空间。
        if (encoded.length > 256 * 1024) throw new IllegalStateException("Snapshot too large");
        AtomicFile file = new AtomicFile(new File(context.getFilesDir(), "usage_snapshot.json"));
        FileOutputStream stream = file.startWrite();
        try {
            stream.write(encoded);
            file.finishWrite(stream);
        } catch (Exception error) {
            file.failWrite(stream);
            throw error;
        }
        return report;
    }
}
