import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../core/core.dart';
import '../platform/annotation_renderer.dart';
import '../platform/pixel_frame_image.dart';

part 'annotation_widgets.dart';
part 'history_widgets.dart';

const _background = Color(0xFF111315),
    _panel = Color(0xFF1B1E21),
    _line = Color(0xFF303438),
    _muted = Color(0xFF949B9F),
    _accent = Color(0xFFD7FA6B);
const _modeLabels = {
  RulerMode.rectangle: '矩形',
  RulerMode.horizontal: '水平',
  RulerMode.vertical: '垂直',
  RulerMode.cross: '交叉',
};

class FrulerApp extends StatelessWidget {
  const FrulerApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'fruler',
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
                  const Text(
                    'fruler',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => c.selectSection(
                      c.section == AppSection.settings
                          ? AppSection.picker
                          : AppSection.settings,
                    ),
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(
                      c.section == AppSection.settings ? '返回历史' : '偏好设置',
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
                    label: Text('取色 · ${c.shortcuts.picker.label}'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('start-ruler'),
                    onPressed: c.busy ? null : c.startRuler,
                    icon: const Icon(Icons.straighten),
                    label: Text('测量 · ${c.shortcuts.ruler.label}'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('start-screenshot'),
                    onPressed: c.busy ? null : c.startScreenshot,
                    icon: const Icon(Icons.screenshot_monitor),
                    label: Text('截图 · ${c.shortcuts.screenshot.label}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '在屏幕上完成操作，复制或保存后回到原应用。',
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
                              AppSection.picker: '取色历史',
                              AppSection.ruler: '测量历史',
                              AppSection.image: '截图历史',
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
                            const _Empty(
                              icon: Icons.colorize,
                              title: '还没有取色记录',
                              description: '在屏幕上取色后自动复制，最近颜色显示在这里。',
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
                            const _Empty(
                              icon: Icons.image_outlined,
                              title: '还没有截图记录',
                              description: '完成的截图暂存在本次运行中，点击即可重新复制。',
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
      const _PageHeading(
        index: '03 / PREFERENCES',
        title: '按你的习惯工作',
        description: '轻量常驻，随时就绪。',
      ),
      _SettingsCard(
        title: '屏幕访问',
        icon: Icons.desktop_access_disabled_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.permissionGranted ? '已获得屏幕录制权限' : '需要允许 fruler 录制屏幕',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              '启动工具时冻结屏幕快照，退出后释放，不上传。仅在你复制或导出标注时，将局部图片写入剪贴板或所选文件。',
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
                    controller.permissionGranted ? '重新检查权限' : '请求屏幕授权',
                  ),
                ),
                TextButton(
                  onPressed: controller.openPrivacySettings,
                  child: const Text('打开系统设置 ↗', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SettingsCard(
        title: '取色',
        icon: Icons.colorize,
        child: Column(
          children: [
            Row(
              children: [
                const Text('复制格式'),
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
              title: const Text('连续取色'),
              subtitle: const Text('每次取色立即复制，Esc 结束'),
              value: controller.continuousPicker,
              onChanged: controller.setContinuousPicker,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SettingsCard(
        title: '边界识别',
        icon: Icons.center_focus_strong_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('颜色容差', style: TextStyle(fontSize: 13)),
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
            const Text(
              '每个 RGB 通道与光标像素比较。容差越小，边界识别越严格。',
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
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0 · 精确匹配', style: TextStyle(color: _muted, fontSize: 10)),
                Text(
                  '255 · 宽松匹配',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SettingsCard(
        title: '快捷操作',
        icon: Icons.keyboard_rounded,
        child: Column(
          children: [
            _editableShortcut(context, true),
            const SizedBox(height: 15),
            _editableShortcut(context, false),
            const SizedBox(height: 10),
            _editableShortcut(context, false, screenshot: true),
            const SizedBox(height: 15),
            _shortcut('取消当前工具', 'Esc / 鼠标右键'),
            if (!controller.shortcutsAvailable)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  '全局快捷键未全部注册，可能已被其他应用占用。仍可使用窗口或菜单栏入口。',
                  style: TextStyle(color: Color(0xFFE7B56A), fontSize: 11),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const _Hint(
        icon: Icons.layers_outlined,
        text: 'fruler 0.10.0 · Flutter 界面与 Dart 测量核心 · macOS 14+',
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
            ? '截图并标注'
            : picker
            ? '取色器'
            : '矩形测量',
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
                ? '截图并标注'
                : picker
                ? '取色器'
                : '矩形测量',
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
        const Expanded(
          child: Text(
            '首次使用需要屏幕录制权限，才能读取屏幕上的像素。',
            style: TextStyle(color: Color(0xFFD8D1B3), fontSize: 11),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () => controller.selectSection(AppSection.settings),
          child: const Text(
            '前往授权 →',
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
          tooltip: '关闭提示',
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
          child: const Padding(
            padding: EdgeInsets.all(5),
            child: Text('清空记录', style: TextStyle(color: _muted, fontSize: 10)),
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
      title: Text('设置${widget.tool}快捷键'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('按下修饰键与一个字母或数字的组合。需要包含 ⌘、⌃ 或 ⌥；支持附加 ⇧。'),
            const SizedBox(height: 20),
            Text(
              candidate?.label ?? '等待按键…',
              style: const TextStyle(fontSize: 24, color: _accent),
            ),
            const SizedBox(height: 16),
            const Text(
              '按 Enter 保存，Esc 取消。系统保留或已占用的组合无法保存。',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: candidate == null
              ? null
              : () => Navigator.pop(context, candidate),
          child: const Text('保存'),
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
