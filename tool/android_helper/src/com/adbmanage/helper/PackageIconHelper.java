package com.adbmanage.helper;

import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.Signature;
import java.security.MessageDigest;
import android.content.res.AssetManager;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.os.IBinder;
import android.util.Base64;
import android.util.DisplayMetrics;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileReader;
import java.lang.reflect.Method;

public final class PackageIconHelper {
    private static final String ICON_CACHE_DIR = "/data/local/tmp/adb_manage/icons";

    static {
        try {
            Method forName = Class.class.getDeclaredMethod("forName", String.class);
            Method getDeclaredMethod = Class.class.getDeclaredMethod("getDeclaredMethod", String.class, Class[].class);
            Class<?> vmRuntimeClass = (Class<?>) forName.invoke(null, "dalvik.system.VMRuntime");
            Method getRuntime = (Method) getDeclaredMethod.invoke(vmRuntimeClass, "getRuntime", null);
            Object vmRuntime = getRuntime.invoke(null);
            Method setHiddenApiExemptions = (Method) getDeclaredMethod.invoke(vmRuntimeClass, "setHiddenApiExemptions", new Class[]{String[].class});
            setHiddenApiExemptions.invoke(vmRuntime, new Object[]{new String[]{"L"}});
        } catch (Throwable e) {
            // Ignore if it fails
        }
    }

    public static void main(String[] args) {
        if (args.length < 2) {
            System.err.println("Usage: PackageIconHelper <package-file> <user-id>");
            return;
        }

        try {
            new PackageIconHelper(Integer.parseInt(args[1])).run(args[0]);
        } catch (Throwable throwable) {
            throwable.printStackTrace(System.err);
        }
    }

    private final Object packageManager;
    private final Method getPackageInfoMethod;
    private final int userId;

    private PackageIconHelper(int userId) throws Exception {
        this.userId = userId;
        Class<?> serviceManagerClass = Class.forName("android.os.ServiceManager");
        Method getServiceMethod = serviceManagerClass.getMethod("getService", String.class);
        IBinder packageBinder = (IBinder) getServiceMethod.invoke(null, "package");

        Class<?> stubClass = Class.forName("android.content.pm.IPackageManager$Stub");
        Method asInterfaceMethod = stubClass.getMethod("asInterface", IBinder.class);
        packageManager = asInterfaceMethod.invoke(null, packageBinder);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getPackageInfoMethod = packageManager.getClass().getMethod(
                    "getPackageInfo",
                    String.class,
                    long.class,
                    int.class
            );
        } else {
            getPackageInfoMethod = packageManager.getClass().getMethod(
                    "getPackageInfo",
                    String.class,
                    int.class,
                    int.class
            );
        }
    }

    private void run(String packageFilePath) throws Exception {
        File iconDir = new File(ICON_CACHE_DIR);
        if (!iconDir.exists()) {
            iconDir.mkdirs();
        }

        try (BufferedReader reader = new BufferedReader(new FileReader(packageFilePath))) {
            String packageName;
            while ((packageName = reader.readLine()) != null) {
                packageName = packageName.trim();
                if (packageName.isEmpty()) {
                    continue;
                }
                try {
                    PackageIconInfo info = readPackageIconInfo(packageName);
                    System.out.println(
                            packageName + "\t" +
                                    base64(info.label) + "\t" +
                                    info.iconPath + "\t" +
                                    info.signatureMd5 + "\t" +
                                    info.firstInstallTime + "\t" +
                                    info.lastUpdateTime
                    );
                } catch (Throwable ignored) {
                    System.out.println(packageName + "\t\t\t\t");
                }
            }
        }
    }

    private PackageIconInfo readPackageIconInfo(String packageName) throws Exception {
        PackageInfo packageInfo = getPackageInfo(packageName);
        ApplicationInfo applicationInfo = packageInfo.applicationInfo;
        File apkFile = new File(applicationInfo.sourceDir);

        String label = packageName;
        if (applicationInfo.nonLocalizedLabel != null) {
            label = applicationInfo.nonLocalizedLabel.toString();
        }

        Resources resources = getResources(applicationInfo);
        if (applicationInfo.labelRes != 0) {
            try {
                label = resources.getString(applicationInfo.labelRes);
            } catch (Throwable ignored) {
                // Keep package name or nonLocalizedLabel fallback.
            }
        }

        String iconPath = "";
        if (applicationInfo.icon != 0) {
            String cacheKey = packageName + "." + apkFile.length() + "." + apkFile.lastModified();
            File iconFile = new File(ICON_CACHE_DIR, cacheKey + ".png");
            if (!iconFile.exists()) {
                Drawable drawable = resources.getDrawable(applicationInfo.icon);
                Bitmap bitmap = drawableToBitmap(drawable);
                iconFile.getParentFile().mkdirs();
                iconFile.createNewFile();
                java.io.FileOutputStream outputStream = new java.io.FileOutputStream(iconFile);
                outputStream.write(bitmapToPng(bitmap));
                outputStream.close();
            }
            iconPath = iconFile.getAbsolutePath();
        }

        String signatureMd5 = getSignatureMd5(packageInfo);
        long firstInstallTime = packageInfo.firstInstallTime;
        long lastUpdateTime = packageInfo.lastUpdateTime;

        return new PackageIconInfo(label, iconPath, signatureMd5, firstInstallTime, lastUpdateTime);
    }

    private String getSignatureMd5(PackageInfo packageInfo) {
        try {
            Signature[] signatures = packageInfo.signatures;
            if (signatures == null || signatures.length == 0) {
                return "";
            }
            byte[] certBytes = signatures[0].toByteArray();
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] digest = md.digest(certBytes);
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (Throwable ignored) {
            return "";
        }
    }

    private PackageInfo getPackageInfo(String packageName) throws Exception {
        int flags = 64; // PackageManager.GET_SIGNATURES
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return (PackageInfo) getPackageInfoMethod.invoke(
                    packageManager,
                    packageName,
                    (long) flags,
                    userId
            );
        }
        return (PackageInfo) getPackageInfoMethod.invoke(
                packageManager,
                packageName,
                flags,
                userId
        );
    }

    private Resources getResources(ApplicationInfo applicationInfo) throws Exception {
        AssetManager assetManager = AssetManager.class.newInstance();
        Method addAssetPathMethod = assetManager.getClass().getMethod("addAssetPath", String.class);
        if (new File("/system/framework/framework-res.apk").exists()) {
            addAssetPathMethod.invoke(assetManager, "/system/framework/framework-res.apk");
        }
        addAssetPathMethod.invoke(assetManager, applicationInfo.sourceDir);
        if (applicationInfo.splitSourceDirs != null) {
            for (String splitDir : applicationInfo.splitSourceDirs) {
                addAssetPathMethod.invoke(assetManager, splitDir);
            }
        }

        DisplayMetrics displayMetrics = new DisplayMetrics();
        displayMetrics.setToDefaults();
        Configuration configuration = new Configuration();
        configuration.setToDefaults();
        return new Resources(assetManager, displayMetrics, configuration);
    }

    private Bitmap drawableToBitmap(Drawable drawable) {
        int width = drawable.getIntrinsicWidth();
        int height = drawable.getIntrinsicHeight();
        if (width <= 0) {
            width = 96;
        }
        if (height <= 0) {
            height = 96;
        }
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        bitmap.setHasAlpha(true);
        Canvas canvas = new Canvas(bitmap);
        drawable.setBounds(0, 0, width, height);
        drawable.draw(canvas);
        return bitmap;
    }

    private byte[] bitmapToPng(Bitmap bitmap) {
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream);
        return stream.toByteArray();
    }

    private String base64(String value) {
        return Base64.encodeToString(value.getBytes(), Base64.NO_WRAP);
    }

    private static final class PackageIconInfo {
        private final String label;
        private final String iconPath;
        private final String signatureMd5;
        private final long firstInstallTime;
        private final long lastUpdateTime;

        private PackageIconInfo(String label, String iconPath, String signatureMd5, long firstInstallTime, long lastUpdateTime) {
            this.label = label;
            this.iconPath = iconPath;
            this.signatureMd5 = signatureMd5;
            this.firstInstallTime = firstInstallTime;
            this.lastUpdateTime = lastUpdateTime;
        }
    }
}
