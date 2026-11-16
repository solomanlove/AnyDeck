package com.anydeck.helper;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** 通过只读 dumpsys 确认 override 所属 PID，避免清理时取消其他工具的请求。 */
final class FoldableStateSnapshot {
    private static final Pattern ACTIVE = Pattern.compile("Override Request active:\\s*(true|false)");
    private static final Pattern PID = Pattern.compile("Request:\\s*mPid=(\\d+)");
    final boolean active;
    final int pid;

    private FoldableStateSnapshot(boolean active, int pid) {
        this.active = active;
        this.pid = pid;
    }

    static FoldableStateSnapshot parse(String output) {
        Matcher status = ACTIVE.matcher(output);
        if (status.find()) {
            if ("false".equals(status.group(1))) return new FoldableStateSnapshot(false, -1);
            Matcher owner = PID.matcher(output);
            if (owner.find()) return new FoldableStateSnapshot(true, Integer.parseInt(owner.group(1)));
            throw new IllegalStateException("override_owner_unreadable");
        }
        if (!output.contains("Override Request active: true")
                && output.contains("mOverrideState=Optional.empty")) {
            return new FoldableStateSnapshot(false, -1);
        }
        throw new IllegalStateException("override_owner_unreadable");
    }

    static FoldableStateSnapshot read() throws Exception {
        java.lang.Process process = new ProcessBuilder("dumpsys", "device_state")
                .redirectErrorStream(true).start();
        FutureTask<String> reader = new FutureTask<>(() -> {
            try (InputStream input = process.getInputStream();
                    ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[4096];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (output.size() + count > 131072) {
                        throw new IllegalStateException("device_state_dump_too_large");
                    }
                    output.write(buffer, 0, count);
                }
                return new String(output.toByteArray(), StandardCharsets.UTF_8);
            }
        });
        Thread thread = new Thread(reader, "anydeck-foldable-snapshot");
        thread.setDaemon(true);
        thread.start();
        try {
            String output = reader.get(3, TimeUnit.SECONDS);
            if (!process.waitFor(1, TimeUnit.SECONDS) || process.exitValue() != 0) {
                throw new IllegalStateException("device_state_dump_failed");
            }
            return parse(output);
        } finally {
            reader.cancel(true);
            process.destroy();
            if (process.isAlive()) process.destroyForcibly();
        }
    }
}
