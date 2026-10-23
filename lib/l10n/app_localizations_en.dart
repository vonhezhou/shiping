// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'fruler';

  @override
  String get uiModeRectangle => 'Rectangle';

  @override
  String get uiModeHorizontal => 'Horizontal';

  @override
  String get uiModeVertical => 'Vertical';

  @override
  String get uiModeCross => 'Cross';

  @override
  String get uiBackToHistory => 'Back to history';

  @override
  String get uiPreferences => 'Preferences';

  @override
  String get uiScreenWorkflow =>
      'Work on screen. Copy or save to return to your previous app.';

  @override
  String get uiColorHistory => 'Color history';

  @override
  String get uiMeasurementHistory => 'Measurement history';

  @override
  String get uiScreenshotHistory => 'Screenshot history';

  @override
  String get uiNoColors => 'No colors yet';

  @override
  String get uiNoColorsDescription =>
      'Pick a screen color to copy it. Recent colors appear here.';

  @override
  String get uiNoScreenshots => 'No screenshots yet';

  @override
  String get uiNoScreenshotsDescription =>
      'Completed screenshots stay here for this session. Click one to copy it again.';

  @override
  String get uiPreferencesIndex => '03 / PREFERENCES';

  @override
  String get uiPreferencesHeading => 'Make it your own';

  @override
  String get uiPreferencesDescription =>
      'Lightweight and ready when you need it.';

  @override
  String get uiScreenAccess => 'Screen access';

  @override
  String get uiScreenPermissionGranted => 'Screen recording access granted';

  @override
  String get uiScreenPermissionNeeded => 'Allow fruler to record the screen';

  @override
  String get uiScreenPrivacy =>
      'Starting a tool freezes a screen snapshot, which is released when you exit. Nothing is uploaded. Only copying or exporting writes the selected image to the clipboard or a file you choose.';

  @override
  String get uiRecheckPermission => 'Check permission again';

  @override
  String get uiRequestPermission => 'Request screen access';

  @override
  String get uiOpenSystemSettings => 'Open System Settings ↗';

  @override
  String get uiColorPicking => 'Color picking';

  @override
  String get uiCopyFormat => 'Copy format';

  @override
  String get uiContinuousPicker => 'Keep picking';

  @override
  String get uiContinuousPickerDescription =>
      'Copy each color immediately; press Esc to finish';

  @override
  String get uiEdgeDetection => 'Edge detection';

  @override
  String get uiColorTolerance => 'Color tolerance';

  @override
  String get uiToleranceDescription =>
      'Each RGB channel is compared with the pixel under the cursor. Lower tolerance produces stricter edges.';

  @override
  String get uiToleranceExact => '0 · Exact match';

  @override
  String get uiToleranceLoose => '255 · Loose match';

  @override
  String get uiKeyboardShortcuts => 'Keyboard shortcuts';

  @override
  String get uiCancelTool => 'Cancel current tool';

  @override
  String get uiCancelToolKeys => 'Esc / right-click';

  @override
  String get uiShortcutsUnavailable =>
      'Some global shortcuts could not be registered. Another app may be using them. You can still start tools from this window or the menu bar.';

  @override
  String get uiAbout =>
      'fruler 0.10.0 · Flutter interface and Dart measurement engine · macOS 14+';

  @override
  String get uiScreenshotAndAnnotate => 'Screenshot and annotate';

  @override
  String get uiColorPicker => 'Color picker';

  @override
  String get uiRectangleMeasurement => 'Rectangle measurement';

  @override
  String get uiPermissionBanner =>
      'Screen recording permission is required to read screen pixels.';

  @override
  String get uiGoToPermission => 'Grant access →';

  @override
  String get uiDismissMessage => 'Dismiss message';

  @override
  String get uiClearHistory => 'Clear history';

  @override
  String get uiShortcutInstructions =>
      'Press a modifier and a letter or number. Include ⌘, ⌃, or ⌥; ⇧ is optional.';

  @override
  String get uiShortcutWaiting => 'Waiting for keys…';

  @override
  String get uiShortcutSaveHint =>
      'Press Enter to save or Esc to cancel. Reserved shortcuts and combinations already in use cannot be saved.';

  @override
  String get uiCancel => 'Cancel';

  @override
  String get uiSave => 'Save';

  @override
  String get uiName => 'Name';

  @override
  String get uiSaveName => 'Save name';

  @override
  String get uiMeasurementRecords => 'Measurements';

  @override
  String get uiMeasurementSearch => 'Search name, size, display, or date';

  @override
  String get uiFavoritesOnly => 'Favorites only';

  @override
  String get uiNoMeasurements => 'No matching measurements';

  @override
  String get uiNoMeasurementsDescription =>
      'Measurements retain pixel size, logical size, and display scaling. Favorites are kept indefinitely.';

  @override
  String get uiUnfavoriteMeasurement => 'Remove from favorites';

  @override
  String get uiFavoriteMeasurement => 'Add to favorites';

  @override
  String get uiOriginalPixels => 'Original pixels';

  @override
  String get uiMeasurementActions => 'Measurement actions';

  @override
  String get uiNameMeasurement => 'Name measurement';

  @override
  String get uiCopyDimensions => 'Copy dimensions';

  @override
  String get uiDeleteRecord => 'Delete record';

  @override
  String get uiSearchFonts => 'Search fonts';

  @override
  String get uiNoMatchingFonts => 'No matching fonts';

  @override
  String get uiFontLoadingFailed =>
      'Could not load system fonts. Select a new screenshot region and try again.';

  @override
  String get uiScreenshotLoadingFailed =>
      'Could not load the screenshot. Select a new region.';

  @override
  String get uiNoSystemFonts => 'No system fonts available';

  @override
  String get uiFontSize => 'Font size';

  @override
  String get uiColorPanelFailed =>
      'Could not open the system color panel. Please try again.';

  @override
  String get uiCustomColor => 'Custom color';

  @override
  String get uiMosaicSize => 'Mosaic block size';

  @override
  String get uiBlurStrength => 'Blur strength';

  @override
  String get uiBrushWidth => 'Brush width';

  @override
  String get uiRectangleEraser => 'Erase a rectangle';

  @override
  String get uiFillShape => 'Fill shape';

  @override
  String get uiEllipse => 'Ellipse';

  @override
  String get uiLineTooltip => 'Line / polyline · Tab for arrow';

  @override
  String get uiArrowTooltip => 'Arrow · Tab for line';

  @override
  String get uiRectangleSelection => 'Rectangle selection';

  @override
  String get uiMosaic => 'Mosaic';

  @override
  String get uiGaussianBlur => 'Gaussian blur';

  @override
  String get uiBold => 'Bold';

  @override
  String get uiItalic => 'Italic';

  @override
  String get uiTextOutline =>
      'Text outline (automatic black or white contrast)';

  @override
  String get uiEditText => 'Edit text';

  @override
  String get uiShapeTools => 'Shapes: rectangle / ellipse';

  @override
  String get uiLineTools => 'Line / polyline / arrow';

  @override
  String get uiPencil => 'Pencil';

  @override
  String get uiMarker => 'Highlighter';

  @override
  String get uiEffectTools => 'Mosaic / Gaussian blur';

  @override
  String get uiText => 'Text';

  @override
  String get uiEraserTools => 'Eraser · rectangle / brush';

  @override
  String get uiUndo => 'Undo ⌘Z';

  @override
  String get uiRedo => 'Redo ⌘Y / ⇧⌘Z';

  @override
  String get uiDeleteSelected => 'Delete selected · Delete';

  @override
  String get uiCancelScreenshot => 'Cancel · Esc';

  @override
  String get uiSavePng => 'Save PNG ⌘S';

  @override
  String get uiCopyAndFinish => 'Copy and finish ↵';

  @override
  String get uiCaptureCopyHint => 'C Copy color · M Copy dimensions';

  @override
  String uiStartPicker(String shortcut) {
    return 'Color picker · $shortcut';
  }

  @override
  String uiStartRuler(String shortcut) {
    return 'Ruler · $shortcut';
  }

  @override
  String uiStartScreenshot(String shortcut) {
    return 'Screenshot · $shortcut';
  }

  @override
  String uiShortcutTitle(String tool) {
    return 'Set $tool shortcut';
  }

  @override
  String uiExportCurrentResults(String format) {
    return 'Export current results as $format';
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
    return '$dimensions · $mode · $display\nScale $scaleX × $scaleY · $date';
  }

  @override
  String uiLineWidthTooltip(int width) {
    return 'Line width $width pt · Scroll / 1, 2 / [, ]';
  }

  @override
  String uiFontFamilyTooltip(String family) {
    return 'Font: $family';
  }

  @override
  String uiCaptureRegion(int width, int height) {
    return 'Region: $width × $height px';
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
  String get uiLanguage => 'Language';

  @override
  String get uiLanguageDescription =>
      'Choose the language for windows, tools, and menus.';

  @override
  String get uiLanguageSystem => 'System default';

  @override
  String get uiLanguageChinese => '简体中文';

  @override
  String get uiLanguageEnglish => 'English';

  @override
  String msgScreenshotSelectionFailed(String detail) {
    return 'Unable to adjust the capture region: $detail';
  }

  @override
  String get msgScreenshotSaved => 'Screenshot saved';

  @override
  String get msgScreenshotCopied => 'Screenshot copied';

  @override
  String get msgCopiedScreenshot => 'Copied screenshot';

  @override
  String msgScreenshotExportFailed(String detail) {
    return 'Screenshot export failed: $detail';
  }

  @override
  String get msgGroupNameInvalid =>
      'Group names must contain 1–60 characters and be unique';

  @override
  String get msgOutputRequired => 'Keep at least one color format enabled';

  @override
  String get msgDesktopDisconnected =>
      'The system tools disconnected. Reopen fruler.';

  @override
  String get msgPlatformUnsupported =>
      'This version supports macOS 14 and later. Other platforms are not available yet.';

  @override
  String get msgPermissionGranted =>
      'Screen access granted. You can start using the tools.';

  @override
  String get msgPermissionDenied =>
      'Allow fruler to record the screen in System Settings, then try again.';

  @override
  String msgScreenshotFailed(String detail) {
    return 'Screenshot failed: $detail';
  }

  @override
  String get msgMacOSRequired => 'This version requires macOS 14 or later.';

  @override
  String msgPickingFinished(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Color picking finished. # samples collected',
      one: 'Color picking finished. # sample collected',
    );
    return '$_temp0';
  }

  @override
  String get msgCancelled => 'Cancelled';

  @override
  String msgPickerActions(String primary, String middle, String secondary) {
    return 'Left: $primary · Middle: $middle · Right: $secondary';
  }

  @override
  String get msgConfirmActions =>
      'Left click / Enter to confirm · Right click to cancel';

  @override
  String get msgPickForeground => 'Pick foreground color';

  @override
  String get msgPickBackground => 'Pick background color';

  @override
  String get msgDragScreenshot => 'Drag to select a capture region';

  @override
  String get msgDragMeasurement =>
      'Click and drag to measure a rectangular region';

  @override
  String get msgPickingCancelled => 'Color picking cancelled';

  @override
  String msgPickerFinishFailed(String detail) {
    return 'Unable to close the color picker: $detail';
  }

  @override
  String msgPickingContinues(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# colors picked · Esc to finish',
      one: '# color picked · Esc to finish',
    );
    return '$_temp0';
  }

  @override
  String msgColorClipboardFailed(String detail) {
    return 'Color saved, but copying failed: $detail';
  }

  @override
  String msgMeasurementsRetained(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# measurements kept and dimensions copied',
      one: '# measurement kept and its dimensions copied',
    );
    return '$_temp0';
  }

  @override
  String msgMeasurementClipboardFailed(String detail) {
    return 'Annotation kept, but copying failed: $detail';
  }

  @override
  String msgCopied(String text) {
    return 'Copied $text';
  }

  @override
  String msgSizeClipboardFailed(String detail) {
    return 'Unable to copy dimensions: $detail';
  }

  @override
  String get msgAnnotationImageExported => 'Annotated image exported';

  @override
  String get msgAnnotationImageCopied => 'Annotated image copied';

  @override
  String msgAnnotationImageExportFailed(String detail) {
    return 'Annotated image export failed: $detail';
  }

  @override
  String msgResultClipboardFailed(String detail) {
    return 'Result saved, but copying failed: $detail';
  }

  @override
  String msgRulerFinishFailed(String detail) {
    return 'Unable to close the ruler. Press Esc: $detail';
  }

  @override
  String get msgShortcutInvalid =>
      'Use a letter or digit with at least one main modifier. Each tool must have a different shortcut.';

  @override
  String get msgShortcutRegistrationFailed =>
      'Unable to register the shortcut. Previous settings were kept.';

  @override
  String get msgShortcutsUpdated => 'Shortcuts updated';

  @override
  String get msgColorsExported => 'Colors exported';

  @override
  String msgColorsExportFailed(String detail) {
    return 'Color export failed: $detail';
  }

  @override
  String msgPaletteReadFailed(String detail) {
    return 'Unable to read the palette file: $detail';
  }

  @override
  String msgColorsMerged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# colors merged',
      one: '# color merged',
    );
    return '$_temp0';
  }

  @override
  String msgPaletteCodeCopied(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copied $format code for # colors',
      one: 'Copied $format code for # color',
    );
    return '$_temp0';
  }

  @override
  String msgMeasurementsExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# measurements exported',
      one: '# measurement exported',
    );
    return '$_temp0';
  }

  @override
  String msgMeasurementsExportFailed(String detail) {
    return 'Measurement export failed: $detail';
  }

  @override
  String msgHistorySaveFailed(String detail) {
    return 'Unable to save history: $detail';
  }

  @override
  String get msgShortcutsRestored =>
      'Invalid shortcut settings. Defaults were restored.';

  @override
  String get msgHistoryRestoreFailed =>
      'Unable to read history. Default settings are in use.';

  @override
  String get msgScreenPermissionRequired =>
      'Screen recording permission is required. Allow access in Preferences, then reopen the tool.';

  @override
  String get msgCaptureCancelled => 'The screen state changed. Start again.';

  @override
  String get msgShortcutConflict =>
      'The shortcut is already in use. Tried to restore the previous settings.';

  @override
  String get msgShortcutUnavailable =>
      'This shortcut is unavailable. Choose another combination.';

  @override
  String get msgCaptureBusy =>
      'A tool is already active. Press Esc to exit it first.';

  @override
  String get msgSystemOperationFailed =>
      'The system operation failed. Try again.';

  @override
  String get msgUnsupportedPlatform => 'This platform is not supported yet';

  @override
  String get msgOperationFailed => 'The operation failed. Try again.';

  @override
  String get msgLocaleChangeFailed =>
      'Unable to change language. Previous settings were kept.';

  @override
  String get msgPickAndClose => 'Pick and finish';

  @override
  String get msgPickAndEdit => 'Pick and open editor';

  @override
  String get msgPickAndContinue => 'Pick and continue';

  @override
  String get msgCancelPicking => 'Cancel color picking';

  @override
  String get validationAnnotationCount => 'Invalid annotation count';

  @override
  String get validationAnnotationInvalid => 'Invalid annotation';

  @override
  String get validationAnnotationStyle => 'Invalid annotation type or style';

  @override
  String get validationAnnotationPoints => 'Too many annotation points';

  @override
  String get validationAnnotationCoordinates =>
      'Invalid annotation coordinates';

  @override
  String get validationAnnotationBounds =>
      'Annotations are outside the image bounds';

  @override
  String get validationAnnotationEndpoints =>
      'Invalid annotation endpoint count';

  @override
  String get validationAnnotationLimit =>
      'Annotation limit reached. Delete some annotations.';

  @override
  String get validationHexColor => 'Enter a 3-digit or 6-digit HEX color';

  @override
  String get validationHslValue => 'Invalid HSL value';

  @override
  String get validationRgbValue => 'Invalid RGB value';

  @override
  String get validationPaletteEntry => 'Invalid palette entry';

  @override
  String get validationPaletteVersion =>
      'Choose a version 1 JSON file exported by fruler';

  @override
  String get validationPaletteLimit => 'Import up to 4096 colors at a time';

  @override
  String get validationPaletteMetadata =>
      'Invalid color entry name or favorite state';

  @override
  String get validationPaletteChannels =>
      'HEX and RGB do not match. No colors were imported.';

  @override
  String get validationPaletteDuplicates =>
      'The file contains duplicate colors. Remove duplicates first.';

  @override
  String get validationOutputInvalid => 'Invalid color format data';

  @override
  String get validationOutputName =>
      'Format names must contain 1–40 characters';

  @override
  String get validationOutputTemplate =>
      'Templates must contain 1–1024 characters and no control characters';

  @override
  String get validationOutputSubstitution =>
      'A template needs at least one color placeholder';

  @override
  String get validationPickerBehavior => 'Invalid color picker action data';

  @override
  String get validationOutputLimit => 'Keep up to 24 color formats';

  @override
  String get validationOutputNameDuplicate => 'Format names must be unique';

  @override
  String get validationImageSize =>
      'Images can have up to 16 million pixels and no side longer than 16384 pixels';

  @override
  String get validationImageFormat =>
      'Only PNG, JPEG and WebP images are supported';

  @override
  String get validationImageDecode => 'Unable to decode the image';

  @override
  String get validationImageAnnotationsEmpty =>
      'There are no image annotations to export';

  @override
  String get validationImageExport => 'Image export failed';

  @override
  String get validationShortcut => 'Invalid shortcut';

  @override
  String get validationShortcutBindings => 'Invalid shortcut settings';

  @override
  String get validationShortcutDuplicates =>
      'Each tool must have a different shortcut';

  @override
  String validationOutputPlaceholder(String token) {
    return 'Unknown placeholder: %$token';
  }

  @override
  String validationImageFileLimit(int limit) {
    return 'Image files cannot exceed $limit MB';
  }
}
