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

import 'font_family_picker.dart';

part 'annotation_widgets.dart';
part 'history_widgets.dart';

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
          return _HistoryHome(controller: controller);
        },
      ),
    ),
  );
}

class _HistoryHome extends StatelessWidget {
  const _HistoryHome({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    context.l10n.appTitle,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    key: const ValueKey('open-preferences'),
                    onPressed: () => c.selectSection(
                      c.section == AppSection.settings
                          ? AppSection.picker
                          : AppSection.settings,
                    ),
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(
                      c.section == AppSection.settings
                          ? context.l10n.uiBackToHistory
                          : context.l10n.uiPreferences,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('start-picker'),
                    onPressed: c.busy ? null : c.pickColor,
                    icon: const Icon(Icons.colorize),
                    label: Text(
                      context.l10n.uiStartPicker(c.shortcuts.picker.label),
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('start-ruler'),
                    onPressed: c.busy ? null : c.startRuler,
                    icon: const Icon(Icons.straighten),
                    label: Text(
                      context.l10n.uiStartRuler(c.shortcuts.ruler.label),
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('start-screenshot'),
                    onPressed: c.busy ? null : c.startScreenshot,
                    icon: const Icon(Icons.screenshot_monitor),
                    label: Text(
                      context.l10n.uiStartScreenshot(
                        c.shortcuts.screenshot.label,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.uiScreenWorkflow,
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (c.error != null || c.notice != null)
                        _Message(controller: c),
                      if (!c.permissionGranted && !c.initializing)
                        _PermissionBanner(controller: c),
                      if (c.section == AppSection.settings)
                        _SettingsPage(controller: c)
                      else ...[
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final e in {
                              AppSection.picker: context.l10n.uiColorHistory,
                              AppSection.ruler:
                                  context.l10n.uiMeasurementHistory,
                              AppSection.image:
                                  context.l10n.uiScreenshotHistory,
                            }.entries)
                              ChoiceChip(
                                label: Text(e.value),
                                selected: c.section == e.key,
                                onSelected: (_) => c.selectSection(e.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (c.section == AppSection.picker) ...[
                          if (c.colors.isEmpty)
                            _Empty(
                              icon: Icons.colorize,
                              title: context.l10n.uiNoColors,
                              description: context.l10n.uiNoColorsDescription,
                            ),
                          for (final color in c.colors)
                            ListTile(
                              leading: Container(
                                width: 32,
                                height: 32,
                                color: Color.fromARGB(
                                  255,
                                  color.r,
                                  color.g,
                                  color.b,
                                ),
                              ),
                              title: Text(c.formatColor(color)),
                              subtitle: Text(color.hex),
                              trailing: const Icon(Icons.copy, size: 18),
                              onTap: () => c.copyColor(color),
                            ),
                        ] else if (c.section == AppSection.ruler)
                          _MeasurementHistory(controller: c)
                        else ...[
                          if (c.screenshots.isEmpty)
                            _Empty(
                              icon: Icons.image_outlined,
                              title: context.l10n.uiNoScreenshots,
                              description:
                                  context.l10n.uiNoScreenshotsDescription,
                            ),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final png in c.screenshots)
                                InkWell(
                                  onTap: () => c.copyScreenshot(png),
                                  child: Image.memory(
                                    png,
                                    width: 220,
                                    height: 150,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _PageHeading(
        index: context.l10n.uiPreferencesIndex,
        title: context.l10n.uiPreferencesHeading,
        description: context.l10n.uiPreferencesDescription,
      ),
      _SettingsCard(
        title: context.l10n.uiLanguage,
        icon: Icons.language,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.uiLanguageDescription),
            const SizedBox(height: 12),
            DropdownButton<AppLanguage>(
              key: const ValueKey('app-language'),
              value: controller.language,
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: AppLanguage.system,
                  child: Text(context.l10n.uiLanguageSystem),
                ),
                DropdownMenuItem(
                  value: AppLanguage.zh,
                  child: Text(context.l10n.uiLanguageChinese),
                ),
                DropdownMenuItem(
                  value: AppLanguage.en,
                  child: Text(context.l10n.uiLanguageEnglish),
                ),
              ],
              onChanged: controller.busy
                  ? null
                  : (value) {
                      if (value != null) controller.setLanguage(value);
                    },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SettingsCard(
        title: context.l10n.uiScreenAccess,
        icon: Icons.desktop_access_disabled_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.permissionGranted
                  ? context.l10n.uiScreenPermissionGranted
                  : context.l10n.uiScreenPermissionNeeded,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.uiScreenPrivacy,
              style: TextStyle(fontSize: 11, color: _muted, height: 1.7),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton(
                  onPressed: controller.requestPermission,
                  child: Text(
                    controller.permissionGranted
                        ? context.l10n.uiRecheckPermission
                        : context.l10n.uiRequestPermission,
                  ),
                ),
                TextButton(
                  onPressed: controller.openPrivacySettings,
                  child: Text(
                    context.l10n.uiOpenSystemSettings,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SettingsCard(
        title: context.l10n.uiColorPicking,
        icon: Icons.colorize,
        child: Column(
          children: [
            Row(
              children: [
                Text(context.l10n.uiCopyFormat),
                const Spacer(),
                DropdownButton<String>(
                  value: controller.selectedOutputId,
                  items: controller.enabledColorOutputs
                      .map(
                        (f) =>
                            DropdownMenuItem(value: f.id, child: Text(f.name)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) controller.selectColorOutput(value);
                  },
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.uiContinuousPicker),
              subtitle: Text(context.l10n.uiContinuousPickerDescription),
              value: controller.continuousPicker,
              onChanged: controller.setContinuousPicker,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SettingsCard(
        title: context.l10n.uiEdgeDetection,
        icon: Icons.center_focus_strong_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.uiColorTolerance,
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  '${controller.tolerance}',
                  style: const TextStyle(
                    color: _accent,
                    fontFamily: 'Menlo',
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.uiToleranceDescription,
              style: TextStyle(color: _muted, fontSize: 11),
            ),
            Slider(
              value: controller.tolerance.toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              label: '${controller.tolerance}',
              onChanged: (v) => controller.setTolerance(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10n.uiToleranceExact,
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
                Text(
                  context.l10n.uiToleranceLoose,
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SettingsCard(
        title: context.l10n.uiKeyboardShortcuts,
        icon: Icons.keyboard_rounded,
        child: Column(
          children: [
            _editableShortcut(context, true),
            const SizedBox(height: 15),
            _editableShortcut(context, false),
            const SizedBox(height: 10),
            _editableShortcut(context, false, screenshot: true),
            const SizedBox(height: 15),
            _shortcut(context.l10n.uiCancelTool, context.l10n.uiCancelToolKeys),
            if (!controller.shortcutsAvailable)
              Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  context.l10n.uiShortcutsUnavailable,
                  style: TextStyle(color: Color(0xFFE7B56A), fontSize: 11),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _Hint(icon: Icons.layers_outlined, text: context.l10n.uiAbout),
    ],
  );
  Widget _editableShortcut(
    BuildContext context,
    bool picker, {
    bool screenshot = false,
  }) => Row(
    children: [
      Text(
        screenshot
            ? context.l10n.uiScreenshotAndAnnotate
            : picker
            ? context.l10n.uiColorPicker
            : context.l10n.uiRectangleMeasurement,
        style: const TextStyle(fontSize: 12),
      ),
      const Spacer(),
      OutlinedButton(
        onPressed:
            controller.busy ||
                controller.initializing ||
                controller.savingShortcuts ||
                controller.recordingShortcut
            ? null
            : () => _recordShortcut(context, picker, screenshot: screenshot),
        child: Text(
          (screenshot
                  ? controller.shortcuts.screenshot
                  : picker
                  ? controller.shortcuts.picker
                  : controller.shortcuts.ruler)
              .label,
        ),
      ),
    ],
  );

  Future<void> _recordShortcut(
    BuildContext context,
    bool picker, {
    bool screenshot = false,
  }) async {
    if (!await controller.beginShortcutRecording()) return;
    ShortcutChord? chord;
    try {
      if (context.mounted) {
        chord = await showDialog<ShortcutChord>(
          context: context,
          builder: (_) => _ShortcutDialog(
            tool: screenshot
                ? context.l10n.uiScreenshotAndAnnotate
                : picker
                ? context.l10n.uiColorPicker
                : context.l10n.uiRectangleMeasurement,
            controller: controller,
          ),
        );
      }
    } finally {
      await controller.endShortcutRecording();
    }
    if (chord != null) {
      await controller.setShortcut(picker, chord, screenshot: screenshot);
    }
  }

  Widget _shortcut(String label, String keys) => Row(
    children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      const Spacer(),
      Text(
        keys,
        style: const TextStyle(
          color: _muted,
          fontSize: 12,
          fontFamily: 'Menlo',
        ),
      ),
    ],
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

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.index,
    required this.title,
    required this.description,
  });
  final String index, title, description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 27),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                index,
                style: const TextStyle(
                  color: _accent,
                  fontSize: 10,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
