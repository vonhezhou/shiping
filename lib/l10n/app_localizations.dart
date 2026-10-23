import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'fruler'**
  String get appTitle;

  /// No description provided for @uiModeRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get uiModeRectangle;

  /// No description provided for @uiModeHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get uiModeHorizontal;

  /// No description provided for @uiModeVertical.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get uiModeVertical;

  /// No description provided for @uiModeCross.
  ///
  /// In en, this message translates to:
  /// **'Cross'**
  String get uiModeCross;

  /// No description provided for @uiBackToHistory.
  ///
  /// In en, this message translates to:
  /// **'Back to history'**
  String get uiBackToHistory;

  /// No description provided for @uiPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get uiPreferences;

  /// No description provided for @uiScreenWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Work on screen. Copy or save to return to your previous app.'**
  String get uiScreenWorkflow;

  /// No description provided for @uiColorHistory.
  ///
  /// In en, this message translates to:
  /// **'Color history'**
  String get uiColorHistory;

  /// No description provided for @uiMeasurementHistory.
  ///
  /// In en, this message translates to:
  /// **'Measurement history'**
  String get uiMeasurementHistory;

  /// No description provided for @uiScreenshotHistory.
  ///
  /// In en, this message translates to:
  /// **'Screenshot history'**
  String get uiScreenshotHistory;

  /// No description provided for @uiNoColors.
  ///
  /// In en, this message translates to:
  /// **'No colors yet'**
  String get uiNoColors;

  /// No description provided for @uiNoColorsDescription.
  ///
  /// In en, this message translates to:
  /// **'Pick a screen color to copy it. Recent colors appear here.'**
  String get uiNoColorsDescription;

  /// No description provided for @uiNoScreenshots.
  ///
  /// In en, this message translates to:
  /// **'No screenshots yet'**
  String get uiNoScreenshots;

  /// No description provided for @uiNoScreenshotsDescription.
  ///
  /// In en, this message translates to:
  /// **'Completed screenshots stay here for this session. Click one to copy it again.'**
  String get uiNoScreenshotsDescription;

  /// No description provided for @uiPreferencesIndex.
  ///
  /// In en, this message translates to:
  /// **'03 / PREFERENCES'**
  String get uiPreferencesIndex;

  /// No description provided for @uiPreferencesHeading.
  ///
  /// In en, this message translates to:
  /// **'Make it your own'**
  String get uiPreferencesHeading;

  /// No description provided for @uiPreferencesDescription.
  ///
  /// In en, this message translates to:
  /// **'Lightweight and ready when you need it.'**
  String get uiPreferencesDescription;

  /// No description provided for @uiScreenAccess.
  ///
  /// In en, this message translates to:
  /// **'Screen access'**
  String get uiScreenAccess;

  /// No description provided for @uiScreenPermissionGranted.
  ///
  /// In en, this message translates to:
  /// **'Screen recording access granted'**
  String get uiScreenPermissionGranted;

  /// No description provided for @uiScreenPermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Allow fruler to record the screen'**
  String get uiScreenPermissionNeeded;

  /// No description provided for @uiScreenPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Starting a tool freezes a screen snapshot, which is released when you exit. Nothing is uploaded. Only copying or exporting writes the selected image to the clipboard or a file you choose.'**
  String get uiScreenPrivacy;

  /// No description provided for @uiRecheckPermission.
  ///
  /// In en, this message translates to:
  /// **'Check permission again'**
  String get uiRecheckPermission;

  /// No description provided for @uiRequestPermission.
  ///
  /// In en, this message translates to:
  /// **'Request screen access'**
  String get uiRequestPermission;

  /// No description provided for @uiOpenSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings ↗'**
  String get uiOpenSystemSettings;

  /// No description provided for @uiColorPicking.
  ///
  /// In en, this message translates to:
  /// **'Color picking'**
  String get uiColorPicking;

  /// No description provided for @uiCopyFormat.
  ///
  /// In en, this message translates to:
  /// **'Copy format'**
  String get uiCopyFormat;

  /// No description provided for @uiContinuousPicker.
  ///
  /// In en, this message translates to:
  /// **'Keep picking'**
  String get uiContinuousPicker;

  /// No description provided for @uiContinuousPickerDescription.
  ///
  /// In en, this message translates to:
  /// **'Copy each color immediately; press Esc to finish'**
  String get uiContinuousPickerDescription;

  /// No description provided for @uiEdgeDetection.
  ///
  /// In en, this message translates to:
  /// **'Edge detection'**
  String get uiEdgeDetection;

  /// No description provided for @uiColorTolerance.
  ///
  /// In en, this message translates to:
  /// **'Color tolerance'**
  String get uiColorTolerance;

  /// No description provided for @uiToleranceDescription.
  ///
  /// In en, this message translates to:
  /// **'Each RGB channel is compared with the pixel under the cursor. Lower tolerance produces stricter edges.'**
  String get uiToleranceDescription;

  /// No description provided for @uiToleranceExact.
  ///
  /// In en, this message translates to:
  /// **'0 · Exact match'**
  String get uiToleranceExact;

  /// No description provided for @uiToleranceLoose.
  ///
  /// In en, this message translates to:
  /// **'255 · Loose match'**
  String get uiToleranceLoose;

  /// No description provided for @uiKeyboardShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get uiKeyboardShortcuts;

  /// No description provided for @uiCancelTool.
  ///
  /// In en, this message translates to:
  /// **'Cancel current tool'**
  String get uiCancelTool;

  /// No description provided for @uiCancelToolKeys.
  ///
  /// In en, this message translates to:
  /// **'Esc / right-click'**
  String get uiCancelToolKeys;

  /// No description provided for @uiShortcutsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Some global shortcuts could not be registered. Another app may be using them. You can still start tools from this window or the menu bar.'**
  String get uiShortcutsUnavailable;

  /// No description provided for @uiAbout.
  ///
  /// In en, this message translates to:
  /// **'fruler 0.10.0 · Flutter interface and Dart measurement engine · macOS 14+'**
  String get uiAbout;

  /// No description provided for @uiScreenshotAndAnnotate.
  ///
  /// In en, this message translates to:
  /// **'Screenshot and annotate'**
  String get uiScreenshotAndAnnotate;

  /// No description provided for @uiColorPicker.
  ///
  /// In en, this message translates to:
  /// **'Color picker'**
  String get uiColorPicker;

  /// No description provided for @uiRectangleMeasurement.
  ///
  /// In en, this message translates to:
  /// **'Rectangle measurement'**
  String get uiRectangleMeasurement;

  /// No description provided for @uiPermissionBanner.
  ///
  /// In en, this message translates to:
  /// **'Screen recording permission is required to read screen pixels.'**
  String get uiPermissionBanner;

  /// No description provided for @uiGoToPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant access →'**
  String get uiGoToPermission;

  /// No description provided for @uiDismissMessage.
  ///
  /// In en, this message translates to:
  /// **'Dismiss message'**
  String get uiDismissMessage;

  /// No description provided for @uiClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get uiClearHistory;

  /// No description provided for @uiShortcutInstructions.
  ///
  /// In en, this message translates to:
  /// **'Press a modifier and a letter or number. Include ⌘, ⌃, or ⌥; ⇧ is optional.'**
  String get uiShortcutInstructions;

  /// No description provided for @uiShortcutWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for keys…'**
  String get uiShortcutWaiting;

  /// No description provided for @uiShortcutSaveHint.
  ///
  /// In en, this message translates to:
  /// **'Press Enter to save or Esc to cancel. Reserved shortcuts and combinations already in use cannot be saved.'**
  String get uiShortcutSaveHint;

  /// No description provided for @uiCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get uiCancel;

  /// No description provided for @uiSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get uiSave;

  /// No description provided for @uiName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get uiName;

  /// No description provided for @uiSaveName.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get uiSaveName;

  /// No description provided for @uiMeasurementRecords.
  ///
  /// In en, this message translates to:
  /// **'Measurements'**
  String get uiMeasurementRecords;

  /// No description provided for @uiMeasurementSearch.
  ///
  /// In en, this message translates to:
  /// **'Search name, size, display, or date'**
  String get uiMeasurementSearch;

  /// No description provided for @uiFavoritesOnly.
  ///
  /// In en, this message translates to:
  /// **'Favorites only'**
  String get uiFavoritesOnly;

  /// No description provided for @uiNoMeasurements.
  ///
  /// In en, this message translates to:
  /// **'No matching measurements'**
  String get uiNoMeasurements;

  /// No description provided for @uiNoMeasurementsDescription.
  ///
  /// In en, this message translates to:
  /// **'Measurements retain pixel size, logical size, and display scaling. Favorites are kept indefinitely.'**
  String get uiNoMeasurementsDescription;

  /// No description provided for @uiUnfavoriteMeasurement.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get uiUnfavoriteMeasurement;

  /// No description provided for @uiFavoriteMeasurement.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get uiFavoriteMeasurement;

  /// No description provided for @uiOriginalPixels.
  ///
  /// In en, this message translates to:
  /// **'Original pixels'**
  String get uiOriginalPixels;

  /// No description provided for @uiMeasurementActions.
  ///
  /// In en, this message translates to:
  /// **'Measurement actions'**
  String get uiMeasurementActions;

  /// No description provided for @uiNameMeasurement.
  ///
  /// In en, this message translates to:
  /// **'Name measurement'**
  String get uiNameMeasurement;

  /// No description provided for @uiCopyDimensions.
  ///
  /// In en, this message translates to:
  /// **'Copy dimensions'**
  String get uiCopyDimensions;

  /// No description provided for @uiDeleteRecord.
  ///
  /// In en, this message translates to:
  /// **'Delete record'**
  String get uiDeleteRecord;

  /// No description provided for @uiSearchFonts.
  ///
  /// In en, this message translates to:
  /// **'Search fonts'**
  String get uiSearchFonts;

  /// No description provided for @uiNoMatchingFonts.
  ///
  /// In en, this message translates to:
  /// **'No matching fonts'**
  String get uiNoMatchingFonts;

  /// No description provided for @uiFontLoadingFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load system fonts. Select a new screenshot region and try again.'**
  String get uiFontLoadingFailed;

  /// No description provided for @uiScreenshotLoadingFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the screenshot. Select a new region.'**
  String get uiScreenshotLoadingFailed;

  /// No description provided for @uiNoSystemFonts.
  ///
  /// In en, this message translates to:
  /// **'No system fonts available'**
  String get uiNoSystemFonts;

  /// No description provided for @uiFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get uiFontSize;

  /// No description provided for @uiColorPanelFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the system color panel. Please try again.'**
  String get uiColorPanelFailed;

  /// No description provided for @uiCustomColor.
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get uiCustomColor;

  /// No description provided for @uiMosaicSize.
  ///
  /// In en, this message translates to:
  /// **'Mosaic block size'**
  String get uiMosaicSize;

  /// No description provided for @uiBlurStrength.
  ///
  /// In en, this message translates to:
  /// **'Blur strength'**
  String get uiBlurStrength;

  /// No description provided for @uiBrushWidth.
  ///
  /// In en, this message translates to:
  /// **'Brush width'**
  String get uiBrushWidth;

  /// No description provided for @uiRectangleEraser.
  ///
  /// In en, this message translates to:
  /// **'Erase a rectangle'**
  String get uiRectangleEraser;

  /// No description provided for @uiFillShape.
  ///
  /// In en, this message translates to:
  /// **'Fill shape'**
  String get uiFillShape;

  /// No description provided for @uiEllipse.
  ///
  /// In en, this message translates to:
  /// **'Ellipse'**
  String get uiEllipse;

  /// No description provided for @uiLineTooltip.
  ///
  /// In en, this message translates to:
  /// **'Line / polyline · Tab for arrow'**
  String get uiLineTooltip;

  /// No description provided for @uiArrowTooltip.
  ///
  /// In en, this message translates to:
  /// **'Arrow · Tab for line'**
  String get uiArrowTooltip;

  /// No description provided for @uiRectangleSelection.
  ///
  /// In en, this message translates to:
  /// **'Rectangle selection'**
  String get uiRectangleSelection;

  /// No description provided for @uiMosaic.
  ///
  /// In en, this message translates to:
  /// **'Mosaic'**
  String get uiMosaic;

  /// No description provided for @uiGaussianBlur.
  ///
  /// In en, this message translates to:
  /// **'Gaussian blur'**
  String get uiGaussianBlur;

  /// No description provided for @uiBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get uiBold;

  /// No description provided for @uiItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get uiItalic;

  /// No description provided for @uiTextOutline.
  ///
  /// In en, this message translates to:
  /// **'Text outline (automatic black or white contrast)'**
  String get uiTextOutline;

  /// No description provided for @uiEditText.
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get uiEditText;

  /// No description provided for @uiShapeTools.
  ///
  /// In en, this message translates to:
  /// **'Shapes: rectangle / ellipse'**
  String get uiShapeTools;

  /// No description provided for @uiLineTools.
  ///
  /// In en, this message translates to:
  /// **'Line / polyline / arrow'**
  String get uiLineTools;

  /// No description provided for @uiPencil.
  ///
  /// In en, this message translates to:
  /// **'Pencil'**
  String get uiPencil;

  /// No description provided for @uiMarker.
  ///
  /// In en, this message translates to:
  /// **'Highlighter'**
  String get uiMarker;

  /// No description provided for @uiEffectTools.
  ///
  /// In en, this message translates to:
  /// **'Mosaic / Gaussian blur'**
  String get uiEffectTools;

  /// No description provided for @uiText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get uiText;

  /// No description provided for @uiEraserTools.
  ///
  /// In en, this message translates to:
  /// **'Eraser · rectangle / brush'**
  String get uiEraserTools;

  /// No description provided for @uiUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo ⌘Z'**
  String get uiUndo;

  /// No description provided for @uiRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo ⌘Y / ⇧⌘Z'**
  String get uiRedo;

  /// No description provided for @uiDeleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete selected · Delete'**
  String get uiDeleteSelected;

  /// No description provided for @uiCancelScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Cancel · Esc'**
  String get uiCancelScreenshot;

  /// No description provided for @uiSavePng.
  ///
  /// In en, this message translates to:
  /// **'Save PNG ⌘S'**
  String get uiSavePng;

  /// No description provided for @uiCopyAndFinish.
  ///
  /// In en, this message translates to:
  /// **'Copy and finish ↵'**
  String get uiCopyAndFinish;

  /// No description provided for @uiCaptureCopyHint.
  ///
  /// In en, this message translates to:
  /// **'C Copy color · M Copy dimensions'**
  String get uiCaptureCopyHint;

  /// No description provided for @uiStartPicker.
  ///
  /// In en, this message translates to:
  /// **'Color picker · {shortcut}'**
  String uiStartPicker(String shortcut);

  /// No description provided for @uiStartRuler.
  ///
  /// In en, this message translates to:
  /// **'Ruler · {shortcut}'**
  String uiStartRuler(String shortcut);

  /// No description provided for @uiStartScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Screenshot · {shortcut}'**
  String uiStartScreenshot(String shortcut);

  /// No description provided for @uiShortcutTitle.
  ///
  /// In en, this message translates to:
  /// **'Set {tool} shortcut'**
  String uiShortcutTitle(String tool);

  /// No description provided for @uiExportCurrentResults.
  ///
  /// In en, this message translates to:
  /// **'Export current results as {format}'**
  String uiExportCurrentResults(String format);

  /// No description provided for @uiMeasurementDetails.
  ///
  /// In en, this message translates to:
  /// **'{dimensions} · {mode} · {display}\nScale {scaleX} × {scaleY} · {date}'**
  String uiMeasurementDetails(
    String dimensions,
    String mode,
    String display,
    String scaleX,
    String scaleY,
    String date,
  );

  /// No description provided for @uiLineWidthTooltip.
  ///
  /// In en, this message translates to:
  /// **'Line width {width} pt · Scroll / 1, 2 / [, ]'**
  String uiLineWidthTooltip(int width);

  /// No description provided for @uiFontFamilyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Font: {family}'**
  String uiFontFamilyTooltip(String family);

  /// No description provided for @uiCaptureRegion.
  ///
  /// In en, this message translates to:
  /// **'Region: {width} × {height} px'**
  String uiCaptureRegion(int width, int height);

  /// No description provided for @uiParameterTooltip.
  ///
  /// In en, this message translates to:
  /// **'{label} · {value}{unit}'**
  String uiParameterTooltip(String label, int value, String unit);

  /// No description provided for @uiParameterValue.
  ///
  /// In en, this message translates to:
  /// **'{label} {value}'**
  String uiParameterValue(String label, int value);

  /// No description provided for @uiLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get uiLanguage;

  /// No description provided for @uiLanguageDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the language for windows, tools, and menus.'**
  String get uiLanguageDescription;

  /// No description provided for @uiLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get uiLanguageSystem;

  /// No description provided for @uiLanguageChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get uiLanguageChinese;

  /// No description provided for @uiLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get uiLanguageEnglish;

  /// No description provided for @msgScreenshotSelectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to adjust the capture region: {detail}'**
  String msgScreenshotSelectionFailed(String detail);

  /// No description provided for @msgScreenshotSaved.
  ///
  /// In en, this message translates to:
  /// **'Screenshot saved'**
  String get msgScreenshotSaved;

  /// No description provided for @msgScreenshotCopied.
  ///
  /// In en, this message translates to:
  /// **'Screenshot copied'**
  String get msgScreenshotCopied;

  /// No description provided for @msgCopiedScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Copied screenshot'**
  String get msgCopiedScreenshot;

  /// No description provided for @msgScreenshotExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Screenshot export failed: {detail}'**
  String msgScreenshotExportFailed(String detail);

  /// No description provided for @msgGroupNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Group names must contain 1–60 characters and be unique'**
  String get msgGroupNameInvalid;

  /// No description provided for @msgOutputRequired.
  ///
  /// In en, this message translates to:
  /// **'Keep at least one color format enabled'**
  String get msgOutputRequired;

  /// No description provided for @msgDesktopDisconnected.
  ///
  /// In en, this message translates to:
  /// **'The system tools disconnected. Reopen fruler.'**
  String get msgDesktopDisconnected;

  /// No description provided for @msgPlatformUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This version supports macOS 14 and later. Other platforms are not available yet.'**
  String get msgPlatformUnsupported;

  /// No description provided for @msgPermissionGranted.
  ///
  /// In en, this message translates to:
  /// **'Screen access granted. You can start using the tools.'**
  String get msgPermissionGranted;

  /// No description provided for @msgPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Allow fruler to record the screen in System Settings, then try again.'**
  String get msgPermissionDenied;

  /// No description provided for @msgScreenshotFailed.
  ///
  /// In en, this message translates to:
  /// **'Screenshot failed: {detail}'**
  String msgScreenshotFailed(String detail);

  /// No description provided for @msgMacOSRequired.
  ///
  /// In en, this message translates to:
  /// **'This version requires macOS 14 or later.'**
  String get msgMacOSRequired;

  /// No description provided for @msgPickingFinished.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Color picking finished. # sample collected} other{Color picking finished. # samples collected}}'**
  String msgPickingFinished(int count);

  /// No description provided for @msgCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get msgCancelled;

  /// No description provided for @msgPickerActions.
  ///
  /// In en, this message translates to:
  /// **'Left: {primary} · Middle: {middle} · Right: {secondary}'**
  String msgPickerActions(String primary, String middle, String secondary);

  /// No description provided for @msgConfirmActions.
  ///
  /// In en, this message translates to:
  /// **'Left click / Enter to confirm · Right click to cancel'**
  String get msgConfirmActions;

  /// No description provided for @msgPickForeground.
  ///
  /// In en, this message translates to:
  /// **'Pick foreground color'**
  String get msgPickForeground;

  /// No description provided for @msgPickBackground.
  ///
  /// In en, this message translates to:
  /// **'Pick background color'**
  String get msgPickBackground;

  /// No description provided for @msgDragScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Drag to select a capture region'**
  String get msgDragScreenshot;

  /// No description provided for @msgDragMeasurement.
  ///
  /// In en, this message translates to:
  /// **'Click and drag to measure a rectangular region'**
  String get msgDragMeasurement;

  /// No description provided for @msgPickingCancelled.
  ///
  /// In en, this message translates to:
  /// **'Color picking cancelled'**
  String get msgPickingCancelled;

  /// No description provided for @msgPickerFinishFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to close the color picker: {detail}'**
  String msgPickerFinishFailed(String detail);

  /// No description provided for @msgPickingContinues.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{# color picked · Esc to finish} other{# colors picked · Esc to finish}}'**
  String msgPickingContinues(int count);

  /// No description provided for @msgColorClipboardFailed.
  ///
  /// In en, this message translates to:
  /// **'Color saved, but copying failed: {detail}'**
  String msgColorClipboardFailed(String detail);

  /// No description provided for @msgMeasurementsRetained.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{# measurement kept and its dimensions copied} other{# measurements kept and dimensions copied}}'**
  String msgMeasurementsRetained(int count);

  /// No description provided for @msgMeasurementClipboardFailed.
  ///
  /// In en, this message translates to:
  /// **'Annotation kept, but copying failed: {detail}'**
  String msgMeasurementClipboardFailed(String detail);

  /// No description provided for @msgCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied {text}'**
  String msgCopied(String text);

  /// No description provided for @msgSizeClipboardFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to copy dimensions: {detail}'**
  String msgSizeClipboardFailed(String detail);

  /// No description provided for @msgAnnotationImageExported.
  ///
  /// In en, this message translates to:
  /// **'Annotated image exported'**
  String get msgAnnotationImageExported;

  /// No description provided for @msgAnnotationImageCopied.
  ///
  /// In en, this message translates to:
  /// **'Annotated image copied'**
  String get msgAnnotationImageCopied;

  /// No description provided for @msgAnnotationImageExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Annotated image export failed: {detail}'**
  String msgAnnotationImageExportFailed(String detail);

  /// No description provided for @msgResultClipboardFailed.
  ///
  /// In en, this message translates to:
  /// **'Result saved, but copying failed: {detail}'**
  String msgResultClipboardFailed(String detail);

  /// No description provided for @msgRulerFinishFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to close the ruler. Press Esc: {detail}'**
  String msgRulerFinishFailed(String detail);

  /// No description provided for @msgShortcutInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use a letter or digit with at least one main modifier. Each tool must have a different shortcut.'**
  String get msgShortcutInvalid;

  /// No description provided for @msgShortcutRegistrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to register the shortcut. Previous settings were kept.'**
  String get msgShortcutRegistrationFailed;

  /// No description provided for @msgShortcutsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts updated'**
  String get msgShortcutsUpdated;

  /// No description provided for @msgColorsExported.
  ///
  /// In en, this message translates to:
  /// **'Colors exported'**
  String get msgColorsExported;

  /// No description provided for @msgColorsExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Color export failed: {detail}'**
  String msgColorsExportFailed(String detail);

  /// No description provided for @msgPaletteReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to read the palette file: {detail}'**
  String msgPaletteReadFailed(String detail);

  /// No description provided for @msgColorsMerged.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{# color merged} other{# colors merged}}'**
  String msgColorsMerged(int count);

  /// No description provided for @msgPaletteCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Copied {format} code for # color} other{Copied {format} code for # colors}}'**
  String msgPaletteCodeCopied(int count, String format);

  /// No description provided for @msgMeasurementsExported.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{# measurement exported} other{# measurements exported}}'**
  String msgMeasurementsExported(int count);

  /// No description provided for @msgMeasurementsExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Measurement export failed: {detail}'**
  String msgMeasurementsExportFailed(String detail);

  /// No description provided for @msgHistorySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save history: {detail}'**
  String msgHistorySaveFailed(String detail);

  /// No description provided for @msgShortcutsRestored.
  ///
  /// In en, this message translates to:
  /// **'Invalid shortcut settings. Defaults were restored.'**
  String get msgShortcutsRestored;

  /// No description provided for @msgHistoryRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to read history. Default settings are in use.'**
  String get msgHistoryRestoreFailed;

  /// No description provided for @msgScreenPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Screen recording permission is required. Allow access in Preferences, then reopen the tool.'**
  String get msgScreenPermissionRequired;

  /// No description provided for @msgCaptureCancelled.
  ///
  /// In en, this message translates to:
  /// **'The screen state changed. Start again.'**
  String get msgCaptureCancelled;

  /// No description provided for @msgShortcutConflict.
  ///
  /// In en, this message translates to:
  /// **'The shortcut is already in use. Tried to restore the previous settings.'**
  String get msgShortcutConflict;

  /// No description provided for @msgShortcutUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This shortcut is unavailable. Choose another combination.'**
  String get msgShortcutUnavailable;

  /// No description provided for @msgCaptureBusy.
  ///
  /// In en, this message translates to:
  /// **'A tool is already active. Press Esc to exit it first.'**
  String get msgCaptureBusy;

  /// No description provided for @msgSystemOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'The system operation failed. Try again.'**
  String get msgSystemOperationFailed;

  /// No description provided for @msgUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'This platform is not supported yet'**
  String get msgUnsupportedPlatform;

  /// No description provided for @msgOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'The operation failed. Try again.'**
  String get msgOperationFailed;

  /// No description provided for @msgLocaleChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to change language. Previous settings were kept.'**
  String get msgLocaleChangeFailed;

  /// No description provided for @msgPickAndClose.
  ///
  /// In en, this message translates to:
  /// **'Pick and finish'**
  String get msgPickAndClose;

  /// No description provided for @msgPickAndEdit.
  ///
  /// In en, this message translates to:
  /// **'Pick and open editor'**
  String get msgPickAndEdit;

  /// No description provided for @msgPickAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Pick and continue'**
  String get msgPickAndContinue;

  /// No description provided for @msgCancelPicking.
  ///
  /// In en, this message translates to:
  /// **'Cancel color picking'**
  String get msgCancelPicking;

  /// No description provided for @validationAnnotationCount.
  ///
  /// In en, this message translates to:
  /// **'Invalid annotation count'**
  String get validationAnnotationCount;

  /// No description provided for @validationAnnotationInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid annotation'**
  String get validationAnnotationInvalid;

  /// No description provided for @validationAnnotationStyle.
  ///
  /// In en, this message translates to:
  /// **'Invalid annotation type or style'**
  String get validationAnnotationStyle;

  /// No description provided for @validationAnnotationPoints.
  ///
  /// In en, this message translates to:
  /// **'Too many annotation points'**
  String get validationAnnotationPoints;

  /// No description provided for @validationAnnotationCoordinates.
  ///
  /// In en, this message translates to:
  /// **'Invalid annotation coordinates'**
  String get validationAnnotationCoordinates;

  /// No description provided for @validationAnnotationBounds.
  ///
  /// In en, this message translates to:
  /// **'Annotations are outside the image bounds'**
  String get validationAnnotationBounds;

  /// No description provided for @validationAnnotationEndpoints.
  ///
  /// In en, this message translates to:
  /// **'Invalid annotation endpoint count'**
  String get validationAnnotationEndpoints;

  /// No description provided for @validationAnnotationLimit.
  ///
  /// In en, this message translates to:
  /// **'Annotation limit reached. Delete some annotations.'**
  String get validationAnnotationLimit;

  /// No description provided for @validationHexColor.
  ///
  /// In en, this message translates to:
  /// **'Enter a 3-digit or 6-digit HEX color'**
  String get validationHexColor;

  /// No description provided for @validationHslValue.
  ///
  /// In en, this message translates to:
  /// **'Invalid HSL value'**
  String get validationHslValue;

  /// No description provided for @validationRgbValue.
  ///
  /// In en, this message translates to:
  /// **'Invalid RGB value'**
  String get validationRgbValue;

  /// No description provided for @validationPaletteEntry.
  ///
  /// In en, this message translates to:
  /// **'Invalid palette entry'**
  String get validationPaletteEntry;

  /// No description provided for @validationPaletteVersion.
  ///
  /// In en, this message translates to:
  /// **'Choose a version 1 JSON file exported by fruler'**
  String get validationPaletteVersion;

  /// No description provided for @validationPaletteLimit.
  ///
  /// In en, this message translates to:
  /// **'Import up to 4096 colors at a time'**
  String get validationPaletteLimit;

  /// No description provided for @validationPaletteMetadata.
  ///
  /// In en, this message translates to:
  /// **'Invalid color entry name or favorite state'**
  String get validationPaletteMetadata;

  /// No description provided for @validationPaletteChannels.
  ///
  /// In en, this message translates to:
  /// **'HEX and RGB do not match. No colors were imported.'**
  String get validationPaletteChannels;

  /// No description provided for @validationPaletteDuplicates.
  ///
  /// In en, this message translates to:
  /// **'The file contains duplicate colors. Remove duplicates first.'**
  String get validationPaletteDuplicates;

  /// No description provided for @validationOutputInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid color format data'**
  String get validationOutputInvalid;

  /// No description provided for @validationOutputName.
  ///
  /// In en, this message translates to:
  /// **'Format names must contain 1–40 characters'**
  String get validationOutputName;

  /// No description provided for @validationOutputTemplate.
  ///
  /// In en, this message translates to:
  /// **'Templates must contain 1–1024 characters and no control characters'**
  String get validationOutputTemplate;

  /// No description provided for @validationOutputSubstitution.
  ///
  /// In en, this message translates to:
  /// **'A template needs at least one color placeholder'**
  String get validationOutputSubstitution;

  /// No description provided for @validationPickerBehavior.
  ///
  /// In en, this message translates to:
  /// **'Invalid color picker action data'**
  String get validationPickerBehavior;

  /// No description provided for @validationOutputLimit.
  ///
  /// In en, this message translates to:
  /// **'Keep up to 24 color formats'**
  String get validationOutputLimit;

  /// No description provided for @validationOutputNameDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Format names must be unique'**
  String get validationOutputNameDuplicate;

  /// No description provided for @validationImageSize.
  ///
  /// In en, this message translates to:
  /// **'Images can have up to 16 million pixels and no side longer than 16384 pixels'**
  String get validationImageSize;

  /// No description provided for @validationImageFormat.
  ///
  /// In en, this message translates to:
  /// **'Only PNG, JPEG and WebP images are supported'**
  String get validationImageFormat;

  /// No description provided for @validationImageDecode.
  ///
  /// In en, this message translates to:
  /// **'Unable to decode the image'**
  String get validationImageDecode;

  /// No description provided for @validationImageAnnotationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no image annotations to export'**
  String get validationImageAnnotationsEmpty;

  /// No description provided for @validationImageExport.
  ///
  /// In en, this message translates to:
  /// **'Image export failed'**
  String get validationImageExport;

  /// No description provided for @validationShortcut.
  ///
  /// In en, this message translates to:
  /// **'Invalid shortcut'**
  String get validationShortcut;

  /// No description provided for @validationShortcutBindings.
  ///
  /// In en, this message translates to:
  /// **'Invalid shortcut settings'**
  String get validationShortcutBindings;

  /// No description provided for @validationShortcutDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Each tool must have a different shortcut'**
  String get validationShortcutDuplicates;

  /// No description provided for @validationOutputPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Unknown placeholder: %{token}'**
  String validationOutputPlaceholder(String token);

  /// No description provided for @validationImageFileLimit.
  ///
  /// In en, this message translates to:
  /// **'Image files cannot exceed {limit} MB'**
  String validationImageFileLimit(int limit);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
