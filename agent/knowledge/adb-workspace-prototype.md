# 小米 17 工作台交互原型

## 范围与证据

2026-11-01 根据用户要求，控制已运行的 AnyDeck，采集小米 17 工作台 12 个入口及应用详情、控制更多设置，共 14 张 PNG。没有修改 Flutter 业务代码或重新安装 App。原型为 `prototype/interactive` 独立 React/Vinext Git 仓库，不属于 Flutter 构建资源。

本地参考图集：`prototype/interactive/reference/xiaomi17/index.html`。实际 PNG 与索引同目录，已在原型仓忽略，不能作为公开站点资源；图集索引提交不会把截图提交。Web 调试无目标、截图黑屏、消息未监听均为真实采集状态。布局展开截图未成功取得：操作时原窗口变为不可访问，未再启动第二个实例。

## 原型组织

- `components/prototype/workspace/workspace-model.ts`：演示数据、页面元数据及纯逻辑。
- `workspace-ui.tsx` / `workspace.css`：共享面板、分段控件、弹窗、空状态、主题变量和响应式布局。
- `device-workspace.tsx`：Android 工作台入口；其他平台继续走原型已有页面。
- `overview-control.tsx`、`apps-files.tsx`、`debug-pages.tsx`、`capture-network.tsx`：按任务域拆分 UI 与交互。
- 详细页面映射、设计规格、运行与验收边界见 `prototype/interactive/docs/xiaomi17-workspace-redesign.md`。

## 导航和状态

工作台包含概览、控制、应用、进程、文件、日志、终端、Web 调试、截图录屏、性能、网络、消息。应用详情保留十种信息标签。布局归入截图录屏，与实际项目的[合并机制](adb-screenshot-layout-merge.md)一致。

侧栏全局品牌、手机身份和底部功能固定，设备工具区域独立滚动；正文切页回顶。沿用原型已有控制台底部入口与模拟器全局入口。注意正式 Flutter 控制台是底部 Dock，原型仍为全页呈现，不能反向覆盖[正式导航机制](adb-main-window-navigation.md)。

所有数据/操作都是本地演示；没有设备通信层。局部交互状态离开主工具页或刷新即重置，设备资料编辑沿用已有流程弹窗。截图画布、录屏、性能曲线和通知不等于真实设备采集。真实序列号不写入演示设备 fixture。未重新引入设备密码/凭据。

## 验证与后续实施

原型命令：`npm test`、`npx tsc --noEmit --incremental false`、`npm run build`、`git diff --check`。

浏览器已逐一切换十二个工具入口；验证应用搜索和十个详情标签、录屏时布局切换拦截、停止后节点属性切换、非法端口和重复监听规则拦截。测试与构建只证明原型，不代表真机功能已实现或所有子弹窗已验收。

后续必须先逐页评审并补齐高保真稿、平台能力和异常状态，再进入 Flutter 实施。不能直接将原型提示反馈替代真实命令执行结果、权限验证或异步任务生命周期。
