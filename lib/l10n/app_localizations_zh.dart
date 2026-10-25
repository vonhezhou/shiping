// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'fruler';

  @override
  String get uiModeRectangle => '矩形';

  @override
  String get uiModeHorizontal => '水平';

  @override
  String get uiModeVertical => '垂直';

  @override
  String get uiModeCross => '交叉';

  @override
  String get uiBackToHistory => '返回历史';

  @override
  String get uiPreferences => '偏好设置';

  @override
  String get uiScreenWorkflow => '在屏幕上完成操作，复制或保存后回到原应用。';

  @override
  String get uiColorHistory => '取色历史';

  @override
  String get uiMeasurementHistory => '测量历史';

  @override
  String get uiScreenshotHistory => '截图历史';

  @override
  String get uiNoColors => '还没有取色记录';

  @override
  String get uiNoColorsDescription => '在屏幕上取色后自动复制，最近颜色显示在这里。';

  @override
  String get uiNoScreenshots => '还没有截图记录';

  @override
  String get uiNoScreenshotsDescription => '完成的截图暂存在本次运行中，点击即可重新复制。';

  @override
  String get uiPreferencesIndex => '03 / 偏好设置';

  @override
  String get uiPreferencesHeading => '按你的习惯工作';

  @override
  String get uiPreferencesDescription => '轻量常驻，随时就绪。';

  @override
  String get uiScreenAccess => '屏幕访问';

  @override
  String get uiScreenPermissionGranted => '已获得屏幕录制权限';

  @override
  String get uiScreenPermissionNeeded => '需要允许 fruler 录制屏幕';

  @override
  String get uiScreenPrivacy =>
      '取色、尺子与截图工具冻结快照，结束后释放。录屏持续采集所选范围，停止后保存到你选择的位置。所有内容均在本机处理，不上传。';

  @override
  String get uiRecheckPermission => '重新检查权限';

  @override
  String get uiRequestPermission => '请求屏幕授权';

  @override
  String get uiOpenSystemSettings => '打开系统设置 ↗';

  @override
  String get uiColorPicking => '取色';

  @override
  String get uiCopyFormat => '复制格式';

  @override
  String get uiContinuousPicker => '连续取色';

  @override
  String get uiContinuousPickerDescription => '每次取色立即复制，Esc 结束';

  @override
  String get uiEdgeDetection => '边界识别';

  @override
  String get uiColorTolerance => '颜色容差';

  @override
  String get uiToleranceDescription => '每个 RGB 通道与光标像素比较。容差越小，边界识别越严格。';

  @override
  String get uiToleranceExact => '0 · 精确匹配';

  @override
  String get uiToleranceLoose => '255 · 宽松匹配';

  @override
  String get uiKeyboardShortcuts => '快捷操作';

  @override
  String get uiCancelTool => '取消当前工具';

  @override
  String get uiCancelToolKeys => 'Esc（取色右键可自定义）';

  @override
  String get uiShortcutsUnavailable => '全局快捷键未全部注册，可能已被其他应用占用。仍可使用窗口或菜单栏入口。';

  @override
  String get uiAbout => 'fruler 0.10.0 · macOS 14+';

  @override
  String get uiScreenshotAndAnnotate => '截图并标注';

  @override
  String get uiColorPicker => '取色器';

  @override
  String get uiRectangleMeasurement => '矩形测量';

  @override
  String get uiPermissionBanner => '首次使用需要屏幕录制权限，才能读取屏幕上的像素。';

  @override
  String get uiGoToPermission => '前往授权 →';

  @override
  String get uiDismissMessage => '关闭提示';

  @override
  String get uiClearHistory => '清空记录';

  @override
  String get uiShortcutInstructions => '按下修饰键与一个字母或数字的组合。需要包含 ⌘、⌃ 或 ⌥；支持附加 ⇧。';

  @override
  String get uiShortcutWaiting => '等待按键…';

  @override
  String get uiShortcutSaveHint => '按 Enter 保存，Esc 取消。系统保留或已占用的组合无法保存。';

  @override
  String get uiCancel => '取消';

  @override
  String get uiSave => '保存';

  @override
  String get uiName => '名称';

  @override
  String get uiSaveName => '保存名称';

  @override
  String get uiMeasurementRecords => '测量记录';

  @override
  String get uiMeasurementSearch => '搜索名称、尺寸、显示器或日期';

  @override
  String get uiFavoritesOnly => '只看收藏';

  @override
  String get uiNoMeasurements => '暂无匹配记录';

  @override
  String get uiNoMeasurementsDescription =>
      '测量后保留像素、逻辑尺寸及显示器缩放；收藏优先保留，仍计入历史上限。';

  @override
  String get uiUnfavoriteMeasurement => '取消收藏测量';

  @override
  String get uiFavoriteMeasurement => '收藏测量';

  @override
  String get uiOriginalPixels => '原图像素';

  @override
  String get uiMeasurementActions => '测量记录操作';

  @override
  String get uiNameMeasurement => '命名测量';

  @override
  String get uiCopyDimensions => '复制尺寸';

  @override
  String get uiDeleteRecord => '删除记录';

  @override
  String get uiSearchFonts => '搜索字体';

  @override
  String get uiNoMatchingFonts => '没有匹配的字体';

  @override
  String get uiFontLoadingFailed => '系统字体读取失败，请重新框选后重试';

  @override
  String get uiScreenshotLoadingFailed => '截图加载失败，请重新框选';

  @override
  String get uiNoSystemFonts => '暂无可用系统字体';

  @override
  String get uiFontSize => '字号';

  @override
  String get uiColorPanelFailed => '无法打开系统调色盘，请重试';

  @override
  String get uiCustomColor => '自定义颜色';

  @override
  String get uiMosaicSize => '色块大小';

  @override
  String get uiBlurStrength => '模糊程度';

  @override
  String get uiBrushWidth => '画笔宽度';

  @override
  String get uiRectangleEraser => '框选擦除';

  @override
  String get uiFillShape => '填充形状';

  @override
  String get uiEllipse => '椭圆';

  @override
  String get uiLineTooltip => '直线 / 折线 · Tab 切换箭头';

  @override
  String get uiArrowTooltip => '箭头 · Tab 切换直线';

  @override
  String get uiRectangleSelection => '框选';

  @override
  String get uiMosaic => '马赛克';

  @override
  String get uiGaussianBlur => '高斯模糊';

  @override
  String get uiBold => '粗体';

  @override
  String get uiItalic => '斜体';

  @override
  String get uiTextOutline => '文字描边（自动黑白对比色）';

  @override
  String get uiEditText => '编辑文字';

  @override
  String get uiShapeTools => '形状：矩形 / 椭圆';

  @override
  String get uiLineTools => '直线 / 折线 / 箭头';

  @override
  String get uiPencil => '画笔';

  @override
  String get uiMarker => '荧光笔';

  @override
  String get uiEffectTools => '马赛克 / 高斯模糊';

  @override
  String get uiText => '文字';

  @override
  String get uiEraserTools => '橡皮擦 · 框选 / 画笔局部擦除';

  @override
  String get uiUndo => '撤销 ⌘Z';

  @override
  String get uiRedo => '重做 ⌘Y / ⇧⌘Z';

  @override
  String get uiDeleteSelected => '删除选中 Delete';

  @override
  String get uiCancelScreenshot => '取消 Esc';

  @override
  String get uiSavePng => '保存 PNG ⌘S';

  @override
  String get uiCopyAndFinish => '复制并完成 ↵';

  @override
  String get uiCaptureCopyHint => 'C 复制颜色 · M 复制尺寸';

  @override
  String uiStartPicker(String shortcut) {
    return '取色器 · $shortcut';
  }

  @override
  String uiStartRuler(String shortcut) {
    return '尺子 · $shortcut';
  }

  @override
  String uiStartScreenshot(String shortcut) {
    return '截图 · $shortcut';
  }

  @override
  String uiShortcutTitle(String tool) {
    return '设置$tool快捷键';
  }

  @override
  String uiExportCurrentResults(String format) {
    return '导出当前结果 $format';
  }

  @override
  String uiMeasurementDetails(
    String dimensions,
    String mode,
    String display,
    String scaleX,
    String scaleY,
    String date,
  ) {
    return '$dimensions · $mode · $display\n缩放 $scaleX × $scaleY · $date';
  }

  @override
  String uiLineWidthTooltip(int width) {
    return '线宽 $width pt · 滚轮 / 1、2 / [、]';
  }

  @override
  String uiFontFamilyTooltip(String family) {
    return '字体：$family';
  }

  @override
  String uiCaptureRegion(int width, int height) {
    return '区域: $width × $height px';
  }

  @override
  String uiParameterTooltip(String label, int value, String unit) {
    return '$label · $value$unit';
  }

  @override
  String uiParameterValue(String label, int value) {
    return '$label $value';
  }

  @override
  String get uiLanguage => '语言';

  @override
  String get uiLanguageDescription => '选择窗口、工具和菜单的显示语言。';

  @override
  String get uiLanguageSystem => '跟随系统';

  @override
  String get uiLanguageChinese => '简体中文';

  @override
  String get uiLanguageEnglish => 'English';

  @override
  String msgScreenshotSelectionFailed(String detail) {
    return '截图区域调整失败：$detail';
  }

  @override
  String get msgScreenshotSaved => '截图已保存';

  @override
  String get msgScreenshotCopied => '截图已复制';

  @override
  String get msgCopiedScreenshot => '已复制截图';

  @override
  String msgScreenshotExportFailed(String detail) {
    return '截图导出失败：$detail';
  }

  @override
  String get msgGroupNameInvalid => '分组名称需为 1–60 个字符，且不能重复';

  @override
  String get msgOutputRequired => '至少保留一种启用的颜色格式';

  @override
  String get msgDesktopDisconnected => '系统工具连接中断，请重新打开 fruler。';

  @override
  String get msgPlatformUnsupported => '当前版本支持 macOS 14 及以上，其他平台的适配尚未实现。';

  @override
  String get msgPermissionGranted => '屏幕访问已授权，可以开始使用。';

  @override
  String get msgPermissionDenied => '请在系统设置中允许 fruler 录制屏幕，然后返回重试。';

  @override
  String msgScreenshotFailed(String detail) {
    return '截图失败：$detail';
  }

  @override
  String get msgMacOSRequired => '当前版本仅支持 macOS 14 及以上。';

  @override
  String msgPickingFinished(int count) {
    return '取色已结束，已采集 $count 次';
  }

  @override
  String get msgCancelled => '已取消';

  @override
  String msgPickerActions(String primary, String middle, String secondary) {
    return '左键：$primary · 中键：$middle · 右键：$secondary';
  }

  @override
  String get msgConfirmActions => '左键 / Enter 确认 · 右键取消';

  @override
  String get msgPickForeground => '选取前景色';

  @override
  String get msgPickBackground => '选取背景色';

  @override
  String get msgDragScreenshot => '拖动框选截图';

  @override
  String get msgDragMeasurement => '按住并拖拽，测量矩形区域';

  @override
  String get msgPickingCancelled => '已取消取色';

  @override
  String msgPickerFinishFailed(String detail) {
    return '无法关闭取色浮层：$detail';
  }

  @override
  String msgPickingContinues(int count) {
    return '已连续取色 $count 次，Esc 结束';
  }

  @override
  String msgColorClipboardFailed(String detail) {
    return '颜色已保存，但复制失败：$detail';
  }

  @override
  String msgMeasurementsRetained(int count) {
    return '已保留 $count 个测量框，并复制尺寸';
  }

  @override
  String msgMeasurementClipboardFailed(String detail) {
    return '标注已保留，但复制失败：$detail';
  }

  @override
  String msgCopied(String text) {
    return '已复制 $text';
  }

  @override
  String msgSizeClipboardFailed(String detail) {
    return '尺寸复制失败：$detail';
  }

  @override
  String get msgAnnotationImageExported => '标注图片已导出';

  @override
  String get msgAnnotationImageCopied => '标注图片已复制';

  @override
  String msgAnnotationImageExportFailed(String detail) {
    return '标注图片导出失败：$detail';
  }

  @override
  String msgResultClipboardFailed(String detail) {
    return '结果已保存，但复制失败：$detail';
  }

  @override
  String msgRulerFinishFailed(String detail) {
    return '无法关闭测量浮层，请按 Esc：$detail';
  }

  @override
  String get msgShortcutInvalid => '快捷键需要未被保留的字母或数字、至少一个主修饰键，且各操作不能重复。';

  @override
  String get msgShortcutRegistrationFailed => '快捷键注册失败，已保留原配置。';

  @override
  String get msgShortcutsUpdated => '快捷键已更新';

  @override
  String get msgColorsExported => '颜色已导出';

  @override
  String msgColorsExportFailed(String detail) {
    return '颜色导出失败：$detail';
  }

  @override
  String msgPaletteReadFailed(String detail) {
    return '无法读取调色板文件：$detail';
  }

  @override
  String msgColorsMerged(int count) {
    return '已合并 $count 个颜色';
  }

  @override
  String msgPaletteCodeCopied(int count, String format) {
    return '已复制 $count 色的 $format 代码';
  }

  @override
  String msgMeasurementsExported(int count) {
    return '已导出 $count 条测量记录';
  }

  @override
  String msgMeasurementsExportFailed(String detail) {
    return '测量记录导出失败：$detail';
  }

  @override
  String msgHistorySaveFailed(String detail) {
    return '历史记录保存失败：$detail';
  }

  @override
  String get msgShortcutsRestored => '快捷键配置无效，已恢复默认值。';

  @override
  String get msgHistoryRestoreFailed => '历史记录无法读取，已使用默认设置。';

  @override
  String get msgScreenPermissionRequired => '需要屏幕录制权限。请前往偏好设置授权，再重新打开工具。';

  @override
  String get msgCaptureCancelled => '屏幕状态发生变化，请重新开始。';

  @override
  String get msgShortcutConflict => '快捷键已被占用，已尝试恢复原配置。';

  @override
  String get msgShortcutUnavailable => '此快捷键不可用，请使用其他组合。';

  @override
  String get msgCaptureBusy => '已有工具正在使用，请先按 Esc 退出。';

  @override
  String get msgSystemOperationFailed => '系统操作失败，请重试。';

  @override
  String get msgUnsupportedPlatform => '当前平台尚未支持';

  @override
  String get msgOperationFailed => '操作失败，请重试。';

  @override
  String get msgLocaleChangeFailed => '无法切换语言，已保留原设置。';

  @override
  String get msgPickAndClose => '取色并结束';

  @override
  String get msgPickAndEdit => '取色后打开编辑器';

  @override
  String get msgPickAndContinue => '取色并继续';

  @override
  String get msgCancelPicking => '取消取色';

  @override
  String get validationAnnotationCount => '通用标注数量无效';

  @override
  String get validationAnnotationInvalid => '通用标注无效';

  @override
  String get validationAnnotationStyle => '通用标注类型或样式无效';

  @override
  String get validationAnnotationPoints => '标注笔画过多';

  @override
  String get validationAnnotationCoordinates => '标注坐标无效';

  @override
  String get validationAnnotationBounds => '标注超出图片边界';

  @override
  String get validationAnnotationEndpoints => '标注端点数量无效';

  @override
  String get validationAnnotationLimit => '标注达到数量上限，请删除部分标注';

  @override
  String get validationHexColor => '请输入 3 位或 6 位 HEX 颜色';

  @override
  String get validationHslValue => 'HSL 颜色值无效';

  @override
  String get validationRgbValue => 'RGB 颜色值无效';

  @override
  String get validationPaletteEntry => '调色板颜色条目无效';

  @override
  String get validationPaletteVersion => '请选择 fruler 导出的 version 1 JSON 文件';

  @override
  String get validationPaletteLimit => '一次最多导入 4096 个颜色';

  @override
  String get validationPaletteMetadata => '颜色条目的名称或收藏状态无效';

  @override
  String get validationPaletteChannels => 'HEX 与 RGB 不一致，未导入任何颜色';

  @override
  String get validationPaletteDuplicates => '文件含重复颜色，请先去重';

  @override
  String get validationOutputInvalid => '颜色格式数据无效';

  @override
  String get validationOutputName => '格式名称需为 1–40 个字符';

  @override
  String get validationOutputTemplate => '模板需为 1–1024 个字符，不能包含控制字符';

  @override
  String get validationOutputSubstitution => '模板至少需要一个颜色占位符';

  @override
  String get validationPickerBehavior => '取色动作数据无效';

  @override
  String get validationOutputLimit => '最多保留 24 种颜色格式';

  @override
  String get validationOutputNameDuplicate => '格式名称不能重复';

  @override
  String get validationImageSize => '图片最多 1600 万像素，单边不超过 16384 像素';

  @override
  String get validationImageFormat => '仅支持 PNG、JPEG 和 WebP 图片';

  @override
  String get validationImageDecode => '无法解码图片';

  @override
  String get validationImageAnnotationsEmpty => '没有可导出的图片标注';

  @override
  String get validationImageExport => '图片导出失败';

  @override
  String get validationShortcut => '快捷键无效';

  @override
  String get validationShortcutBindings => '快捷键配置无效';

  @override
  String get validationShortcutDuplicates => '各操作的快捷键不能重复';

  @override
  String validationOutputPlaceholder(String token) {
    return '未知占位符：%$token';
  }

  @override
  String validationImageFileLimit(int limit) {
    return '图片文件不能超过 $limit MB';
  }

  @override
  String get uiOptionsTitle => '选项';

  @override
  String get uiGeneral => '常规';

  @override
  String get uiGeneralDescription => '语言、全局快捷键和屏幕访问权限。';

  @override
  String get uiRuler => '尺子';

  @override
  String get uiScreenshot => '截图';

  @override
  String get uiPickerDescription => '在屏幕上取色并立即复制，按你的习惯设置复制格式与放大镜。';

  @override
  String get uiRulerDescription => '在屏幕上测量像素和逻辑尺寸，设置默认模式与边界识别容差。';

  @override
  String get uiScreenshotDescription => '在同一个全屏浮层框选、标注并复制、保存或贴出截图。';

  @override
  String get uiPickerOptions => '取色选项';

  @override
  String get uiMagnification => '放大倍率';

  @override
  String get uiMagnificationDescription => '使用工具时也可通过滚轮调整，支持 4×–32×。';

  @override
  String get uiRulerOptions => '测量选项';

  @override
  String get uiDefaultMode => '默认模式';

  @override
  String get uiDefaultModeDescription => '尺子启动时使用所选模式；工具内按 1–4 也可切换。';

  @override
  String get uiScreenshotWorkflow => '截图与标注';

  @override
  String get uiScreenshotSelect => '框选屏幕区域，可单击吸附窗口或拖动框选。';

  @override
  String get uiScreenshotAnnotate => '在原位添加形状、画笔、文字或模糊，选区可继续调整。';

  @override
  String get uiScreenshotFinish => '复制、保存或贴图成功后返回原应用；取消保存会继续标注。';

  @override
  String get uiScreenshotHistoryStorage =>
      '仅保留本次运行最近 12 张截图，总计不超过 64 MiB；退出应用后释放。';

  @override
  String get uiColorHistoryStorage => '最近颜色保存在本机，按配置的上限保留，点击即可再次复制。';

  @override
  String get uiAboutTitle => '关于';

  @override
  String get uiOptionsSidebarHint => '通过快捷键或菜单栏，在屏幕上启动工具。';

  @override
  String get uiCopyScreenshotFromHistory => '再次复制截图';

  @override
  String get uiScreenshotCurrentSession => '仅本次运行';

  @override
  String uiHistoryItemCount(int count) {
    return '$count 条';
  }

  @override
  String uiScreenshotPreview(int index) {
    return '截图 $index';
  }

  @override
  String get uiHistoryLimit => '历史记录上限';

  @override
  String get uiColorHistoryLimitHint => '超过上限时自动移除最旧颜色；调低上限会立即精简已有历史。';

  @override
  String get uiMeasurementHistoryLimitHint =>
      '始终保留最新测量，其余优先保留收藏；超限时先移除最旧未收藏记录，没有时移除最旧收藏。调低上限立即生效。';

  @override
  String get uiMouseActions => '鼠标动作';

  @override
  String get uiMouseActionsHint => '分别设置中键与右键的取色动作；左键由连续取色开关控制，Esc 始终可退出。';

  @override
  String get uiMouseMiddle => '鼠标中键';

  @override
  String get uiMouseRight => '鼠标右键';

  @override
  String get uiColorFormats => '颜色格式';

  @override
  String get uiColorFormatsHint => '配置可选的复制格式与模板。至少保留一种启用的格式。';

  @override
  String get uiAddColorFormat => '添加格式';

  @override
  String get uiEditColorFormat => '编辑颜色格式';

  @override
  String get uiFormatTemplate => '格式模板';

  @override
  String get uiFormatTemplateHint =>
      'RGB 通道：%Re、%Gr、%Bl；两位大写十六进制：%ReX、%GrX、%BlX；小写使用 x，百分号使用 %% 。';

  @override
  String get uiFormatPreview => '复制预览';

  @override
  String get uiEdit => '编辑';

  @override
  String get uiMoveUp => '上移';

  @override
  String get uiMoveDown => '下移';

  @override
  String get uiFormatActions => '格式操作';

  @override
  String get uiDeleteColorFormat => '删除格式';

  @override
  String get uiPinScreenshot => '贴到屏幕（⌘T）';

  @override
  String get uiPinClipboard => '剪贴板贴图';

  @override
  String get uiTogglePins => '显示／隐藏全部贴图';

  @override
  String get uiClosePins => '销毁全部贴图';

  @override
  String get uiPinnedImages => '贴图';

  @override
  String get uiPinHistory => '贴出这张截图';

  @override
  String get uiPinDescription =>
      '将截图、剪贴板图片、文字或 HEX 颜色贴在其他窗口上方。拖动移动，滚轮缩放，⌘滚轮调透明度；1／2 旋转，3／4 翻转，中键重置。Esc 或双击隐藏，Shift+Esc 销毁；隐藏的贴图可一起恢复。贴图仅保留到退出应用。';

  @override
  String get msgImagePinned => '已贴到屏幕';

  @override
  String get uiRecording => '录屏';

  @override
  String get uiRecordingDescription => '录制前选择屏幕范围，通过菜单栏或本页停止后保存 MP4 视频。';

  @override
  String get uiStartRecording => '选择录制范围';

  @override
  String get uiStopRecording => '停止并保存';

  @override
  String get uiRecordingOptions => '视频参数';

  @override
  String get uiRecordingCodec => '视频编码';

  @override
  String get uiRecordingH264 => 'H.264 · 兼容性好';

  @override
  String get uiRecordingHevc => 'HEVC · 文件更小';

  @override
  String get uiRecordingFrameRate => '帧率';

  @override
  String get uiRecordingQuality => '视频质量';

  @override
  String get uiRecordingQualityLow => '低 · 文件较小';

  @override
  String get uiRecordingQualityMedium => '中';

  @override
  String get uiRecordingQualityHigh => '高 · 画面更清晰';

  @override
  String get uiRecordingResolution => '输出尺寸';

  @override
  String get uiRecordingOriginal => '原始像素';

  @override
  String get uiRecordingResolutionHint =>
      '720p / 1080p 分别限制在 1280 × 720 / 1920 × 1080 内，保持选区比例，不放大小选区。';

  @override
  String get uiRecordingCursor => '录制鼠标指针';

  @override
  String get uiRecordingAudio => '录制系统声音';

  @override
  String get uiRecordingAudioHint => '包含其他应用播放的声音，不录制麦克风。';

  @override
  String get uiRecordingWorkflow => '录制与保存';

  @override
  String get uiRecordingSelect => '在一块显示器上拖动选择范围，松开鼠标开始录制；Esc 取消选区。';

  @override
  String get uiRecordingFinish => '通过菜单栏或本页停止录制，再选择 MP4 保存位置。取消保存会丢弃本次录屏。';

  @override
  String get uiRecordingSettingsHint => '参数用于下一次录制，录制过程中不可调整。';

  @override
  String get uiRecordingActive => '正在录屏';

  @override
  String get uiRecordingWorking => '正在处理录屏…';

  @override
  String get msgRecordingStarted => '录屏已开始，通过菜单栏可停止。';

  @override
  String get msgRecordingSaved => '录屏已保存';

  @override
  String get msgRecordingDiscarded => '已丢弃本次录屏';

  @override
  String msgRecordingFailed(String detail) {
    return '录屏失败：$detail';
  }

  @override
  String get msgRecordingSelectRegion => '拖动选择录制范围';

  @override
  String get uiRecognizeQrCode => '识别选区二维码';

  @override
  String get uiQrCodeRecognizing => '正在识别选区内的二维码…';

  @override
  String get uiQrCodeCopying => '正在复制二维码内容…';

  @override
  String get uiQrCodeResults => '选择要复制的二维码';

  @override
  String get uiQrCodeResultsDescription => '选区内有多个二维码，请核对内容后选择。';

  @override
  String get uiQrCodeRetryDescription => '点击内容重试复制。';

  @override
  String get uiQrCodeAdjustSelection => '返回调整选区';

  @override
  String get msgQrCodeNotFound => '选区内未识别到二维码，请调整范围并保留二维码完整边缘后重试。';

  @override
  String get msgQrCodeRecognitionFailed => '二维码识别失败，请重试。';

  @override
  String get msgQrCodeCopyFailed => '二维码内容复制失败，请重试。';

  @override
  String get msgQrCodeCopied => '已复制二维码内容';

  @override
  String get msgScreenshotCancelFailed => '截图取消失败，请重试。';
}
