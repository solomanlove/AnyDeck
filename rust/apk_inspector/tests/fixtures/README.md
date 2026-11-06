# Android 包格式测试样本

这些小型样本由 Android Build Tools 36.0.0 的 AAPT2 从本目录 XML 生成，用于 AnyDeck 离线解析测试；测试运行时不依赖 SDK 或 Java。样本不含第三方 App 代码。

- `base-manifest.axml` / `split-manifest.axml`：分别来自 `base.xml` / `split.xml` 的二进制 Manifest。
- `base-manifest.pb` / `feature-manifest.pb`：上述 APK 经 `aapt2 convert --output-format proto` 转换后的 Manifest。
- `resource-manifest.pb` / `resources.pb`：`resource.xml` 配合字符串资源 `test_name = AnyDeck 容器测试`，使用 `aapt2 link --proto-format` 生成，用于验证 AAB 资源引用和中文字符串。

生成步骤（路径按开发机 SDK 调整）：

```bash
aapt2 link -I android.jar --manifest base.xml -o base.apk
aapt2 convert --output-format proto -o base-proto.apk base.apk
# 从 APK 中提取 AndroidManifest.xml；resource.xml 还需 compile 对应 values/strings.xml。
```

Rust 测试将这些 Manifest 与少量模拟 DEX/SO 字节写入临时归档，覆盖 APKS、XAPK、AAB 的元数据与清单分析；模拟 DEX/SO 不用于验证反编译或实际安装。
