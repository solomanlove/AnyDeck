package com.anydeck.helper;

import android.os.SystemClock;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.io.RandomAccessFile;
import java.nio.channels.FileLock;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * AnyDeck 折叠屏会话入口：通过 JSON 行请求状态，并在断连或心跳超时后释放自身请求。
 * 由 app_process 启动，stdin 支持 state、reset、ping、close；stdout 仅输出 JSON 行。
 */
public final class FoldableScreenHelper {
    private static final long HEARTBEAT_TIMEOUT_MS = 12000;
    private static final int MAX_LINE_LENGTH = 4096;
    private final AtomicBoolean closed = new AtomicBoolean();
    private volatile long lastContact = SystemClock.elapsedRealtime();
    private RandomAccessFile lockFile;
    private FileLock deviceLock;
    private FoldableStateBridge bridge;

    public static void main(String[] args) {
        FoldableScreenHelper helper = new FoldableScreenHelper();
        int result = 0;
        try {
            helper.run();
        } catch (Throwable error) {
            JSONObject failure = failure(null, error);
            try {
                failure.put("ready", false).put("version", 1);
            } catch (Exception ignored) {
                // 固定字段不包含不可序列化的数据。
            }
            emit(failure);
            result = 1;
        } finally {
            helper.close("eof");
        }
        // Binder 回调线程不会随 stdin 结束，必须显式结束 app_process。
        System.exit(result);
    }

    private void run() throws Exception {
        File directory = new File("/data/local/tmp/anydeck");
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IllegalStateException("lock_directory_unavailable");
        }
        lockFile = new RandomAccessFile(new File(directory, "foldable-screen.lock"), "rw");
        deviceLock = lockFile.getChannel().tryLock();
        if (deviceLock == null) {
            throw new IllegalStateException("device_busy");
        }
        bridge = new FoldableStateBridge(state -> {
            try {
                emit(new JSONObject().put("event", "canceled").put("state", state));
            } catch (Exception error) {
                System.err.println("AnyDeck foldable callback failed: " + error);
            }
        });
        lastContact = SystemClock.elapsedRealtime();
        Runtime.getRuntime().addShutdownHook(new Thread(() -> close("shutdown")));
        Thread watchdog = new Thread(() -> {
            try {
                while (!closed.get()) {
                    Thread.sleep(1000);
                    if (SystemClock.elapsedRealtime() - lastContact >= HEARTBEAT_TIMEOUT_MS) {
                        close("heartbeat_timeout");
                        System.exit(0);
                    }
                }
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
        }, "anydeck-foldable-watchdog");
        watchdog.setDaemon(true);
        watchdog.start();
        emit(new JSONObject().put("ready", true).put("version", 1)
                .put("pid", android.os.Process.myPid()));
        BufferedReader input = new BufferedReader(new InputStreamReader(
                System.in, StandardCharsets.UTF_8));
        String line;
        while (!closed.get() && (line = readLine(input)) != null) {
            Object id = null;
            try {
                JSONObject command = new JSONObject(line);
                id = command.get("id");
                if (!(id instanceof Number) || ((Number) id).doubleValue()
                        != ((Number) id).longValue()) {
                    throw new IllegalArgumentException("invalid_id");
                }
                String operation = command.getString("command");
                lastContact = SystemClock.elapsedRealtime();
                JSONObject response = new JSONObject().put("id", id).put("ok", true);
                switch (operation) {
                    case "state":
                        Object state = command.get("state");
                        if (!(state instanceof Number) || ((Number) state).doubleValue()
                                != ((Number) state).intValue()) {
                            throw new IllegalArgumentException("invalid_state");
                        }
                        bridge.request(((Number) state).intValue());
                        response.put("state", state);
                        break;
                    case "reset":
                        response.put("restored", bridge.reset());
                        break;
                    case "ping":
                        response.put("ownsRequest", bridge.ownsRequest());
                        break;
                    case "close":
                        response.put("restored", bridge.reset());
                        emit(response);
                        return;
                    default:
                        throw new IllegalArgumentException("unknown_command");
                }
                emit(response);
            } catch (Throwable error) {
                emit(failure(id, error));
            }
        }
    }

    /** 限制单行长度，避免异常客户端把常驻设备进程变成无界缓冲。 */
    private static String readLine(BufferedReader input) throws Exception {
        StringBuilder line = new StringBuilder();
        int value;
        while ((value = input.read()) != -1) {
            if (value == '\n') return line.toString();
            if (value != '\r') line.append((char) value);
            if (line.length() > MAX_LINE_LENGTH) {
                throw new IllegalArgumentException("command_too_long");
            }
        }
        return line.length() == 0 ? null : line.toString();
    }

    private void close(String reason) {
        if (!closed.compareAndSet(false, true)) return;
        try {
            if (bridge != null) bridge.reset();
        } catch (Throwable error) {
            System.err.println("AnyDeck foldable cleanup failed: " + message(error));
        } finally {
            try {
                if (deviceLock != null) deviceLock.release();
                if (lockFile != null) lockFile.close();
            } catch (Exception error) {
                System.err.println("AnyDeck foldable lock cleanup failed: " + error);
            }
        }
    }

    private static JSONObject failure(Object id, Throwable error) {
        JSONObject response = new JSONObject();
        try {
            response.put("id", id == null ? JSONObject.NULL : id);
            response.put("ok", false);
            response.put("error", message(error));
            response.put("code", errorCode(error));
        } catch (Exception ignored) {
            // 字段均来自固定结构，异常仅保留在最终退出路径。
        }
        return response;
    }

    private static String message(Throwable error) {
        while (error.getCause() != null) error = error.getCause();
        return error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
    }

    private static String errorCode(Throwable error) {
        while (error.getCause() != null) error = error.getCause();
        String message = message(error);
        if (error instanceof SecurityException || message.contains("Permission")) return "permission";
        if (message.equals("device_busy")) return "busy";
        if (message.equals("external_override_active")) return "external_override";
        if (message.equals("unsupported_state") || error instanceof ReflectiveOperationException
                || message.equals("device_state_unavailable")
                || message.equals("override_owner_unreadable")) return "unsupported";
        if (error instanceof IllegalArgumentException || message.startsWith("invalid_")
                || message.equals("unknown_command")) return "invalid_command";
        return "command_failed";
    }

    private static synchronized void emit(JSONObject response) {
        System.out.println(response.toString());
        System.out.flush();
    }
}
