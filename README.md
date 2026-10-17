# fruler

**Flutter + ruler**：面向桌面的取色器与屏幕尺子。当前实现 macOS 版，Flutter 负责工作台界面，Dart 负责颜色与测量规则，平台适配层负责屏幕采集、浮层、快捷键和权限。

## 当前功能

- 取色：4×–32× 可调像素放大镜；单次或连续采集；HEX / RGB / HSL / Flutter `Color(...)` / CSS 复制格式；最多 64 条去重的最近颜色。
- 颜色编辑：输入 3 位或 6 位 HEX，调整 RGB / HSL，确认后加入最近记录；取消不修改颜色。
- 我的调色板：收藏、命名、单条删除，独立于最近记录保存；JSON / CSS 导出，JSON 导入预览与冲突合并，多选复制 CSS 变量或 Flutter 颜色列表；支持分组、重命名、解散、颜色名称 / HEX 搜索和长按拖动排序。
- 图片工作区：打开或拖入 PNG / JPEG / WebP，按原始像素取色与矩形 / 水平 / 垂直 / 交叉测量；缩放、平移、编辑标注、撤销 / 重做及局部 PNG 导出；支持自包含 `.fruler` 项目保存与恢复，读取本地图片不需要录屏授权。
- 颜色对比度：编辑或从屏幕依次选取前景 / 背景色，实时文字预览、比值和普通 / 大号文字的 WCAG AA / AAA 结果。
- 测量：浮动工具栏现场切换模式、Shift 连续保留多个矩形标注、选中和删除单个标注、撤销标注操作、复制和保存带尺寸的局部 PNG、矩形拖拽、水平间距、垂直间距、交叉测距；自动测量根据光标处像素的颜色识别连续边界，可通过滚轮调整颜色容差（0–255，每档 15）。
- 标注编辑：拖动移动、拖拽四角或四边调整，方向键移动一个截图像素，Shift + 方向键调整右 / 下边界；支持整次拖拽撤销，限制在所属显示器内，至少保留 1×1 像素。
- 测量历史：命名、收藏、搜索、单条删除，按当前筛选结果导出 CSV / JSON；记录模式、原始像素 / 逻辑尺寸、显示器、时间和两轴缩放。最近 32 条非收藏记录加全部收藏。
- 同时显示截图像素 `px` 与 macOS 逻辑点 `pt`，处理每块显示器各自的缩放比例。矩形框选限于单块显示器。
- 菜单栏常驻、可自定义全局快捷键、方向键逐截图像素微调、Enter 确认、Esc 或鼠标右键取消；关闭主窗口后仍可从菜单栏打开或退出。
- 按次冻结屏幕快照，不持续录屏；屏幕图像在内存中保留到工具退出，不上传；只有用户主动复制或导出标注时，才将局部图片写入剪贴板或用户选择的文件。颜色、测量历史、调色板和偏好设置保存在本机。

同一应用标识的多个 macOS 副本只允许一个运行：后启动的副本在创建 Flutter 引擎、注册快捷键之前退出，并尝试唤起已有主窗口。锁由操作系统在进程结束时释放，崩溃后也无需清理。Debug 与 Release 的应用标识不同，可分别运行，仍可能发生快捷键冲突。

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
| 撤销 / 重做标注 | 「撤销」「重做」或 `⌘ Z` / `⌘ ⇧ Z`，支持添加、删除、清除、移动与调尺寸，各保留最近 64 个状态 |
| 复制 / 保存标注图 | 「复制图片」或「导出 PNG」；选中时仅导出选中框，否则导出当前屏全部保留框 |
| 调整已有标注 | 「编辑标注」后拖动框；先选中框，再拖边 / 角调整；方向键移动，Shift + 方向键调整右 / 下边界 |
| 测量历史管理 | 尺子页搜索、只看收藏，星标收藏；记录菜单命名 / 删除；导出当前筛选结果 |
| 颜色对比度 | 取色页底部编辑两色、使用当前颜色、分别从屏幕选取，或「依次取两色」 |
| 导入调色板 | 「导入 JSON」选择 fruler 导出的文件；预览后选择保留已有或采用导入的名称 / 收藏，再合并 |
| 批量复制 | 「批量复制」中多选或全选，复制 CSS 变量或 Flutter `<Color>[...]` |
| 调色板分组 | 新建分组；分组下拉切换全部 / 未分组 / 指定分组；分组旁按钮重命名或解散，色卡菜单可移动到分组 |
| 调色板排序 / 搜索 | 长按色卡拖到目标色卡位置，或菜单「向前排序 / 向后排序」；按名称或 HEX 搜索，搜索时暂停排序 |
| 整组导出 | 选中分组后导出 JSON / CSS；导出与批量复制均使用当前分组及搜索结果 |
| 打开图片 | 图片工作区「打开图片」，或把单个图片文件从访达拖入 fruler 窗口 |
| 图片缩放 / 平移 | 滚轮或触控板缩放，或使用 + / −；选「平移」后拖动；「适应窗口」「100%」重置视图 |
| 图片取色 / 测量 | 工作区选工具后点击或拖拽；原图坐标不随视图缩放改变；方向键 / Enter 可微调和确认，测量自动保留标注 |
| 图片项目 | 「保存项目」「打开项目」；画布聚焦时 `⌘ S` 保存，保存面板取消不丢弃修改 |
| 图片标注 / 对比度 | 「编辑标注」后选择、拖动、调边角，或用方向键与 Shift 调尺寸；导出 PNG / 复制标注图；已取颜色可设为前景 / 背景 |
| 取消屏幕工具 | `Esc` 或鼠标右键；图片工作区 Esc 取消选择，关闭图片结束该图片会话 |

快捷键表中的组合为默认值。自定义组合必须包含 Command / Control / Option 中至少一个修饰键，可附加 Shift，按物理 US 键位识别字母与数字。录制期间临时暂停本应用的全局快捷键及菜单等效键；取消会恢复。系统保留组合会被拒绝，使用 Carbon 独占注册；修改冲突时尝试恢复原配置，并显示实际注册状态。重启时若保存的组合已被占用，保留偏好并显示未注册，不启用其他组合。倍率、容差、快捷键和连续取色开关随偏好设置持久化，兼容前两版历史。屏幕标注只存在于当前捕获会话，Esc 退出后释放；图片标注可保存到项目文件。标注撤销 / 重做不删除或重建测量历史。图片导出使用冻结截图的原始像素，以尺寸标签和框的联合区域加边距裁剪；相邻标签会尝试错开排布，不包含工具栏或光标；不同显示器分别导出，取消保存后可继续测量。

第四版标注编辑只修改当前冻结会话的框和导出图片，测量历史保留确认当时的原始结果；移动 / 调整不会重复添加历史。一次鼠标拖拽对应一次撤销，键盘每次调整也可撤销。历史收藏不会被最近 32 条非收藏记录淘汰；取消收藏后重新受该上限约束。CSV 字段加引号并转义，可能作为公式执行的文本加单引号前缀；JSON 保留完整矩形与两轴缩放。

对比度按 [W3C WCAG 相对亮度与对比度定义](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum)计算不透明 sRGB 两色；普通文字 AA ≥ 4.5、AAA ≥ 7，大号文字 AA ≥ 3、AAA ≥ 4.5，判断使用未舍入比值。大号为至少 18pt，或粗体 14pt。依次取两色复用同一张冻结截图：第一次确认前景、第二次确认背景并结束；此流程暂时覆盖连续取色行为，不改变其偏好。Esc 结束时已确认的一色仍保留。前景与背景也随偏好保存。

JSON 导入只接受 fruler version 1 导出格式，文件最多 2 MB、4096 色。整份校验通过后才预览，取消不修改调色板。相同 RGB 按所选规则保留已有或覆盖名称、收藏与分组；不同颜色即使同名也均保留。文件内重复 RGB、损坏条目、HEX / RGB 不一致或不支持的版本会整份拒绝，防止部分导入。批量代码按调色板顺序输出，不把名称拼入代码。

最近记录删除或清空不会删除调色板；从调色板删除也不会移除最近记录。取消收藏仍保留调色板条目，删除请使用「从调色板删除」。JSON 保留名称、RGB、HEX、收藏及分组；CSS 使用 `--fruler-1` 等编号变量，不将用户名称拼入 CSS 语法。

### 第五版的分组与图片约定

每个 RGB 颜色在我的调色板中只有一个条目，归属一个分组；未分组使用空字符串表示。分组名称为 1–60 个字符且不能重复。解散分组仅把颜色移到未分组，不删除颜色。旧版无 group 字段的条目自动迁移到未分组。JSON version 1 新增可选 group 字段，导入时自动建立分组，同名分组合并；旧版导出仍可导入。选中非空分组且清空搜索后导出，即为整组文件；空分组没有颜色可导出。分组列表和色卡顺序持久化，当前筛选条件不持久化。指定分组排序不会改变其他颜色的相对顺序。

图片文件最多 32 MB、1600 万像素，单边最多 16384 像素，超限会明确拒绝，不静默缩小。PNG / JPEG / WebP 使用 Flutter 解码器读取，动画 WebP 仅取第一帧。透明度统一合成到白底，再以不透明 sRGB 像素显示、取样和测量，原始文件不被修改。图片视图的 100% 表示 1 个图片像素占 1 个 Flutter 逻辑像素，与屏幕倍率无关；导出仍按原图像素绘制，不按视图缩放。

图片工具复用 Dart 会话和测量规则，持续点击取色、拖拽测量会保留结果。图片标注支持与屏幕标注相同的移动、缩放、单条删除和撤销；选中后仅导出该框，否则导出全部框。PNG 包含尺寸标签与边距，小图允许把标签排在图片区域之外以保持可读，原图本身不被放大。图片测量记录以 imageSource=true 标识，显示和复制只使用 px；历史 JSON / CSV 中的逻辑尺寸采用 1:1 图片坐标约定，并非 Mac 显示器的物理点尺寸。

图片内容和标注不写入偏好设置；颜色与数值测量历史仍正常保存。切换页面或启动屏幕工具会保留图片草稿、选择状态和撤销 / 重做历史，返回图片工作区后继续编辑。原始文件访问仅使用用户选择或拖入的文件权限，不请求整盘访问。

### 第六版的项目与编辑历史

「保存项目」通过系统面板写入 `.fruler` 文件，包含白底合成 PNG、图片名称、标注坐标、当前工具、倍率、容差、缩放和平移位置，无需原始图片即可恢复。「打开项目」完整校验后才替换当前图片，不重复添加测量历史。项目不包含调色板、偏好设置、屏幕历史或撤销 / 重做栈；重新打开后从保存的标注状态开始编辑。当前通过工作区按钮打开项目，不提供 Finder 双击打开。

未保存的图片项目显示提示，替换图片、关闭图片或退出应用前可选择保存、放弃或取消。保存面板取消或写入失败保留当前内容；保存期间的新视图变化仍标为未保存。关闭主窗口仅隐藏窗口，不丢弃草稿。

项目 JSON 格式为 `dev.fruler.image-project`、版本 1，最多 128 MiB，内嵌 PNG 最多 96 MiB；图片仍限制 1600 万像素、单边 16384，最多 4096 个标注。未知版本、尺寸不符、重复编号、越界或损坏内容整份拒绝并保留原文档。普通图片导入仍限制 32 MB。

屏幕和图片标注共用撤销 / 重做规则：添加、删除、清空、移动和调尺寸均可往返；一次拖拽合并为一次操作，键盘调整按次记录。新编辑清空重做分支，每侧最多保留 64 个状态。屏幕新捕获重置历史，图片切到屏幕工具时保留自己的历史。此功能作用于标注，不撤销取色、调色板或测量历史管理。

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

测试覆盖核心算法、应用会话、调色板分组迁移 / 排序 / 搜索、图片解码与坐标、透明区域、缩放平移和桌面布局，使用 `FakeDesktop` 隔离原生服务，不需要录屏权限或启动真实捕获浮层。它们不能代替屏幕授权、多屏缩放、全屏应用覆盖和实际全局快捷键的实机验收。

单实例回归提取生产锁实现，以独立进程验证互斥和退出释放，不启动界面；macOS 原生 PNG 渲染回归使用合成图像，不读取真实屏幕，校验裁剪、方向、颜色与无效标注。需要系统 `python3` 和 Xcode 的 Swift 工具链：

```sh
python3 tool/test_annotation_export.py
python3 tool/test_single_instance.py
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
    palette.dart                  # 命名、收藏、导入合并与 JSON / CSS / Flutter 输出
    contrast.dart                 # sRGB 相对亮度与 WCAG 对比度
    pixel_frame.dart              # RGBA 帧、像素取样、逻辑坐标与像素换算
    ruler.dart                    # 测量模式、半开矩形和颜色边界检测
    capture_controls.dart         # 倍率、容差与逐像素坐标微调
    shortcut.dart                 # 平台无关的快捷键配置与序列化
    image_project.dart            # 自包含图片项目、版本与严格校验
    core.dart                     # 核心类型导出
  app/
    app_controller.dart           # 工具会话、取消与提交、历史和偏好设置
  platform/
    desktop_service.dart          # 平台接口、macOS 通道适配、不支持平台的实现
    image_document.dart           # Flutter 图片解码、白底合成与原图标注 PNG 渲染
  ui/
    fruler_app.dart                # 取色器、尺子、偏好设置和绘制组件
    palette_widgets.dart          # 颜色编辑对话框、色卡菜单与导出入口
    v4_widgets.dart               # 对比度、导入预览、批量复制与历史管理
    v5_widgets.dart               # 分组、拖动排序与可缩放平移的图片工作区
    v6_widgets.dart               # 未保存项目的保存、放弃与取消确认
macos/
  Runner/
    MainFlutterWindow.swift       # 原生桥接、截图、浮层、菜单栏和快捷键
    AppDelegate.swift             # 生命周期、常驻行为及跨副本进程锁
    Configs/AppInfo.xcconfig      # 产品名和 Release 应用标识
    Info.plist                    # 应用元数据与屏幕权限用途说明
  Runner.xcodeproj/               # 原生工程与各构建配置
  Runner.xcworkspace/             # Xcode 工作区入口
test/
  core/                           # 颜色、坐标、缩放和边界算法测试
  app/                            # 会话、复制、权限错误和历史恢复测试
  ui/                             # 桌面布局与导航测试
  fake_desktop.dart               # 测试用平台服务
  fixtures/                       # 已知颜色和透明区域的无损图片夹具
  macos/                          # PNG 渲染合成图像回归夹具
tool/
  generate_icon.swift             # 可重复执行的 macOS 图标生成脚本
  test_annotation_export.py       # 调用生产 PNG 渲染实现执行原生回归
  test_single_instance.py         # 跨进程验证生产实例锁
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
| `openImageFile()` | 通过系统文件选择器返回 ImageFileData(name, bytes)，取消返回 null，文件最多 32 MB；解码、像素上限检查与图片交互由 Flutter 承担 |
| `openProjectFile()` / `saveProjectFile(text)` | 系统面板读取 UTF-8 项目或原子保存；读取取消返回 null，保存取消返回 false，失败抛错；Dart 校验内容 |
| `replyToQuit(allow)` | 响应 quitRequested，等待 Flutter 完成未保存确认后继续或取消退出 |
| `exportImage(png, save)` | 保存 Flutter 渲染的原图标注 PNG，或写入图片剪贴板；取消返回 false，失败抛错 |
| `openPaletteFile()` | 通过系统文件对话框读取用户选中的 UTF-8 JSON；取消返回 null，限制 2 MB；内容由 Dart 完整校验并预览 |
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
- 第六版新增 `redoPins` 会话事件及 `updateOverlay.canRedoPins`；平台提供撤销 / 重做按钮与快捷键。全局 `quitRequested` 挂起退出，收到 `replyToQuit(allow)` 后继续或取消。图片项目与编辑历史在 Dart 中实现，新平台只需接入文件面板和退出握手。图片画布支持 Control Z / Control Shift Z / Control S。
- 本地 JSON 继续使用 `fruler.state.v1`，新增可选 `continuousPicker` 和 `palette[]`；缺失时按旧版本迁移，单条损坏记录独立跳过。调色板条目包含 `color`、`name` 和 `favorite`，不存屏幕图像。
- 第四版 `pinDrag` 包含 `id`、`displayId`、`phase: start/update/end`；update/end 的 `dx/dy` 为相对手势起点的本屏逻辑坐标位移，`handle` 为 move/n/s/e/w/ne/nw/se/sw。Dart 按该屏 scaleX/scaleY 换算截图像素并限制边界。`nudge` 新增 `resize` 布尔值，仅在编辑状态调整选中框；旧平台不发送时默认移动。
- `updateOverlay.capturePurpose` 显示本次前景 / 背景取色用途；非空时隐藏连续取色切换。第四版 JSON 新增可选 contrastForeground / contrastBackground，以及测量记录 name / favorite；旧数据默认黑白对比、未命名和未收藏。
- 第五版原生拖入图片事件为 imageDropped(name, bytes)，bytes 使用 Uint8List / FlutterStandardTypedData；失败用 imageDropFailed(message)。平台仅读取用户明确拖入的单个文件，Dart 再完整校验。新增平台只需实现文件选择、拖入及图片保存 / 剪贴板接口，即可复用图片工作区，无需为它接入屏幕捕获权限。
- 图片使用独立的负会话 ID 和 displayId=0，1:1 的 PixelFrame；输入、标注及撤销规则复用控制器，浮层更新在 Flutter 内渲染，不调用原生 begin/updateOverlay/finish。屏幕会话保持原契约。新数据可选 paletteGroups[]、PaletteEntry.group 和 MeasurementRecord.imageSource，旧值缺省仍兼容。
- 新平台应在创建引擎及系统服务之前实现同等的单实例保护与激活已有窗口机制；macOS 当前使用沙盒容器内的 flock，不能直接复制文件路径假设到 Windows / Linux。
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
