package com.adbmanage.companion;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Bundle;
import android.util.Base64;
import org.json.JSONObject;
import java.nio.charset.StandardCharsets;

/** 仅向 ADB shell 提供用户已开启共享的统计和位置历史，不允许普通 App 调用。 */
public final class UsageProvider extends ContentProvider {
    private UsageRepository repository;

    @Override public boolean onCreate() {
        repository = new UsageRepository(getContext());
        return true;
    }

    @Override public Bundle call(String method, String arg, Bundle extras) {
        // ContentProvider.call 必须自行鉴权，不能只依赖 manifest 的读写权限。
        if (Binder.getCallingUid() != 2000) throw new SecurityException("ADB shell only");
        long identity = Binder.clearCallingIdentity();
        try {
            JSONObject payload;
            try {
                payload = handle(method, arg);
            } catch (Exception error) {
                payload = new JSONObject();
                try { payload.put("status", "internal_error"); } catch (Exception ignored) { }
            }
            Bundle reply = new Bundle();
            reply.putString("payload", Base64.encodeToString(
                    payload.toString().getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP));
            return reply;
        } finally {
            Binder.restoreCallingIdentity(identity);
        }
    }

    private JSONObject handle(String method, String arg) throws Exception {
        if (!getContext().getSystemService(android.os.UserManager.class).isUserUnlocked()) {
            return new JSONObject().put("status", "user_locked");
        }
        if ("notification_status".equals(method)) {
            boolean sharing = NotificationForwardingService.isShared(getContext());
            boolean permission = NotificationForwardingService.isPermissionGranted(getContext());
            String notifStatus = !sharing ? "sharing_disabled" : !permission ? "permission_required" : "ok";
            return new JSONObject()
                    .put("status", notifStatus)
                    .put("sharing", sharing)
                    .put("permission", permission)
                    .put("installationId", CompanionStore.installationId(getContext()))
                    .put("androidUserId", android.os.Process.myUid() / 100000);
        }
        if ("notification_start_session".equals(method)) {
            if (!NotificationForwardingService.isShared(getContext())) {
                return new JSONObject().put("status", "sharing_disabled");
            }
            if (!NotificationForwardingService.isPermissionGranted(getContext())) {
                return new JSONObject().put("status", "permission_required");
            }
            String sessionId = NotificationForwardingService.startSession(getContext());
            return new JSONObject()
                    .put("status", "ok")
                    .put("sessionId", sessionId)
                    .put("installationId", CompanionStore.installationId(getContext()))
                    .put("androidUserId", android.os.Process.myUid() / 100000);
        }
        if ("notification_poll".equals(method)) {
            if (!NotificationForwardingService.isShared(getContext())) {
                return new JSONObject().put("status", "sharing_disabled");
            }
            if (!NotificationForwardingService.isPermissionGranted(getContext())) {
                return new JSONObject().put("status", "permission_required");
            }
            String[] parts = arg == null ? new String[]{"", "0"} : arg.split(":", -1);
            if (parts.length != 2) throw new IllegalArgumentException();
            String sessionId = parts[0];
            long cursor = Long.parseLong(parts[1]);
            JSONObject pollRes = NotificationForwardingService.pollEvents(getContext(), sessionId, cursor);
            pollRes.put("installationId", CompanionStore.installationId(getContext()));
            pollRes.put("androidUserId", android.os.Process.myUid() / 100000);
            return pollRes;
        }
        if ("notification_stop_session".equals(method)) {
            NotificationForwardingService.stopSession(getContext(), arg);
            return new JSONObject().put("status", "ok");
        }
        if ("snapshot".equals(method)) return repository.snapshot();
        boolean usage = "usage_history".equals(method);
        boolean location = "location_history".equals(method);
        if (!usage && !location && !"identity".equals(method)) throw new IllegalArgumentException();
        String status = usage ? repository.status() : LocationRecordingService.isShared(getContext())
                ? "ok" : "sharing_disabled";
        if ("identity".equals(method)) {
            if (!repository.preferences().getBoolean("sharing", false)
                    && !LocationRecordingService.isShared(getContext())
                    && !NotificationForwardingService.isShared(getContext())) {
                return new JSONObject().put("status", "sharing_disabled");
            }
            return new JSONObject().put("status", "ok").put("schemaVersion", 2)
                    .put("installationId", CompanionStore.installationId(getContext()))
                    .put("androidUserId", android.os.Process.myUid() / 100000);
        }
        if (!status.equals("ok")) return new JSONObject().put("status", status);
        String[] cursor = arg == null ? new String[]{"0", "0"} : arg.split(":", -1);
        if (cursor.length != 2) throw new IllegalArgumentException();
        JSONObject page = CompanionStore.get(getContext()).page(usage ? "usage" : "location",
                Long.parseLong(cursor[0]), Long.parseLong(cursor[1]));
        // 查询期间关闭共享时，不返回已经读出的历史。
        status = usage ? repository.status() : LocationRecordingService.isShared(getContext())
                ? "ok" : "sharing_disabled";
        if (!status.equals("ok")) return new JSONObject().put("status", status);
        page.put("recording", location && LocationRecordingService.running);
        return page;
    }

    @Override public Cursor query(Uri uri, String[] projection, String selection,
            String[] selectionArgs, String sortOrder) { throw new UnsupportedOperationException(); }
    @Override public String getType(Uri uri) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) {
        throw new UnsupportedOperationException();
    }
}
