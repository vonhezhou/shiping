import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../app/app_controller.dart';
import '../core/core.dart';
import '../l10n/app_language.dart';
import '../l10n/app_localizations.dart';
import '../l10n/localizations_context.dart';
import '../platform/annotation_renderer.dart';
import '../platform/pixel_frame_image.dart';
import '../platform/desktop_service.dart' show DesktopFeature;

import 'font_family_picker.dart';

part 'annotation_widgets.dart';
part 'text_recognition_overlay.dart';
part 'qr_code_results_dialog.dart';
part 'color_format_widgets.dart';
part 'history_widgets.dart';
part 'settings_widgets.dart';
part 'recording_widgets.dart';

const _background = Color(0xFF111315),
    _panel = Color(0xFF1B1E21),
    _line = Color(0xFF303438),
    _muted = Color(0xFF949B9F),
    _accent = Color(0xFFD7FA6B);
String _modeLabel(BuildContext context, RulerMode mode) => switch (mode) {
  RulerMode.rectangle => context.l10n.uiModeRectangle,
  RulerMode.horizontal => context.l10n.uiModeHorizontal,
  RulerMode.vertical => context.l10n.uiModeVertical,
  RulerMode.cross => context.l10n.uiModeCross,
};

class FrulerApp extends StatefulWidget {
  const FrulerApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<FrulerApp> createState() => _FrulerAppState();
}

class _FrulerAppState extends State<FrulerApp> with WidgetsBindingObserver {
  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    controller.updateSystemLocale(locales?.firstOrNull ?? const Locale('en'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale>(
    valueListenable: controller.localeChanges,
    builder: (context, locale, _) => MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: _background,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          surface: _panel,
          onPrimary: Color(0xFF182008),
          onSurface: Color(0xFFF1F3EF),
          outline: _line,
        ),
        fontFamily: 'PingFang SC',
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.screenshotEditing) {
            return Material(
              color: Colors.transparent,
              child: _AnnotationEditor(
                key: ObjectKey(controller.imageDocument),
                controller: controller,
              ),
            );
          }
          return _OptionsHome(controller: controller);
        },
      ),
    ),
  );
}

String _sectionLabel(BuildContext context, AppSection section) =>
    switch (section) {
      AppSection.settings => context.l10n.uiGeneral,
      AppSection.picker => context.l10n.uiColorPicker,
      AppSection.ruler => context.l10n.uiRuler,
      AppSection.image => context.l10n.uiScreenshot,
      AppSection.recording => context.l10n.uiRecording,
    };

IconData _sectionIcon(AppSection section) => switch (section) {
  AppSection.settings => Icons.settings_outlined,
  AppSection.picker => Icons.colorize,
  AppSection.ruler => Icons.straighten,
  AppSection.image => Icons.screenshot_monitor,
  AppSection.recording => Icons.videocam_outlined,
};

class _OptionsHome extends StatelessWidget {
  const _OptionsHome({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final canStart =
        !c.busy &&
        !c.pinningImage &&
        !c.initializing &&
        !c.recordingShortcut &&
        !c.savingShortcuts &&
        !c.screenRecording &&
        !c.recordingTransition;
    final action = switch (c.section) {
      AppSection.settings => null,
      AppSection.picker => FilledButton.icon(
        key: const ValueKey('start-picker'),
        onPressed: canStart ? c.pickColor : null,
        icon: const Icon(Icons.colorize, size: 18),
        label: Text(context.l10n.uiStartPicker(c.shortcuts.picker.label)),
      ),
      AppSection.ruler => FilledButton.icon(
        key: const ValueKey('start-ruler'),
        onPressed: canStart ? c.startRuler : null,
        icon: const Icon(Icons.straighten, size: 18),
        label: Text(context.l10n.uiStartRuler(c.shortcuts.ruler.label)),
      ),
      AppSection.image => FilledButton.icon(
        key: const ValueKey('start-screenshot'),
        onPressed: canStart ? c.startScreenshot : null,
        icon: const Icon(Icons.screenshot_monitor, size: 18),
        label: Text(
          context.l10n.uiStartScreenshot(c.shortcuts.screenshot.label),
        ),
      ),
      AppSection.recording => FilledButton.icon(
        key: ValueKey(c.screenRecording ? 'stop-recording' : 'start-recording'),
        onPressed: c.recordingTransition
            ? null
            : c.screenRecording
            ? c.stopRecording
            : canStart
            ? c.startRecording
            : null,
        icon: Icon(
          c.screenRecording ? Icons.stop_rounded : Icons.videocam_outlined,
          size: 18,
        ),
        label: Text(
          c.screenRecording
              ? context.l10n.uiStopRecording
              : context.l10n.uiStartRecording,
        ),
      ),
    };
    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OptionsNavigation(controller: c),
            Expanded(
              // 每个工具保留自己的滚动位置，切页时不把另一个工具的偏移带过来。
              child: KeyedSubtree(
                key: PageStorageKey(c.section),
                child: SingleChildScrollView(
                  key: ValueKey('options-scroll-${c.section.name}'),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OptionsHeading(
                        title: _sectionLabel(context, c.section),
                        description: switch (c.section) {
                          AppSection.settings =>
                            context.l10n.uiGeneralDescription,
                          AppSection.picker => context.l10n.uiPickerDescription,
                          AppSection.ruler => context.l10n.uiRulerDescription,
                          AppSection.image =>
                            context.l10n.uiScreenshotDescription,
                          AppSection.recording =>
                            context.l10n.uiRecordingDescription,
                        },
                        icon: _sectionIcon(c.section),
                        action: action,
                      ),
                      if (c.error != null || c.notice != null) ...[
                        _Message(controller: c),
                        const SizedBox(height: 16),
                      ],
                      if (c.section != AppSection.settings &&
                          !c.permissionGranted &&
                          !c.initializing) ...[
                        _PermissionBanner(controller: c),
                        const SizedBox(height: 16),
                      ],
                      switch (c.section) {
                        AppSection.settings => _GeneralSettingsPage(
                          controller: c,
                        ),
                        AppSection.picker => _PickerOptionsPage(controller: c),
                        AppSection.ruler => _RulerOptionsPage(controller: c),
                        AppSection.image => _ScreenshotOptionsPage(
                          controller: c,
                        ),
                        AppSection.recording => _RecordingOptionsPage(
                          controller: c,
                        ),
                      },
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionsNavigation extends StatelessWidget {
  const _OptionsNavigation({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Material(
    color: _panel,
    child: Container(
      key: const ValueKey('options-navigation'),
      width: 200,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.appTitle,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.uiOptionsTitle,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          for (final section in [
            AppSection.settings,
            AppSection.picker,
            AppSection.ruler,
            AppSection.image,
            AppSection.recording,
          ].where(controller.supportsSection))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: ListTile(
                key: ValueKey('nav-${section.name}'),
                selected: controller.section == section,
                selectedTileColor: _accent.withValues(alpha: .12),
                selectedColor: _accent,
                iconColor: _muted,
                textColor: const Color(0xFFE0E4DE),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                minLeadingWidth: 20,
                horizontalTitleGap: 10,
                leading: Icon(_sectionIcon(section), size: 19),
                title: Text(
                  _sectionLabel(context, section),
                  style: const TextStyle(fontSize: 13),
                ),
                onTap: () => controller.selectSection(section),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: _Hint(
              icon: Icons.keyboard_outlined,
              text: context.l10n.uiOptionsSidebarHint,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(23),
    decoration: BoxDecoration(
      color: _panel,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF252A23),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: _accent),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: _muted)),
              const SizedBox(height: 15),
              Material(color: Colors.transparent, child: child),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(15, 12, 12, 12),
    decoration: BoxDecoration(
      color: const Color(0xFF28271D),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFF47422E)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          size: 18,
          color: Color(0xFFE7B56A),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            context.l10n.uiPermissionBanner,
            style: TextStyle(color: Color(0xFFD8D1B3), fontSize: 11),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () => controller.selectSection(AppSection.settings),
          child: Text(
            context.l10n.uiGoToPermission,
            style: TextStyle(color: Color(0xFFE7B56A), fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 7, 8),
    decoration: BoxDecoration(
      color: controller.error != null
          ? const Color(0xFF392320)
          : const Color(0xFF252D1E),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(
          controller.error != null
              ? Icons.error_outline_rounded
              : Icons.check_circle_outline,
          color: controller.error != null ? const Color(0xFFF3A994) : _accent,
          size: 17,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            controller.error ?? controller.notice!,
            style: const TextStyle(fontSize: 11),
          ),
        ),
        IconButton(
          onPressed: controller.dismissMessage,
          tooltip: context.l10n.uiDismissMessage,
          icon: const Icon(Icons.close_rounded, size: 16),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.onClear,
  });
  final String title, subtitle;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      const SizedBox(width: 12),
      Text(subtitle, style: const TextStyle(fontSize: 10, color: _muted)),
      const Spacer(),
      if (onClear != null)
        InkWell(
          onTap: onClear,
          child: Padding(
            padding: EdgeInsets.all(5),
            child: Text(
              context.l10n.uiClearHistory,
              style: TextStyle(color: _muted, fontSize: 10),
            ),
          ),
        ),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title, description;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _line),
    ),
    child: Column(
      children: [
        Icon(icon, size: 24, color: const Color(0xFF666F71)),
        const SizedBox(height: 11),
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Color(0xFFB9C1BF)),
        ),
        const SizedBox(height: 7),
        Text(
          description,
          style: const TextStyle(fontSize: 10, color: _muted),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 13, color: _muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 10, color: _muted, height: 1.6),
        ),
      ),
    ],
  );
}

class _ShortcutDialog extends StatefulWidget {
  const _ShortcutDialog({required this.tool, required this.controller});
  final String tool;
  final AppController controller;
  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  ShortcutChord? candidate;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_nativeChordChanged);
  }

  void _nativeChordChanged() {
    final chord = widget.controller.recordedShortcut;
    if (chord != null && chord != candidate) setState(() => candidate = chord);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_nativeChordChanged);
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && candidate != null) {
      Navigator.pop(context, candidate);
      return KeyEventResult.handled;
    }
    final usage = event.physicalKey.usbHidUsage;
    final String? key = usage >= 0x70004 && usage <= 0x7001d
        ? String.fromCharCode(65 + usage - 0x70004)
        : usage >= 0x7001e && usage <= 0x70027
        ? '${(usage - 0x7001e + 1) % 10}'
        : null;
    if (key != null) {
      final keyboard = HardwareKeyboard.instance;
      final chord = ShortcutChord(
        key: key,
        meta: keyboard.isMetaPressed,
        control: keyboard.isControlPressed,
        alt: keyboard.isAltPressed,
        shift: keyboard.isShiftPressed,
      );
      if (chord.isValid) setState(() => candidate = chord);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _onKey,
    child: AlertDialog(
      title: Text(context.l10n.uiShortcutTitle(widget.tool)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.uiShortcutInstructions),
            const SizedBox(height: 20),
            Text(
              candidate?.label ?? context.l10n.uiShortcutWaiting,
              style: const TextStyle(fontSize: 24, color: _accent),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.uiShortcutSaveHint,
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.uiCancel),
        ),
        FilledButton(
          onPressed: candidate == null
              ? null
              : () => Navigator.pop(context, candidate),
          child: Text(context.l10n.uiSave),
        ),
      ],
    ),
  );
}

class _OptionsHeading extends StatelessWidget {
  const _OptionsHeading({
    required this.title,
    required this.description,
    required this.icon,
    this.action,
  });
  final String title, description;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 27, color: _accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (action != null) ...[const SizedBox(width: 16), action!],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: const TextStyle(fontSize: 12, color: _muted, height: 1.6),
        ),
      ],
    ),
  );
}
