package com.adbmanage.companion;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.os.Process;
import org.json.JSONArray;
import org.json.JSONObject;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

/** 手机端离线历史；两个流分别递增编号，导出不删除，保留最近 7 天。 */
public final class CompanionStore extends SQLiteOpenHelper {
    private static CompanionStore instance;
    private final Context context;

    public static synchronized CompanionStore get(Context context) {
        if (instance == null) instance = new CompanionStore(context.getApplicationContext());
        return instance;
    }

    private CompanionStore(Context context) {
        super(context, "companion.db", null, 1);
        this.context = context;
        setWriteAheadLoggingEnabled(true);
    }

    @Override public void onCreate(SQLiteDatabase db) {
        for (String table : new String[]{"usage_records", "location_records"}) {
            db.execSQL("CREATE TABLE " + table + " (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                    + "recorded_at INTEGER NOT NULL, payload TEXT NOT NULL)");
        }
    }

    @Override public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        throw new IllegalStateException("Unknown schema migration");
    }

    public static synchronized String installationId(Context context) {
        android.content.SharedPreferences prefs = context.getSharedPreferences("usage", 0);
        String id = prefs.getString("installId", null);
        if (id == null) {
            id = UUID.randomUUID().toString();
            if (!prefs.edit().putString("installId", id).commit()) {
                throw new IllegalStateException("Identity persistence failed");
            }
        }
        return id;
    }

    private String table(String kind) {
        if (!kind.equals("usage") && !kind.equals("location")) throw new IllegalArgumentException();
        return kind + "_records";
    }

    public synchronized void append(String kind, JSONObject payload) {
        String encoded = payload.toString();
        if (encoded.getBytes(StandardCharsets.UTF_8).length > 96 * 1024) {
            throw new IllegalArgumentException("Record too large");
        }
        long now = System.currentTimeMillis();
        SQLiteDatabase db = getWritableDatabase();
        db.beginTransaction();
        try {
            ContentValues values = new ContentValues();
            values.put("recorded_at", now);
            values.put("payload", encoded);
            long id = db.insertOrThrow(table(kind), null, values);
            db.delete(table(kind), "recorded_at < ? OR id <= ?", new String[]{
                    Long.toString(now - 7L * 86400000), Long.toString(id - 10000)});
            db.setTransactionSuccessful();
        } finally { db.endTransaction(); }
    }

    /** upperBound 固定本轮导出的上界；每页最多 100 行和约 128 KiB JSON。 */
    public synchronized JSONObject page(String kind, long after, long upperBound) throws Exception {
        SQLiteDatabase db = getReadableDatabase();
        String table = table(kind);
        long first = 0, last = 0;
        try (Cursor cursor = db.rawQuery("SELECT MIN(id), MAX(id) FROM " + table, null)) {
            if (cursor.moveToFirst()) { first = cursor.getLong(0); last = cursor.getLong(1); }
        }
        if (after < 0 || upperBound < 0 || after > last) {
            return new JSONObject().put("status", "cursor_invalid");
        }
        long until = upperBound == 0 ? last : Math.min(upperBound, last);
        if (after > until) return new JSONObject().put("status", "cursor_invalid");
        JSONArray records = new JSONArray();
        int size = 0;
        long next = after;
        try (Cursor cursor = db.rawQuery("SELECT id, recorded_at, payload FROM " + table
                + " WHERE id > ? AND id <= ? ORDER BY id LIMIT 100", new String[]{
                Long.toString(after), Long.toString(until)})) {
            while (cursor.moveToNext()) {
                String payload = cursor.getString(2);
                int bytes = payload.getBytes(StandardCharsets.UTF_8).length;
                if (records.length() > 0 && size + bytes > 128 * 1024) break;
                records.put(new JSONObject().put("id", cursor.getLong(0))
                        .put("recordedAtMs", cursor.getLong(1))
                        .put("data", new JSONObject(payload)));
                size += bytes;
                next = cursor.getLong(0);
            }
        }
        if (records.length() == 0) next = until;
        return new JSONObject().put("status", "ok").put("schemaVersion", 2)
                .put("kind", kind).put("installationId", installationId(context))
                .put("androidUserId", Process.myUid() / 100000)
                .put("firstAvailableId", first).put("after", after)
                .put("upperBound", until).put("nextCursor", next)
                .put("hasMore", next < until).put("records", records);
    }
}
