part of 'fruler_app.dart';

class _GeneralSettingsPage extends StatelessWidget {
  const _GeneralSettingsPage({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
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
        title: context.l10n.uiAboutTitle,
        icon: Icons.info_outline,
        child: Text(
          context.l10n.uiAbout,
          style: const TextStyle(color: _muted, height: 1.6),
        ),
      ),
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
            : context.l10n.uiRuler,
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
                : context.l10n.uiRuler,
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

class _PickerOptionsPage extends StatelessWidget {
  const _PickerOptionsPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SettingsCard(
        title: context.l10n.uiPickerOptions,
        icon: Icons.colorize,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(context.l10n.uiCopyFormat),
                const SizedBox(width: 24),
                Expanded(
                  child: DropdownButton<String>(
                    key: const ValueKey('picker-format'),
                    isExpanded: true,
                    value: controller.selectedOutputId,
                    items: controller.enabledColorOutputs
                        .map(
                          (format) => DropdownMenuItem(
                            value: format.id,
                            child: Text(
                              format.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) controller.selectColorOutput(value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('picker-continuous'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.uiContinuousPicker),
              subtitle: Text(context.l10n.uiContinuousPickerDescription),
              value: controller.continuousPicker,
              onChanged: controller.setContinuousPicker,
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(child: Text(context.l10n.uiMagnification)),
                DropdownButton<int>(
                  key: const ValueKey('picker-zoom'),
                  value: controller.zoom,
                  items: [
                    for (final zoom in CaptureControls.zoomLevels)
                      DropdownMenuItem(value: zoom, child: Text('$zoom×')),
                  ],
                  onChanged: (value) {
                    if (value != null) controller.setZoom(value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.uiMagnificationDescription,
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.6),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _ColorHistory(controller: controller),
    ],
  );
}

class _RulerOptionsPage extends StatelessWidget {
  const _RulerOptionsPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SettingsCard(
        title: context.l10n.uiRulerOptions,
        icon: Icons.straighten,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(context.l10n.uiDefaultMode)),
                DropdownButton<RulerMode>(
                  key: const ValueKey('ruler-mode'),
                  value: controller.mode,
                  items: [
                    for (final mode in RulerMode.values)
                      DropdownMenuItem(
                        value: mode,
                        child: Text(_modeLabel(context, mode)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) controller.selectMode(value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.uiDefaultModeDescription,
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.6),
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(child: Text(context.l10n.uiColorTolerance)),
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
            const SizedBox(height: 8),
            Text(
              context.l10n.uiToleranceDescription,
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.6),
            ),
            Slider(
              key: const ValueKey('ruler-tolerance'),
              value: controller.tolerance.toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              label: '${controller.tolerance}',
              onChanged: (value) => controller.setTolerance(value.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10n.uiToleranceExact,
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
                Text(
                  context.l10n.uiToleranceLoose,
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _MeasurementHistory(controller: controller),
    ],
  );
}

class _ScreenshotOptionsPage extends StatelessWidget {
  const _ScreenshotOptionsPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SettingsCard(
        title: context.l10n.uiScreenshotWorkflow,
        icon: Icons.crop,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Hint(icon: Icons.crop_free, text: context.l10n.uiScreenshotSelect),
            const SizedBox(height: 12),
            _Hint(
              icon: Icons.draw_outlined,
              text: context.l10n.uiScreenshotAnnotate,
            ),
            const SizedBox(height: 12),
            _Hint(
              icon: Icons.copy_outlined,
              text: context.l10n.uiScreenshotFinish,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _ScreenshotHistory(controller: controller),
    ],
  );
}
