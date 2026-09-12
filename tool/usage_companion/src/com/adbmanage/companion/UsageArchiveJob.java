package com.adbmanage.companion;

import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** 用户明确启用后由系统调度保存统计；15 分钟是请求周期，不保证准点。 */
public final class UsageArchiveJob extends JobService {
    private static final int JOB_ID = 4101;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    public static void schedule(Context context) {
        UsageRepository repository = new UsageRepository(context);
        JobScheduler scheduler = context.getSystemService(JobScheduler.class);
        boolean enabled = repository.preferences().getBoolean("usageAuto", false)
                && repository.status().equals("ok");
        if (!enabled) { scheduler.cancel(JOB_ID); return; }
        if (scheduler.getPendingJob(JOB_ID) != null) return;
        scheduler.schedule(new JobInfo.Builder(JOB_ID,
                new ComponentName(context, UsageArchiveJob.class))
                .setPeriodic(15 * 60000L).setPersisted(false).build());
    }

    @Override public boolean onStartJob(JobParameters params) {
        worker.execute(() -> {
            UsageRepository repository = new UsageRepository(this);
            if (repository.preferences().getBoolean("usageAuto", false)) {
                try { repository.snapshot(); } catch (Exception ignored) { }
            }
            jobFinished(params, false);
        });
        return true;
    }

    @Override public boolean onStopJob(JobParameters params) { return false; }
    @Override public void onDestroy() { worker.shutdownNow(); super.onDestroy(); }
}
