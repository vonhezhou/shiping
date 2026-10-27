# 开发与测试

[返回首页](../README.md) · [贡献指南](../CONTRIBUTING.md) · [架构](architecture.md)

## 环境与运行

当前本机验证 Flutter 3.47.7 / Dart 3.13.4 和 Xcode，Apple Silicon；Intel 尚未实机验收。

```sh
flutter --no-version-check pub get
flutter --no-version-check run -d macos
```

构建：

```sh
flutter --no-version-check build macos --release --no-pub
```

构建结果位于 `build/macos/Build/Products/Release/拾屏.app`。分发给其他用户前仍需正式签名与公证。SDK 镜像缺少引擎文件时，可在单次命令前设置可用的 `FLUTTER_STORAGE_BASE_URL`；不需要修改全局设置。

## 依赖与生成文件

`pubspec.lock` 随应用代码提交，以固定依赖版本。依赖默认从 `pub.dev` 获取；需要镜像时仅在本机设置 `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`，不要把本机 SDK 路径、镜像偏好或签名证书写入仓库。

修改 `pigeons/desktop.dart` 后运行 `dart run pigeon --input pigeons/desktop.dart`，修改 ARB 后运行 `flutter --no-version-check gen-l10n`。生成的 Dart / Swift 文件与源文件一起提交，不直接编辑生成文件。

## 测试与验收

新增 / 修复行为先补失败回归，再修改实现。单元和 UI 测试不能替代真实 macOS 通道与浮层验收；开发约束见 [AGENTS.md](../AGENTS.md)。

```sh
python3 tool/check.py
```

完整门禁依次运行静态检查、单元 / UI、原生 PNG、跨进程单实例、原生 XCTest 和真实 macOS 集成测试。原生 XCTest 串行执行，避免共享单实例宿主、剪贴板和 AppKit 状态的测试进程互相干扰。任一步失败返回非零。也可单独运行：

```sh
flutter --no-version-check test --no-pub
python3 tool/test_macos_native.py
python3 tool/test_macos_integration.py
python3 tool/test_color_samples.py
```

集成测试使用独立的 `dev.fruler.integration` 标识和沙盒，需要本机允许录屏并保持桌面解锁。锁屏时 ScreenCaptureKit 可能返回空的显示器列表，不能作为验收通过。它实际调用 ScreenCaptureKit，向原生 NSPanel 发送 Cocoa 鼠标 / 键盘事件，检查：

- 独立 AppKit 文字窗口经真实屏幕采集、Vision OCR、原生鼠标拖选和键盘输入，验证中英文选区隔离、按词跨行选择、连续复制与完成后返回原应用；结束时恢复剪贴板。
- 独立 AppKit 窗口同屏显示两个真实二维码，经 ScreenCaptureKit 采集、原生框选和 Vision 识别验证左右选区隔离、空白选区保留、单结果保留查看、多结果选择、主动复制及完成后关闭浮层；剪贴板在结束时恢复。
- FFI 真实读取带行间填充的原生缓冲，原生注销 / 释放会话后旧像素视图仍有效，失效句柄和长度不符被拒绝；读取 isolate 退出后验证原生终结器释放最后一个引用。
- 选区前后窗口编号不变，主窗口始终隐藏；标注后调整选区仍在本次会话中。
- 九种标注工具、文字、撤销 / 重做，以及真实系统 PNG 剪贴板。
- 截图原位贴图、完整标注像素与 Retina 逻辑尺寸；剪贴板图片／文字／颜色，真实 Cocoa 拖动、滚轮、透明度、旋转翻转、重置、隐藏恢复与销毁。
- 取消保存面板继续标注；复制完成、Esc 取消、取色和测量结束后不重新打开主窗口。
- Swift 与 Dart 日志落入同一沙盒文件、真实退出握手刷新日志，以及未激活浮层的首次点击仍立即取色。
- 鼠标切换语言后 Flutter、原生菜单和现有尺子浮层同步更新，语言偏好通过真实原生存储恢复，剪贴板颜色格式保持一致。
- 从选项窗口用鼠标设置取色格式 / 倍率和尺子模式 / 容差，真实屏幕浮层接收同一配置，结束后主窗口继续隐藏，配置可重新载入。
- 通过原生存储精简超量的取色 / 收藏测量历史并恢复上限设置，真实 Cocoa 右键按自定义格式连续复制，中键取消不改变剪贴板。

颜色样本回归通过真实系统鼠标拖放保存色块、点击恢复，并启动第二个应用进程验证自定义色块及画笔当前颜色仍在；夹具需要辅助功能权限，测试前后备份和恢复系统颜色样本文件。

测试会备份和恢复剪贴板，外部 AppKit 夹具也会在退出时恢复启动前的剪贴板，以覆盖测试应用异常退出。没有录屏权限时，真实采集用例明确失败，不以跳过替代通过。输入驱动仅在 `FRULER_INTEGRATION_TEST` 条件下编译，普通 Debug / Release 不包含它。运行集成测试后，正常 `flutter run -d macos` 会重新构建普通应用。

UI 回归覆盖默认 1100×760、最小 920×680 和鼠标输入。跨显示器混合缩放、不同全屏应用及真实物理快捷键还应进行额外实机验收。

## GitHub Actions

仓库的 `Checks` 工作流在 macOS runner 上检查语言资源、Pigeon 生成文件、静态分析、Dart 单元 / UI 测试与原生 PNG 导出。此工作流不运行需要交互桌面、屏幕录制或辅助功能权限的用例，不等于完整 macOS 验收；完整门禁仍须在已授权且解锁的本机执行 `python3 tool/check.py`。
