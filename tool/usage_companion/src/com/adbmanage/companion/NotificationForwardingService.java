package com.adbmanage.companion;

import android.app.Notification;
import android.content.ComponentName;
import android.content.Context;
import android.os.Bundle;
import android.provider.Settings;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import org.json.JSONObject;
import java.util.UUID;

/**
 * 手机端通知监听服务，负责按规则过滤并将增量事件推入有界内存队列。
 */
public final class NotificationForwardingService extends NotificationListenerService {
    private static volatile NotificationSession activeSession = null;
    private static volatile boolean isConnected = false;

    @Override
    public void onListenerConnected() {
        super.onListenerConnected();
        isConnected = true;
    }

    @Override
    public void onListenerDisconnected() {
        super.onListenerDisconnected();
        isConnected = false;
        NotificationSession s = activeSession;
        if (s != null) {
            s.clear();
            activeSession = null;
        }
    }

    public static boolean isShared(Context context) {
        return context.getSharedPreferences("usage_prefs", Context.MODE_PRIVATE)
                .getBoolean("notificationSharing", false);
    }

    public static boolean isPermissionGranted(Context context) {
        String flat = Settings.Secure.getString(context.getContentResolver(), "enabled_notification_listeners");
        if (flat == null || flat.isEmpty()) return false;
        String[] names = flat.split(":");
        String target = context.getPackageName();
        for (String name : names) {
            ComponentName cn = ComponentName.unflattenFromString(name);
            if (cn != null && target.equals(cn.getPackageName())) {
                return true;
            }
        }
        return false;
    }

    public static synchronized String startSession(Context context) {
        NotificationSession old = activeSession;
        if (old != null) {
            old.clear();
        }
        String id = UUID.randomUUID().toString();
        activeSession = new NotificationSession(id);
        return id;
    }

    public static synchronized JSONObject pollEvents(Context context, String sessionId, long afterCursor) {
        NotificationSession session = activeSession;
        if (session == null || !session.getSessionId().equals(sessionId) || session.isExpired()) {
            if (session != null && session.isExpired()) {
                session.clear();
                activeSession = null;
            }
            JSONObject res = new JSONObject();
            try {
                res.put("status", "session_expired");
            } catch (Exception ignored) {}
            return res;
        }
        return session.poll(afterCursor, 100);
    }

    public static synchronized void stopSession(Context context, String sessionId) {
        NotificationSession session = activeSession;
        if (session != null && (sessionId == null || session.getSessionId().equals(sessionId))) {
            session.clear();
            activeSession = null;
        }
    }

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        if (!isShared(this)) return;
        NotificationSession session = activeSession;
        if (session == null || session.isExpired()) return;

        // 1. 过滤 Companion 自身通知
        if (getPackageName().equals(sbn.getPackageName())) return;

        Notification notification = sbn.getNotification();
        if (notification == null) return;

        // 2. 过滤常驻通知
        if (sbn.isOngoing() || (notification.flags & Notification.FLAG_ONGOING_EVENT) != 0) {
            return;
        }

        // 3. 过滤进度通知
        Bundle extras = notification.extras;
        if (extras != null && extras.getInt(Notification.EXTRA_PROGRESS_MAX, 0) > 0) {
            return;
        }

        // 4. 过滤分组汇总通知
        if ((notification.flags & Notification.FLAG_GROUP_SUMMARY) != 0) {
            return;
        }

        // 提取普通通知核心字段
        String title = "";
        String text = "";
        if (extras != null) {
            CharSequence csTitle = extras.getCharSequence(Notification.EXTRA_TITLE);
            if (csTitle != null) title = csTitle.toString();
            CharSequence csText = extras.getCharSequence(Notification.EXTRA_TEXT);
            if (csText == null) {
                csText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT);
            }
            if (csText != null) text = csText.toString();
        }

        try {
            JSONObject event = new JSONObject();
            event.put("event", "posted");
            event.put("key", sbn.getKey());
            event.put("packageName", sbn.getPackageName());
            event.put("title", title);
            event.put("content", text);
            event.put("postTime", sbn.getPostTime());
            session.offer(event);
        } catch (Exception ignored) {}
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification sbn) {
        if (!isShared(this)) return;
        NotificationSession session = activeSession;
        if (session == null || session.isExpired()) return;

        if (getPackageName().equals(sbn.getPackageName())) return;
        Notification notification = sbn.getNotification();
        if (notification != null && (sbn.isOngoing() || (notification.flags & Notification.FLAG_ONGOING_EVENT) != 0)) {
            return;
        }

        try {
            JSONObject event = new JSONObject();
            event.put("event", "removed");
            event.put("key", sbn.getKey());
            event.put("packageName", sbn.getPackageName());
            event.put("postTime", System.currentTimeMillis());
            session.offer(event);
        } catch (Exception ignored) {}
    }
}
