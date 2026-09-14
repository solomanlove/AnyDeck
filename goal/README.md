# AnyDeck 跨平台底层架构重构与多端落地总纲

## 核心架构原则

> **Flutter 负责 UI 渲染与视图交互；Rust 负责底层系统交互、密集型计算与跨平台设备抽象。**

本项目旨在将 AnyDeck 从“依赖外部 CLI 子进程与 Dart 繁重解析”的模式，演进为以 **Rust 高性能原生核心** 为底座、**统一设备抽象层 (DAL)** 为纽带、支持 **Android / 鸿蒙 (HarmonyOS NEXT) / iOS** 三端并行的现代化跨平台桌面管理工作台。

---

## 知识库与计划文档索引

| 文档 | 名称 | 核心内容 |
| :--- | :--- | :--- |
| [01_platform_goals.md](./01_platform_goals.md) | **三端目标愿景与能力矩阵** | 安卓（性能零拷贝/融合模式）、鸿蒙（HDC 管道/投屏）、iOS（投屏/蓝牙HID反控/WDA）及批量自动化目标 |
| [02_implementation_plan.md](./02_implementation_plan.md) | **详细落地实施计划** | 分阶段演进路线（Phase 1 ~ Phase 4）、里程碑、任务拆解与量化验收指标 |
| [03_core_architecture_principles.md](./03_core_architecture_principles.md) | **核心技术架构与原理解析** | Direct ADB Socket、零拷贝解析数学公式、DAL 抽象 Trait、Android 14 虚拟屏原理、iOS 蓝牙 HID 协议 |
| [04_technical_flowcharts.md](./04_technical_flowcharts.md) | **技术时序图与交互流程图** | 性能采样时序、Tokio 批量限流、Android 14 融合模式生命周期、iOS 投屏与反控时序 |

---

## 核心收益预期

1. **宿主机系统内存大幅降低**：规避频繁的子进程创建与 Dart 堆内存膨胀，性能监控常驻内存降低 80%+。
2. **软件运行更快更丝滑**：消除 Dart VM 周期性 GC 造成的丢帧，所有密集型字符解析原地零拷贝完成。
3. **更统一的跨平台调用**：上层 Flutter 仅面对统一的 `DeviceDriver` API，彻底屏蔽底层 Android、鸿蒙与 iOS 的协议异构性。
