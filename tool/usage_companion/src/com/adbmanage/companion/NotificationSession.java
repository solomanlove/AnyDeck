package com.adbmanage.companion;

import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;

/**
 * 手机端通知转发会话有界内存队列。
 * 限制队列最多 1000 条且不超过 2 MiB，10 秒未续租即视为超时失效。
 */
public final class NotificationSession {
    public static final long LEASE_TIMEOUT_MS = 10000; // 10秒
    public static final int MAX_ITEMS = 1000;
    public static final long MAX_BYTES = 2 * 1024 * 1024; // 2 MiB

    private final String sessionId;
    private long lastLeaseTime;
    private long nextSequence = 1;
    private long currentBytes = 0;
    private boolean gap = false;

    private static class QueueItem {
        final long sequence;
        final JSONObject event;
        final int byteSize;

        QueueItem(long sequence, JSONObject event, int byteSize) {
            this.sequence = sequence;
            this.event = event;
            this.byteSize = byteSize;
        }
    }

    private final LinkedList<QueueItem> queue = new LinkedList<>();

    public NotificationSession(String sessionId) {
        this.sessionId = sessionId;
        this.lastLeaseTime = System.currentTimeMillis();
    }

    public synchronized String getSessionId() {
        return sessionId;
    }

    public synchronized boolean isExpired() {
        return (System.currentTimeMillis() - lastLeaseTime) > LEASE_TIMEOUT_MS;
    }

    public synchronized void renew() {
        this.lastLeaseTime = System.currentTimeMillis();
    }

    public synchronized void offer(JSONObject event) {
        if (isExpired()) return;

        int bytes = event.toString().length() * 2; // UTF-16 字节粗估
        long seq = nextSequence++;
        try {
            event.put("sequence", seq);
        } catch (Exception ignored) {}

        queue.addLast(new QueueItem(seq, event, bytes));
        currentBytes += bytes;

        // 超过 1000 条或 2 MiB 时丢弃队头并标记缺口
        while (queue.size() > MAX_ITEMS || currentBytes > MAX_BYTES) {
            QueueItem removed = queue.removeFirst();
            currentBytes -= removed.byteSize;
            gap = true;
        }
    }

    public synchronized JSONObject poll(long afterCursor, int limit) {
        renew();
        JSONObject result = new JSONObject();
        JSONArray events = new JSONArray();
        long highest = afterCursor;

        List<QueueItem> snapshot = new ArrayList<>(queue);
        int count = 0;
        boolean hasMore = false;

        for (QueueItem item : snapshot) {
            if (item.sequence > afterCursor) {
                if (count < limit) {
                    events.put(item.event);
                    highest = Math.max(highest, item.sequence);
                    count++;
                } else {
                    hasMore = true;
                    break;
                }
            }
        }

        try {
            result.put("status", "ok");
            result.put("sessionId", sessionId);
            result.put("nextCursor", highest);
            result.put("events", events);
            result.put("hasMore", hasMore);
            result.put("gap", gap);
        } catch (Exception ignored) {}

        // 上报过缺口后复位
        if (gap) {
            gap = false;
        }

        return result;
    }

    public synchronized void clear() {
        queue.clear();
        currentBytes = 0;
        gap = false;
    }
}
