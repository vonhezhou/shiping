# 架构与平台扩展

[返回首页](../README.md) · [开发与测试](development.md)

## 目录结构

| 目录 | 职责 |
| --- | --- |
| `lib/core/` | 颜色、坐标、测量、标注及录屏规则 |
| `lib/app/` | 应用状态、历史、偏好与诊断日志 |
| `lib/platform/` | 桌面服务、原生通信、像素缓冲与图片渲染 |
| `lib/ui/` | 历史、设置与截图标注界面 |
| `lib/l10n/` | 中英文资源及生成代码 |
| `macos/Runner/` | 屏幕采集、浮层、录屏、Vision、贴图及系统集成 |
| `pigeons/` | Dart / Swift 通信协议源 |
| `test/` | Dart 单元 / UI 测试及原生夹具 |
| `integration_test/` | 真实 macOS 应用集成测试 |
| `tool/` | 协议与语言检查、原生回归和图标生成工具 |

## 产品名称与内部标识

产品名为「拾屏」，中英文界面使用同一品牌，macOS 构建产物为 `拾屏.app`。Dart 包名 `fruler`、Swift 模块名、应用标识 `dev.fruler.app`（Debug 为 `dev.fruler.app.debug`）、通信协议、偏好键与日志路径保留原标识，以延续本机数据和系统权限。`LICENSE` 中的 `dev.fruler` 是版权主体。导出文件使用「拾屏」前缀，CSS 变量使用 `--shiping-` 前缀。

## 平台能力

工具入口按 `DesktopService.capabilities` 声明的平台能力显示：取色、测量、截图、录屏、二维码、OCR 和贴图可分别启用。未声明的能力默认隐藏，控制器也会拦截直接调用和原生激活事件；二维码与 OCR 还要求支持截图。录屏权限与能力分开处理，尚未授权时仍保留工具和授权入口。当前 macOS 适配器支持上述全部能力，尚未适配的平台仅显示通用设置。新增平台时需显式声明已实现的能力，并让原生菜单和快捷键仅注册支持的工具。

## 原生通信协议

macOS 与 Flutter 使用 Pigeon 传递控制、事件和元数据，使用 Dart FFI 读取冻结的 sRGB RGBA 像素。协议源是 `pigeons/desktop.dart`：`DesktopHostApi` 定义 Dart → Swift 调用，`DesktopFlutterApi` 定义 Swift → Dart 回调；截图回复只包含缓冲句柄、长度、行跨度及显示器尺寸，不通过通道传整屏像素。文本复制继续使用 Flutter 标准 Clipboard 接口。

`NativePixelBuffer.swift` 提供稳定的 C ABI：`fruler_frame_acquire`、`fruler_frame_data`、`fruler_frame_length`、`fruler_frame_release`。原生会话持有初始缓冲，Dart 外部字节视图持有独立引用，最后一个视图被回收后由 native finalizer 释放。结束会话注销句柄，已有视图仍可安全读取；像素视图只读。其他桌面平台实现相同采集与缓冲接口即可复用 Dart 算法。

选区通过 `PixelFrame` 的原图、偏移和行跨度共享缓冲，取色和测距通过统一像素寻址访问。标注按原图缓存 `ui.Image`，调整和重新选择选区复用原图，预览与导出按源矩形绘制；PNG 仅在最终输出时编码。首次创建 Flutter 图片仍会复制到引擎缓冲并上传，不能视为全链路零拷贝。

修改协议后执行：

```sh
dart run pigeon --input pigeons/desktop.dart
```

生成的 Dart / Swift 文件一起提交；Pigeon 版本固定在开发依赖中。`python3 tool/check_protocol.py` 会重新生成到临时目录并检查一致性，完整检查已包含此步骤。`dev.fruler/integration` 是独立的测试驱动通道，只在 `FRULER_INTEGRATION_TEST` 构建中启用。
