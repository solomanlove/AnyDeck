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

/**
 * Android 端的辅助程序，用于通过 app_process 命令行执行来高效读取已安装应用的名称、图标缓存路径、签名 MD5 和安装升级时间等元数据。
 */
public final class PackageIconHelper {
    // 远程设备上的图标文件缓存根目录
    private static final String ICON_CACHE_DIR = "/data/local/tmp/adb_manage/icons";

    // 静态初始化块：解除 Android 9+ 对非公开 SDK (Hidden API) 反射调用的机制限制
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
            // 忽略失败以支持没有此 API 或未做限制的老旧 Android 系统版本
        }
    }

    /**
     * 辅助工具的命令行入口点
     * @param args 参数列表。args[0]：需要处理的包名文本文件路径；args[1]：目标用户 ID (User ID)
     */
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

    /**
     * 初始化助手类，反射获取 IPackageManager 接口的底层代理以绕过高级权限限制直接进行包查询
     */
    private PackageIconHelper(int userId) throws Exception {
        this.userId = userId;
        // 获取底层 ServiceManager 以拿到 package 服务的 Binder
        Class<?> serviceManagerClass = Class.forName("android.os.ServiceManager");
        Method getServiceMethod = serviceManagerClass.getMethod("getService", String.class);
        IBinder packageBinder = (IBinder) getServiceMethod.invoke(null, "package");

        // 将 Binder 转换为 IPackageManager 代理实例
        Class<?> stubClass = Class.forName("android.content.pm.IPackageManager$Stub");
        Method asInterfaceMethod = stubClass.getMethod("asInterface", IBinder.class);
        packageManager = asInterfaceMethod.invoke(null, packageBinder);

        // 根据不同的 Android SDK 版本自适应匹配 getPackageInfo 方法签名
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

    /**
     * 逐行读取包名并调用处理函数，以制表符分隔输出：[包名]\t[Base64编码的应用名称]\t[本地图标PNG路径]\t[签名MD5]\t[首次安装时间]\t[最后更新时间]
     * @param packageFilePath 包含待处理包名列表的文件路径
     */
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
                    // 当单个应用读取失败时输出空白列，不破坏后续的按行解析机制
                    System.out.println(packageName + "\t\t\t\t");
                }
            }
        }
    }

    /**
     * 核心逻辑：获取指定应用的信息，创建其独立的资源加载器(Resources)并提取应用名和图标并导出为缓存的 PNG 文件
     */
    private PackageIconInfo readPackageIconInfo(String packageName) throws Exception {
        PackageInfo packageInfo = getPackageInfo(packageName);
        ApplicationInfo applicationInfo = packageInfo.applicationInfo;
        File apkFile = new File(applicationInfo.sourceDir);

        // 默认将包名作为应用标签的兜底
        String label = packageName;
        if (applicationInfo.nonLocalizedLabel != null) {
            label = applicationInfo.nonLocalizedLabel.toString();
        }

        // 创建专用的资源加载器加载包括 Split APKs 在内的所有相关资源包
        Resources resources = getResources(applicationInfo);
        if (applicationInfo.labelRes != 0) {
            try {
                label = resources.getString(applicationInfo.labelRes);
            } catch (Throwable ignored) {
                // 读取失败时回退到已有的 label (nonLocalizedLabel 或包名)
            }
        }

        String iconPath = "";
        if (applicationInfo.icon != 0) {
            // 利用包名、APK 大小与修改时间合成唯一的缓存文件名以防止脏缓存
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

    /**
     * 计算应用签名证书的 MD5 值
     */
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

    /**
     * 通过反射调用 IPackageManager 代理的 getPackageInfo 方法获取对应的包数据
     */
    private PackageInfo getPackageInfo(String packageName) throws Exception {
        int flags = 64; // PackageManager.GET_SIGNATURES 标志位
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

    /**
     * 核心资源加载函数：动态创建一个专有的 AssetManager，并将宿主 framework、主 APK 以及其对应的所有 Split APKs 都加载进来，最后构建全新的 Resources 实例以保证资源引用的正确性
     */
    private Resources getResources(ApplicationInfo applicationInfo) throws Exception {
        AssetManager assetManager = AssetManager.class.newInstance();
        Method addAssetPathMethod = assetManager.getClass().getMethod("addAssetPath", String.class);
        
        // 可选加载 Android 框架系统资源文件，防止矢量资源或全局引用加载异常
        if (new File("/system/framework/framework-res.apk").exists()) {
            addAssetPathMethod.invoke(assetManager, "/system/framework/framework-res.apk");
        }
        
        // 加载主 APK 资源路径
        addAssetPathMethod.invoke(assetManager, applicationInfo.sourceDir);
        
        // 关键修复：循环加载应用的所有拆分 APK (Split APKs) 资源包以支持多 APK 部署的应用
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

    /**
     * 将 Drawable 实例渲染并转换成 Bitmap 内存实例
     */
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

    /**
     * 将 Bitmap 压缩编码为 PNG 格式的字节流
     */
    private byte[] bitmapToPng(Bitmap bitmap) {
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream);
        return stream.toByteArray();
    }

    /**
     * 对字符串进行 Base64 编码以防止控制字符或者中文制表符损坏标准输出流
     */
    private String base64(String value) {
        return Base64.encodeToString(value.getBytes(), Base64.NO_WRAP);
    }

    /**
     * 包图标信息的实体封装类
     */
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
