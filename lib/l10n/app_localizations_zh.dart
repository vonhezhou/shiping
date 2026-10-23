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
      '启动工具时冻结屏幕快照，退出后释放，不上传。仅在你复制或导出标注时，将局部图片写入剪贴板或所选文件。';

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
  String get uiCancelToolKeys => 'Esc / 鼠标右键';

  @override
  String get uiShortcutsUnavailable => '全局快捷键未全部注册，可能已被其他应用占用。仍可使用窗口或菜单栏入口。';

  @override
  String get uiAbout => 'fruler 0.10.0 · Flutter 界面与 Dart 测量核心 · macOS 14+';

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
  String get uiNoMeasurementsDescription => '测量后会保留像素、逻辑尺寸及显示器缩放；收藏可长期保留。';

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
  String get msgShortcutInvalid => '快捷键需要字母或数字、至少一个主修饰键，且各工具不能重复。';

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
  String get validationShortcutDuplicates => '各工具的快捷键不能重复';

  @override
  String validationOutputPlaceholder(String token) {
    return '未知占位符：%$token';
  }

  @override
  String validationImageFileLimit(int limit) {
    return '图片文件不能超过 $limit MB';
  }
}
