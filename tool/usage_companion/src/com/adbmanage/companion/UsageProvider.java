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

/** 仅向 ADB shell 提供用户已开启的使用统计，不允许普通 App 调用。 */
public final class UsageProvider extends ContentProvider {
    private UsageRepository repository;

    @Override public boolean onCreate() {
        repository = new UsageRepository(getContext());
        return true;
    }

    @Override public Bundle call(String method, String arg, Bundle extras) {
        // ContentProvider.call 必须自行鉴权，不能只依赖 manifest 的读写权限。
        if (Binder.getCallingUid() != 2000) throw new SecurityException("ADB shell only");
        if (!"snapshot".equals(method)) throw new IllegalArgumentException("Unknown method");
        long identity = Binder.clearCallingIdentity();
        try {
            JSONObject payload;
            try {
                payload = repository.snapshot();
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

    @Override public Cursor query(Uri uri, String[] projection, String selection,
            String[] selectionArgs, String sortOrder) { throw new UnsupportedOperationException(); }
    @Override public String getType(Uri uri) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) {
        throw new UnsupportedOperationException();
    }
}
