# 拾屏

macOS 菜单栏屏幕工具，集取色、测量、截图标注、区域录屏、OCR、二维码识别与贴图于一体。支持简体中文和 English，使用 Flutter 与 Swift 构建。

启动后常驻菜单栏。取色和测量在屏幕上直接复制，截图选区和标注在同一个全屏浮层完成；结束后回到原应用。主窗口用于历史和设置。

## 功能

| 工具 | 默认入口 | 主要能力 |
| --- | --- | --- |
| 取色器 | `⌘⇧C` | 像素放大镜、连续取色、自定义颜色格式与历史 |
| 屏幕尺子 | `⌘⇧R` | 矩形 / 水平 / 垂直 / 交叉测量，多框编辑与历史导出 |
| 截图标注 | `⌘⇧X` | 形状、箭头、文字、荧光笔、马赛克、模糊及撤销 / 重做 |
| 区域录屏 | 菜单栏 / 设置 | H.264 / HEVC、24 / 30 / 60 fps、可选系统声音，输出 MP4 |
| OCR / 二维码 | 截图工具栏；二维码另有菜单栏入口 | 本机识别选区，查看并复制结果 |
| 贴图 | `⌘⇧T` | 将剪贴板图片、文字或颜色置顶，支持缩放、旋转和透明度 |
| 显示 / 隐藏贴图 | `⌘⇧V` | 集中隐藏或恢复贴图 |

## 从源码运行

需要 **macOS 14+**、Xcode（含命令行工具）和 Flutter。当前已记录的开发环境为 **Flutter 3.47.7 / Dart 3.13.4、Apple Silicon**；Intel 尚未实机验收，Windows / Linux 尚未适配。

在仓库根目录执行：

```sh
flutter --no-version-check pub get
flutter --no-version-check run -d macos
```

首次启动只显示菜单栏图标。通过菜单打开设置，在「常规」中请求屏幕录制权限，并在系统设置中允许实际运行的拾屏应用，必要时重启。剪贴板贴图无需屏幕录制权限。

构建 Release：

```sh
flutter --no-version-check build macos --release --no-pub
```

产物为 `build/macos/Build/Products/Release/拾屏.app`。本地构建不代表已完成正式签名与公证，分发前请阅读[发布说明](docs/releasing.md)。

## macOS 自动构建

GitHub Actions 的 `Checks` 工作流仅在推送版本 tag（例如 `v0.10.0`）且现有检查通过后，构建 macOS Release 并将安装包单独发布到 GitHub Release。tag 必须为 `v` 加上 `pubspec.yaml` 中去掉 `+构建号` 的版本。普通分支 push（包括 main）、PR 和手动运行只执行检查，不构建 Release。

更新版本并提交代码后，推送对应 tag：

```sh
git tag v0.10.0
git push origin v0.10.0
```

前往 **[Releases 下载页面](https://github.com/vonhezhou/shiping/releases)**，选择「拾屏 macOS 安装包（DMG，ad hoc）」即可下载安装包，无需解压 ZIP。每个版本分别提供：

- `shiping-<版本tag>-macos-adhoc.dmg`：应用安装包。
- `shiping-<版本tag>-macos-adhoc.dmg.sha256`：SHA-256 校验文件。

GitHub 页面中的 `Source code (zip)` 和 `Source code (tar.gz)` 是自动生成的源码压缩包，不包含可直接安装的应用。Actions 的 Artifacts 仅作为 CI 备份，GitHub 下载时会将其包装为 ZIP；安装应用请优先使用上面的 Release 下载项。

打开 DMG，将「拾屏.app」拖到旁边的「应用程序」快捷方式，复制完成后推出磁盘镜像，再从「应用程序」启动拾屏。从菜单栏进入设置并按需授权屏幕录制。校验下载文件可在所在目录运行 `shasum -a 256 -c shiping-v0.10.0-macos-adhoc.dmg.sha256`。DMG 内的 `BUILD-INFO.txt` 记录版本、提交、实际构建架构和签名状态。

**当前产物使用 ad hoc 签名，没有 Developer ID 签名，未公证，未 stapling，仅供测试；macOS Gatekeeper 可能阻止打开。** Developer ID 签名、公证和 stapling 将在后续配置。构建成功不代表真实 macOS 集成测试或人工验收通过，Intel 仍未实机验收。

## 数据与限制

屏幕内容、OCR 和二维码识别在本机处理，不上传。颜色、测量历史及偏好保存在本机；截图历史和贴图仅在本次运行中保留。录屏停止后选择保存或丢弃，不录制麦克风。详见[权限、数据与诊断日志](docs/privacy.md)。

选区限于单块显示器；macOS 尺寸按逻辑点 pt 展示，图片按原始像素导出。混合缩放、跨显示器及不同全屏应用的行为仍需实机验收。

## 文档与贡献

- [使用指南](docs/usage.md)：各工具操作、快捷键和边界。
- [开发与测试](docs/development.md)：环境、生成代码与回归入口。
- [架构与平台扩展](docs/architecture.md)：目录职责、Pigeon 和像素缓冲。
- [贡献指南](CONTRIBUTING.md)：问题反馈、开发约束和 PR 要求。
- [发布说明](docs/releasing.md)：公开仓库和应用分发前的检查。

完整本机回归入口：

```sh
python3 tool/check.py
```

GitHub Actions 仅覆盖可自动运行的检查，不替代需要录屏权限和交互桌面的真实 macOS 集成测试。

## 致谢

部分交互设计参考 [PowerToys Screen Ruler](https://learn.microsoft.com/windows/powertoys/screen-ruler)、[Color Picker](https://learn.microsoft.com/windows/powertoys/color-picker) 和 [Snipaste](https://github.com/Snipaste/feedback/wiki/基础操作)。拾屏是独立项目。

## 许可证

本项目采用 [MIT License](LICENSE)。第三方依赖保留各自许可证。
