# fruler

**Flutter + ruler**：面向桌面的取色器与屏幕尺子。当前实现 macOS 版，Flutter 负责工作台界面，Dart 负责颜色与测量规则，平台适配层负责屏幕采集、浮层、快捷键和权限。

## 当前功能

- 取色：4×–32× 可调像素放大镜；单次或连续采集；HEX / RGB / HSL / Flutter `Color(...)` / CSS 复制格式；最多 64 条去重的最近颜色。
- 颜色编辑：输入 3 位或 6 位 HEX，调整 RGB / HSL，确认后加入最近记录；取消不修改颜色。
- 我的调色板：收藏、命名、单条删除，独立于最近记录保存；最近记录与调色板分别支持 JSON / CSS 文件导出。分组暂未实现。
- 测量：浮动工具栏现场切换模式、Shift 连续保留多个矩形标注、选中和删除单个标注、撤销标注操作、复制和保存带尺寸的局部 PNG、矩形拖拽、水平间距、垂直间距、交叉测距；自动测量根据光标处像素的颜色识别连续边界，可通过滚轮调整颜色容差（0–255，每档 15）。
- 同时显示截图像素 `px` 与 macOS 逻辑点 `pt`，处理每块显示器各自的缩放比例。矩形框选限于单块显示器。
- 菜单栏常驻、可自定义全局快捷键、方向键逐截图像素微调、Enter 确认、Esc 或鼠标右键取消；关闭主窗口后仍可从菜单栏打开或退出。
- 按次冻结屏幕快照，不持续录屏；屏幕图像在内存中保留到工具退出，不上传；只有用户主动复制或导出标注时，才将局部图片写入剪贴板或用户选择的文件。颜色、测量历史、调色板和偏好设置保存在本机。

Windows / Linux 尚未实现。仅生成对应平台工程不会获得完整取色、测量能力，仍需实现下文的平台适配层。

## 开发环境

| 项目 | 要求或当前验证环境 |
| --- | --- |
| 运行系统 | macOS 14 或更新版本，使用 `ScreenCaptureKit` 的单帧截图 API |
| Flutter / Dart | 当前验证版本为 Flutter 3.47.5 / Dart 3.13.4；`pubspec.yaml` 要求 Dart `^3.13.4` |
| 原生工具链 | 完整 Xcode 及其命令行工具；当前验证版本为 Xcode 27.1 |
| 已验证架构 | Apple Silicon / arm64；Intel 尚未实机验收 |

在项目根目录执行以下命令，先确认 Flutter 能识别 macOS 工具链：

```sh
flutter --no-version-check --version
flutter --no-version-check doctor -v
flutter --no-version-check pub get
```

本文使用 `--no-version-check` 跳过 Flutter 启动时的版本检查，不修改 SDK 或全局配置。如果使用 FVM，可将命令开头的 `flutter` 替换为 `fvm flutter`。首次准备环境、解析依赖或下载引擎可能需要联网；应用本身的取色与测量不需要联网。

## 运行 macOS 版

```sh
flutter --no-version-check run -d macos
```

该命令启动 Debug 版，支持 Flutter 热重载。编辑原生 Swift 或工程配置后，需要退出并重新运行，热重载不会重新编译这些文件。

首次使用，在 fruler 的「偏好设置」中请求屏幕授权，再到 macOS「系统设置 → 隐私与安全 → 录屏与系统录音」（旧系统名称可能为「屏幕录制」）允许**实际运行的 fruler 应用**。系统要求退出重开时，按提示重启应用。

| 操作 | 快捷键或交互 |
| --- | --- |
| 开始取色 | `⌘ ⇧ C`，或工作台 / 菜单栏入口 |
| 开始矩形测量 | `⌘ ⇧ R`，或工作台 / 菜单栏入口 |
| 水平、垂直、交叉测距 | 在尺子页选择模式后开始，或使用菜单栏入口 |
| 复制结果 | 取色和自动测距时点击；矩形测量时拖拽并松开 |
| 现场切换尺子模式 | 浮动工具栏，或数字 `1` 矩形 / `2` 水平 / `3` 垂直 / `4` 交叉；复用同一张冻结快照 |
| 调整取色倍率 | 取色时滚轮，在 4× / 8× / 12× / 16× / 24× / 32× 间切换 |
| 调整自动测量容差 | 水平 / 垂直 / 交叉模式下滚轮，每档 15，范围 0–255 |
| 连续矩形标注 | `Shift` + 松开鼠标，或 `Shift Enter`；复制并保留标注，继续测量 |
| 清除当前标注 | 浮动栏「清除标注」，保留已有测量历史 |
| 逐像素微调 | 方向键每次移动一个截图像素，支持连续按键；鼠标移动后恢复鼠标定位 |
| 键盘确认 | 取色 / 自动测距按 `Enter`；矩形第一次 `Enter` 定起点，移动后第二次确认 |
| 自定义全局快捷键 | 偏好设置点击当前组合，按下修饰键与字母 / 数字，再按 `Enter` 或「保存」；`Esc` 取消 |
| 连续取色 | 在工作台或取色浮层勾选「连续取色」；每次点击 / Enter 复制并加入最近记录，Esc / 右键结束 |
| 编辑颜色 | 工作台「编辑颜色」或色卡菜单；支持 HEX 输入与 RGB / HSL 滑块，保存后加入最近记录 |
| 收藏、命名与删除 | 色卡右侧菜单；收藏、命名或「保存到调色板」会建立独立的调色板条目 |
| 调色板导出 | 最近记录或我的调色板下方「导出 JSON / CSS」，在系统保存对话框中选择位置 |
| 选择与删除标注 | 浮层第二行的「选择本屏标注」，或「编辑标注」后点击框；「删除选中」或编辑模式下 Delete 删除 |
| 撤销标注 | 「撤销」或 `⌘ Z`，支持撤销添加、删除和清除，保留最近 64 次操作 |
| 复制 / 保存标注图 | 「复制图片」或「导出 PNG」；选中时仅导出选中框，否则导出当前屏全部保留框 |
| 取消 | `Esc` 或鼠标右键 |

快捷键表中的组合为默认值。自定义组合必须包含 Command / Control / Option 中至少一个修饰键，可附加 Shift，按物理 US 键位识别字母与数字。录制期间临时暂停本应用的全局快捷键及菜单等效键；取消会恢复。系统保留组合会被拒绝，使用 Carbon 独占注册；修改冲突时尝试恢复原配置，并显示实际注册状态。重启时若保存的组合已被占用，保留偏好并显示未注册，不启用其他组合。倍率、容差、快捷键和连续取色开关随偏好设置持久化，兼容前两版历史。标注只存在于当前会话，Esc 退出后释放；已确认的测量仍保存在历史中。标注撤销只作用于当前浮层，不删除测量历史。图片导出使用冻结截图的原始像素，以尺寸标签和框的联合区域加边距裁剪；相邻标签会尝试错开排布，不包含工具栏或光标；不同显示器分别导出，取消保存后可继续测量。

最近记录删除或清空不会删除调色板；从调色板删除也不会移除最近记录。取消收藏仍保留调色板条目，删除请使用「从调色板删除」。JSON 保留名称、RGB、HEX 和收藏状态；CSS 使用 `--fruler-1` 等编号变量，不将用户名称拼入 CSS 语法。

### 授权与快捷键排查

- Debug 标识为 `dev.fruler.app.debug`，Release 标识为 `dev.fruler.app`，两者分别授权、分别保存本地历史。
- 本地构建默认使用临时签名；重建后系统可能要求重新授权。系统列表显示已开启、应用仍报告未授权时，核对所授权的构建路径，并按系统提示重新开启权限、退出重开。
- 不要同时运行 `flutter run`、构建目录中的应用和 `dist/` 中的副本。它们会争用同一组全局快捷键；同一 Release 标识的多个副本也可能让系统重新打开错误路径的应用。
- 快捷键注册失败会在偏好设置中显示提示；可在偏好设置更换组合，或退出占用快捷键的应用后重新启动 fruler。

## 构建 macOS 应用

先退出正在运行的 fruler，再构建。以下是已验证的 Apple Silicon 本机 Release 构建方式，只构建当前活动架构，不改变全局 Flutter 架构配置：

```sh
flutter --no-version-check pub get
FLUTTER_XCODE_ONLY_ACTIVE_ARCH=YES FLUTTER_XCODE_ARCHS=arm64 \
  flutter --no-version-check build macos --release --no-pub
```

构建产物为：

```text
build/macos/Build/Products/Release/fruler.app
```

可直接启动：

```sh
open build/macos/Build/Products/Release/fruler.app
```

如果需要将可运行副本单独放到交付目录：

```sh
mkdir -p dist
ditto build/macos/Build/Products/Release/fruler.app dist/fruler.app
open dist/fruler.app
```

选择一个应用路径运行与授权即可。`build/` 和 `dist/` 已被 Git 忽略；本地构建不是经过公证的发行包，面向其他用户分发时还需配置正式签名和公证。其他架构需要按目标环境构建和验收，当前 arm64 产物不能用于 Intel Mac。

## 校验与图标

```sh
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub
```

测试覆盖核心算法、应用会话、调色板及桌面布局，使用 `FakeDesktop` 隔离原生服务，不需要录屏权限或启动真实捕获浮层。它们不能代替屏幕授权、多屏缩放、全屏应用覆盖和实际全局快捷键的实机验收。

macOS 原生 PNG 渲染回归使用合成图像，不读取真实屏幕，校验裁剪、方向、颜色与无效标注。需要系统 `python3` 和 Xcode 的 Swift 工具链：

```sh
python3 tool/test_annotation_export.py
```

仅运行某一组测试：

```sh
flutter --no-version-check test --no-pub test/core
flutter --no-version-check test --no-pub test/app
flutter --no-version-check test --no-pub test/ui
```

应用图标已包含在源码中。修改图标绘图规则后，可在 macOS 项目根目录重新生成：

```sh
swift tool/generate_icon.swift
```

## 项目结构

```text
lib/
  main.dart                       # 创建平台服务和控制器，启动 Flutter
  core/
    color_value.dart              # HEX 解析、RGB / HSL 转换与开发代码格式
    palette.dart                  # 命名、收藏模型与 JSON / CSS 导出
    pixel_frame.dart              # RGBA 帧、像素取样、逻辑坐标与像素换算
    ruler.dart                    # 测量模式、半开矩形和颜色边界检测
    capture_controls.dart         # 倍率、容差与逐像素坐标微调
    shortcut.dart                 # 平台无关的快捷键配置与序列化
    core.dart                     # 核心类型导出
  app/
    app_controller.dart           # 工具会话、取消与提交、历史和偏好设置
  platform/
    desktop_service.dart          # 平台接口、macOS 通道适配、不支持平台的实现
  ui/
    fruler_app.dart                # 取色器、尺子、偏好设置和绘制组件
    palette_widgets.dart          # 颜色编辑对话框、色卡菜单与导出入口
macos/
  Runner/
    MainFlutterWindow.swift       # 原生桥接、截图、浮层、菜单栏和快捷键
    AppDelegate.swift             # 应用生命周期和关闭窗口后的常驻行为
    Configs/AppInfo.xcconfig      # 产品名和 Release 应用标识
    Info.plist                    # 应用元数据与屏幕权限用途说明
  Runner.xcodeproj/               # 原生工程与各构建配置
  Runner.xcworkspace/             # Xcode 工作区入口
test/
  core/                           # 颜色、坐标、缩放和边界算法测试
  app/                            # 会话、复制、权限错误和历史恢复测试
  ui/                             # 桌面布局与导航测试
  fake_desktop.dart               # 测试用平台服务
  macos/                          # PNG 渲染合成图像回归夹具
tool/
  generate_icon.swift             # 可重复执行的 macOS 图标生成脚本
  test_annotation_export.py       # 调用生产 PNG 渲染实现执行原生回归
```

`lib/core/` 不依赖 Flutter 或 macOS，可以直接复用于其他平台；`lib/app/` 使用 Flutter 的状态通知机制，但通过 `DesktopService` 调用系统能力。Swift 不承载颜色转换或边界检测规则。

## Windows / Linux 扩展点

### 1. 实现 `DesktopService`

扩展入口是 `lib/platform/desktop_service.dart` 中的 `DesktopService.create()`。当前工厂只在 macOS 返回 `MacDesktopService`，其余平台返回 `UnsupportedDesktopService`。

新增 `WindowsDesktopService` / `LinuxDesktopService`，实现同一接口并接入工厂；系统能力通过原生 runner 或独立 Flutter 插件承接。原生层可以继续使用现有通道契约，也可以由新的 Dart 适配器转换平台协议，不应把 OS API 引入 `lib/core/`。

| 接口 | 新平台应实现的职责 |
| --- | --- |
| `initialize` | 报告捕获是否可用、权限状态和快捷键注册状态 |
| `requestPermission` / `openPrivacySettings` | 完成对应平台的授权或引导；不需要额外授权的平台返回真实可用状态 |
| `begin(tool)` | 按次获取显示器快照、排除自身窗口，创建捕获会话和交互浮层 |
| `events` | 转发工具唤起、指针操作、模式切换、滚轮、键盘微调、确认、清除标注、取消和权限变化 |
| `configureShortcuts(bindings)` | 原子注册取色与矩形测量组合；失败恢复旧配置，报告真实注册状态 |
| `setShortcutRecording(recording)` | 录制时暂停本应用快捷键与菜单等效键，结束后重新注册 |
| `updateOverlay` | 根据 Dart 返回的颜色、标签和像素矩形更新浮层 |
| `finish(sessionId)` | 关闭浮层、释放屏幕帧，恢复必要的焦点；旧会话不能关闭新会话 |
| `loadState` / `saveState` | 读写控制器提供的 JSON；macOS 当前使用 `UserDefaults` 的 `fruler.state.v1` |
| `saveTextFile(filename, text)` | 通过平台保存对话框导出调色板；取消返回 false，成功返回 true，写入失败抛错 |
| `exportAnnotations(sessionId, displayId, annotations, save)` | 从冻结帧绘制带编号、尺寸的局部图；save=true 保存 PNG，否则写图片剪贴板；不重新截图 |
| `writeClipboard` | 写入文本剪贴板；现有 macOS 实现使用 Flutter `Clipboard` |

### 2. 保持帧、坐标和会话契约

macOS 当前使用 `MethodChannel('dev.fruler/desktop')` 和 `EventChannel('dev.fruler/events')`。`begin` 接收的 `tool` 为 `picker`、`rectangle`、`horizontal`、`vertical` 或 `cross`，返回：

```text
CaptureSession
  id: 会话 ID
  displays[]
    id / name: 显示器标识与名称
    frame.width / height: 截图像素宽高
    frame.logicalWidth / logicalHeight: 同一显示器的逻辑宽高
    frame.rgba: width × height × 4 字节的 Uint8List
```

- 屏幕帧归一化为 **8 位 sRGB RGBA**，按行存储，原点为显示器左上角。BGRA 或其他色彩空间必须在平台侧转换。
- 指针事件的 `x` / `y` 使用**该显示器本地的逻辑坐标**。原生虚拟桌面的负坐标、DPI、缩放及上下原点差异，在进入 Dart 前转换。
- `updateOverlay.rect` 使用截图像素坐标，右、下边界不包含在矩形内，即 `[left, right) × [top, bottom)`；浮层绘制时再转换为平台坐标。
- 指针事件包含 `type: pointer`、`sessionId`、`displayId`、`x`、`y` 和 `phase`，`phase` 为 `move` / `down` / `drag` / `up`。
- 第二版会话输入包括 `modeChanged(tool)`、`scroll(steps)`、`nudge(dx,dy)`、`confirm(keep)` 和 `clearPins`，都包含 `sessionId`。Shift 松开鼠标时 `pointer.keep=true`，Shift Enter 时 `confirm.keep=true`。
- `updateOverlay` 同时携带 `tool`、`tolerance`、`zoom`、`pinned[]`；每个标注有 `displayId`、截图像素 `rect` 和 `label`。未带 `displayId` 的更新只刷新各屏的全局控件，不移动采样位置。`keyboard` 表示虚拟键盘光标，`anchored` 表示矩形已定起点。
- 快捷键录制可通过 Flutter 键盘事件处理；macOS 也发送 `shortcutRecorded(chord)`，以原生事件自带的修饰键和物理键位为准，避免输入法或遗漏修饰键变化事件影响录制。此事件只在录制期间生效。
- 快捷键 `bindings` 为 `{picker, ruler}`，每项含 `key`（A–Z / 0–9）和布尔修饰键 `meta/control/alt/shift`。新平台应按其按键映射实现，不把 macOS Carbon keycode 写入 Dart。注册失败不能覆盖已保存组合。
- 第三版增加 `continuousChanged(enabled)`、`editPins`、`selectPin(id)`、`deletePin`、`undoPins` 和 `exportPins(displayId, save)` 会话事件。保留框含稳定 `id`；`selectPin(null)` 取消选择。`updateOverlay` 增加 `continuous`、`pickedCount`、`editingPins`、`selectedPin`、`canUndoPins`。
- 本地 JSON 继续使用 `fruler.state.v1`，新增可选 `continuousPicker` 和 `palette[]`；缺失时按旧版本迁移，单条损坏记录独立跳过。调色板条目包含 `color`、`name` 和 `favorite`，不存屏幕图像。
- macOS 的文件保存只启用 `com.apple.security.files.user-selected.read-write`，文件位置由系统保存对话框选择，不申请整盘文件访问。
- 其他事件为 `activate`（含 `tool`）、`cancelled`（含 `sessionId`）、`permissionChanged`（含 `permission`）。取消后须释放平台资源，并让控制器离开忙碌状态。
- 输入可能早于 `begin` 的返回结果到达，控制器会暂存事件；后续仍依赖正确的会话 ID 过滤旧事件。屏幕重配、休眠等导致会话失效时，应关闭浮层并通知取消。

### 3. 按平台补齐能力和界面语义

| 平台 | 需要补齐的部分 |
| --- | --- |
| Windows | 原生屏幕采集、浮层窗口、全局快捷键、托盘与生命周期；重点验证不同显示器的 DPI 和虚拟桌面坐标。可从 [Windows 屏幕采集官方文档](https://learn.microsoft.com/en-us/windows/uwp/audio-video-camera/screen-capture) 评估采集方案。 |
| Linux / X11 | 截图、窗口覆盖、全局快捷键和托盘的原生实现；单独验证桌面环境与缩放行为。 |
| Linux / Wayland | 先评估目标桌面的 [XDG Desktop Portal](https://flatpak.github.io/xdg-desktop-portal/docs/api-reference) 及 [Global Shortcuts](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html) 支持，再设计采集授权与浮层交互；不能直接照搬 X11 的实现与权限假设。 |

界面目前包含 macOS 平台名称、`⌘` 快捷键提示和 `pt` 单位。新增平台时，应同步调整为对应平台的快捷键与逻辑尺寸术语；无法提供的能力要明确显示为不可用，而不是只修改平台工厂后继续沿用 macOS 文案。

### 4. 新增 runner 与验证

准备正式实现时，可在项目根目录生成平台工程，并审查生成差异：

```sh
flutter --no-version-check create --platforms=windows,linux .
```

这一步仅生成 runner。完成原生实现、Dart 适配及工厂注册后，再分别在目标系统准备工具链并运行：

```sh
# Windows 宿主机
flutter --no-version-check run -d windows

# Linux 宿主机
flutter --no-version-check run -d linux
```

新增平台至少覆盖：帧通道与方向、非整数缩放、不同 DPI 多屏、单像素和屏幕边缘、反向拖拽、授权拒绝、重复唤起、Esc / 右键取消、屏幕重配、剪贴板和历史恢复。继续复用 `test/core/` 与 `test/app/`，并为新平台增加原生集成验收；仅跑 `FakeDesktop` 测试不能宣称平台接入完成。

Flutter 平台工程与工具链说明见[桌面支持文档](https://docs.flutter.dev/platform-integration/desktop)。
