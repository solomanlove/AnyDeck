package com.anydeck.helper;

import android.os.Process;

import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.List;
import java.util.concurrent.Executor;
import java.util.function.IntConsumer;

/** 封装版本敏感的 Hidden API；请求由当前设备进程持有，不使用 system_server 的全局 Shell 请求。 */
final class FoldableStateBridge {
    private final Object global;
    private final Class<?> requestClass;
    private final Method requestMethod;
    private final Method cancelMethod;
    private final Object callback;
    private final Executor callbackExecutor = Runnable::run;
    private volatile Object ownedRequest;
    private volatile int requestedState;

    FoldableStateBridge(IntConsumer onCanceled) throws Exception {
        exemptHiddenApis();
        Class<?> globalClass = Class.forName("android.hardware.devicestate.DeviceStateManagerGlobal");
        Method instance = globalClass.getDeclaredMethod("getInstance");
        instance.setAccessible(true);
        global = instance.invoke(null);
        if (global == null) throw new IllegalStateException("device_state_unavailable");
        requestClass = Class.forName("android.hardware.devicestate.DeviceStateRequest");
        Class<?> callbackClass = Class.forName(
                "android.hardware.devicestate.DeviceStateRequest$Callback");
        requestMethod = globalClass.getMethod("requestState", requestClass,
                Executor.class, callbackClass);
        cancelMethod = globalClass.getMethod("cancelStateRequest");
        callback = Proxy.newProxyInstance(callbackClass.getClassLoader(),
                new Class<?>[]{callbackClass}, (proxy, method, args) -> {
                    if ("onRequestCanceled".equals(method.getName()) && args != null
                            && args.length > 0 && ownedRequest == args[0]) {
                        ownedRequest = null;
                        onCanceled.accept(requestedState);
                    }
                    if ("hashCode".equals(method.getName())) return System.identityHashCode(proxy);
                    if ("equals".equals(method.getName())) return proxy == args[0];
                    if ("toString".equals(method.getName())) return "AnyDeckFoldableCallback";
                    return null;
                });
        // 初始化时只查询；不取消用户或其他工具已经建立的请求。
        FoldableStateSnapshot.read();
    }

    synchronized void request(int state) throws Exception {
        FoldableStateSnapshot snapshot = FoldableStateSnapshot.read();
        if (snapshot.active && snapshot.pid != Process.myPid()) {
            throw new IllegalStateException("external_override_active");
        }
        if (!supports(state)) throw new IllegalArgumentException("unsupported_state");
        Object builder = requestClass.getMethod("newBuilder", int.class).invoke(null, state);
        // 用户实际折叠/展开设备时释放手动模式，让硬件状态重新接管。
        builder.getClass().getMethod("setFlags", int.class).invoke(builder, 1);
        Object request = builder.getClass().getMethod("build").invoke(builder);
        Object previous = ownedRequest;
        int previousState = requestedState;
        ownedRequest = request;
        requestedState = state;
        try {
            requestMethod.invoke(global, request, callbackExecutor, callback);
        } catch (Exception error) {
            ownedRequest = previous;
            requestedState = previousState;
            throw error;
        }
    }

    /** reset 是幂等操作；外部请求接管后绝不向系统发送全局 cancel。 */
    synchronized boolean reset() throws Exception {
        if (ownedRequest == null) return false;
        FoldableStateSnapshot snapshot = FoldableStateSnapshot.read();
        if (!snapshot.active || snapshot.pid != Process.myPid()) {
            ownedRequest = null;
            return false;
        }
        cancelMethod.invoke(global);
        ownedRequest = null;
        return true;
    }

    boolean ownsRequest() {
        return ownedRequest != null;
    }

    private boolean supports(int state) throws Exception {
        try {
            Method method = global.getClass().getMethod("getSupportedDeviceStates");
            for (Object candidate : (List<?>) method.invoke(global)) {
                Object identifier = candidate.getClass().getMethod("getIdentifier").invoke(candidate);
                if (((Number) identifier).intValue() == state) return true;
            }
        } catch (NoSuchMethodException ignored) {
            int[] states = (int[]) global.getClass().getMethod("getSupportedStates").invoke(global);
            for (int candidate : states) if (candidate == state) return true;
        }
        return false;
    }

    private static void exemptHiddenApis() throws Exception {
        Method forName = Class.class.getDeclaredMethod("forName", String.class);
        Method declaredMethod = Class.class.getDeclaredMethod("getDeclaredMethod", String.class,
                Class[].class);
        Class<?> runtimeClass = (Class<?>) forName.invoke(null, "dalvik.system.VMRuntime");
        Object runtime = ((Method) declaredMethod.invoke(runtimeClass, "getRuntime", null)).invoke(null);
        Method exempt = (Method) declaredMethod.invoke(runtimeClass, "setHiddenApiExemptions",
                new Class<?>[]{String[].class});
        exempt.invoke(runtime, new Object[]{new String[]{"Landroid/hardware/devicestate/"}});
    }
}
