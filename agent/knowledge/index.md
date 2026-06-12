# Knowledge Index (AI 需求与知识库索引)

本索引用于管理 AdbManage 项目内已实现的需求与业务机制知识库 (Knowledge)。所有的 AI 助手在进行二次开发或优化相关需求前，应根据本索引的指引，优先调取对应模块的知识库文档。

## 知识库列表

### 1. 业务与机制知识 (Business & Mechanisms)

| Knowledge | 中文名 | 状态 | 用途 | 关联模块 |
| --- | --- | --- | --- | --- |
| `adb-cert-management` | 证书管理机制 | active | 记录用户证书与系统证书（Root 权限，包含 Android 10+ 内存挂载与 Conscrypt APEX 挂载）的导入机制与 adb 命令设计 | `control/` (控制面板) |
| `adb-tabs-features-principles` | 各 Tab 功能与实现原理指南 | active | 梳理概览、控制、应用、文件、日志、终端、进程、网页调试、布局分析、性能监控、网络/端口转发等 12 个 Tab 页的功能设计与底层 ADB 命令及系统级原理 | `dashboard/` (主面板各 Tab) |

## 新增知识库规则
每次新增的需求或重大功能迭代，在开发完成后均必须将其技术设计、关键实现与命令机制以知识文档的形式沉淀在 `agent/knowledge/` 目录下，并在此索引中进行登记。
