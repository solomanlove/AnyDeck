# AnyDeck 截图图片编辑

## 需求与使用路径

- 在截图录屏页右上角、布局分析开关左侧增加“编辑图片”。已有截图且非加载/录屏阶段时可进入。
- 当前工作区显示编辑工具栏与单画布，提供拖动画布、矩形、圆形/椭圆、画笔、马赛克、不透明遮盖、六种标注颜色和原图像素笔宽，以及撤销、重做、清空、取消、完成。
- 选择图形/画笔后按住鼠标左键绘制；使用“拖动画布”工具平移、触控板缩放，底栏始终提供缩放、1:1 和适应窗口。
- 完成后回到进入前的普通截图/布局分析模式，保存与复制均导出编辑后的 PNG；取消有标注的会话时先选择继续编辑或放弃，取消保留进入前的画面。
- 编辑时停止连续截图，完成/取消后保持暂停，防止新截图立即覆盖结果。手动重新截图成功后清除编辑结果；重新进入编辑以已完成的图片为新底图，上次会话的撤销历史不保留。

## 架构与改动范围

| 位置 | 职责 |
| --- | --- |
| `lib/features/screenshot/dashboard_screenshot_tab.dart` | 工作台模式切换，编辑时收起布局分析侧栏，完成或取消后恢复 |
| `widgets/screenshot_toolbar.dart` | 右上角编辑入口和加载/录屏禁用状态 |
| `widgets/screenshot_canvas.dart` | 复用 Viewer，附加随图片变换的 overlay，绘制时禁用 Viewer 手势 |
| `model/screenshot_state.dart` | 独立保存原始与编辑后的 PNG/Image，`displayImage`、`exportBytes` 优先取编辑结果 |
| `controller/screenshot_edit_session.dart` | 编辑互斥、冻结当前图、接管导出 Image、销毁清理 |
| `controller/screenshot_controller.dart` | 截图请求失效、连续截图暂停、刷新清除结果，保存/复制使用统一 exportBytes |
| `editor/model/` | 不可变标注/编辑状态，以及原图坐标逆旋转 |
| `editor/controller/` | 会话级 autoDispose Riverpod Notifier，工具样式、草稿、撤销与重做 |
| `editor/renderer/` | 预览与原分辨率 PNG 共用标注渲染器，马赛克纹理生成 |
| `editor/widgets/` | 工具栏、鼠标 overlay、持有图像资源的编辑工作区 |

不增加依赖、设备命令、常驻进程、独立窗口或跨 Isolate 通信。Android、HarmonyOS、iOS 获取的 PNG 使用相同编辑链路，投屏 Texture 和输入映射不参与。

## 坐标、像素与导出约定

- 标注点与线宽全部使用未旋转原图的像素坐标；Overlay 位于 InteractiveViewer 的图片子节点中，PointerEvent.localPosition 已反向应用缩放和平移，再按现有画布旋转中心逆旋转到原图。
- 若图片尺寸为 \((W,H)\)，旋转后包围盒为 \((W_r,H_r)\)，局部坐标为 \(p\)，原图坐标为：

  \[
  p_{image}=R(-\theta)\left(p-(W_r/2,H_r/2)\right)+(W/2,H/2)
  \]

- 绘制点裁剪到原图边界，矩形/椭圆支持反向拖动；画笔单击可留下圆点，单次落笔对应一次撤销。
- 旋转沿用现有预览行为，导出保持原图方向、原始宽高，不包含编辑工具栏、布局高亮或窗口 DPR 缩放。工具栏提供方向说明 Tooltip。
- 使用 PictureRecorder → Canvas → Picture.toImage → PNG 合成；底图不进入撤销栈，PNG 仅在点击完成时编码。保存/复制复用现有 HostPlatformService，包括原有“保存同时复制”行为。
- 马赛克为约 18 原图像素的固定网格，低分辨率纹理每会话准备一次，以最近邻放大后沿笔迹蒙版覆盖；不会只添加可移除的 UI 遮罩。纹理准备失败禁用马赛克工具并展示重试，其他工具仍可使用。
- 不透明遮盖输出实色矩形，可用于完全盖住内容；马赛克仍可能保留文字形状，不能将其视为不可恢复的匿名化保证。

## 性能、状态与生命周期

- 每会话最多 200 笔，达到上限提示撤销/清空；每笔最多 2048 个采样点，长轨迹等距抽稀后继续追踪末端。相邻距离小于 1 原图像素时不追加点。
- 高频更新只订阅编辑 Provider，截图主 Controller 不随每个鼠标采样更新；底图与标注分层，标注层使用 RepaintBoundary。
- `beginEditing` 取消连续截图 Timer 并递增请求令牌；已发出的自动截图即使迟到也只能释放其 Image，不替换编辑源图。
- 编辑状态在 Controller 层同时拦截截图、布局抓取、连续截图配置和录屏启动；UI 显示编辑专用工具栏，导出忙碌期间锁定操作。
- 工作区 clone 源图和异步渲染需要的句柄，销毁后迟到的纹理/导出结果及时 dispose；成功结果由 ScreenshotEditSession 接管，刷新、再次完成编辑、设备重置及 Provider 销毁均释放旧结果。
- 普通 Tab 切换由现有 IndexedStack 保留草稿；切设备或路由移除工作区会放弃临时草稿。销毁时通过微任务结束对应源图的编辑标记，避免非 autoDispose 截图 Controller 残留 `isEditing=true`。设备切换期间完成的过期导出不会写回新设备。
- 编辑时设备临时离线仍保留工作区，可继续编辑当前快照。工具栏使用项目 Theme 和中英文 l10n；标注颜色属于固定图片内容，不随主题变色。

## 测试与回归

新增测试覆盖编辑操作历史、像素合成、马赛克笔迹、会话互斥、迟到请求、资源释放、四个旋转角度下缩放/平移后的鼠标落点、拖动画布，以及取消/完成流程。现有截图、布局分析、连续截图配置和 HarmonyOS 布局回归仍需通过。

```bash
flutter test --no-pub test/screenshot_edit_core_test.dart \
  test/screenshot_edit_toolbar_test.dart test/screenshot_edit_session_test.dart \
  test/screenshot_edit_overlay_test.dart test/screenshot_edit_workspace_test.dart \
  test/screenshot_layout_merge_test.dart test/screenshot_canvas_reset_test.dart \
  test/screenshot_auto_save_test.dart test/harmony_layout_inspector_test.dart \
  test/layout_properties_table_test.dart
flutter analyze --no-pub lib/features/screenshot \
  lib/app/l10n/tables/app_l10n_tools_mirror.dart test/screenshot_edit_*.dart
```

2026-11-06 验证：上述 10 个测试文件共 53 项通过，其中新增编辑测试 36 项；修改模块与新增测试定向 analyze 无诊断，`git diff --check` 通过。全量 `flutter analyze --no-pub` 报告 38 项位于其他未修改文件的 warning/info，未发现本次修改文件诊断；遵循局部修改原则保留这些存量问题。

桌面应用未启动或重新构建。真实窗口中的触控板体验、保存文件/系统剪贴板粘贴、不同设备截图及超大图片内存峰值仍需手动验收；自动测试不代表这些环境已经验收。
