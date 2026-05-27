package com.adbmanage.helper;

import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
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
                                    info.iconPath
                    );
                } catch (Throwable ignored) {
                    System.out.println(packageName + "\t\t");
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

        Resources resources = getResources(applicationInfo.sourceDir);
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

        return new PackageIconInfo(label, iconPath);
    }

    private PackageInfo getPackageInfo(String packageName) throws Exception {
        int flags = 0;
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

    private Resources getResources(String apkPath) throws Exception {
        AssetManager assetManager = AssetManager.class.newInstance();
        Method addAssetPathMethod = assetManager.getClass().getMethod("addAssetPath", String.class);
        addAssetPathMethod.invoke(assetManager, apkPath);

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

        private PackageIconInfo(String label, String iconPath) {
            this.label = label;
            this.iconPath = iconPath;
        }
    }
}
