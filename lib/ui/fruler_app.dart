import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../core/core.dart';

part 'palette_widgets.dart';

const _background = Color(0xFF111315);
const _panel = Color(0xFF1B1E21);
const _line = Color(0xFF303438);
const _muted = Color(0xFF949B9F);
const _accent = Color(0xFFD7FA6B);

class FrulerApp extends StatelessWidget {
  const FrulerApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'fruler',
    debugShowCheckedModeBanner: false,
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
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 13, height: 1.5),
        bodySmall: TextStyle(fontSize: 12, color: _muted, height: 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE4E8DF),
          side: const BorderSide(color: _line),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    ),
    home: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        body: Row(
          children: [
            _Sidebar(controller: controller),
            const VerticalDivider(width: 1, color: _line),
            Expanded(
              child: Column(
                children: [
                  _TopBar(controller: controller),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(34, 29, 34, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (controller.error != null ||
                              controller.notice != null) ...[
                            _Message(controller: controller),
                            const SizedBox(height: 20),
                          ],
                          if (!controller.permissionGranted &&
                              !controller.initializing) ...[
                            _PermissionBanner(controller: controller),
                            const SizedBox(height: 24),
                          ],
                          switch (controller.section) {
                            AppSection.picker => _PickerPage(
                              controller: controller,
                            ),
                            AppSection.ruler => _RulerPage(
                              controller: controller,
                            ),
                            AppSection.settings => _SettingsPage(
                              controller: controller,
                            ),
                          },
                        ],
                      ),
                    ),
                  ),
                  _Footer(controller: controller),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Container(
    width: 192,
    color: const Color(0xFF151719),
    padding: const EdgeInsets.fromLTRB(18, 30, 18, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Row(
            children: [
              _BrandMark(size: 30),
              SizedBox(width: 11),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'fruler',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(9, 15, 0, 35),
          child: Text(
            'FLUTTER + RULER',
            style: TextStyle(fontSize: 9, letterSpacing: 2.1, color: _muted),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 0, 12),
          child: Text('工作台', style: TextStyle(fontSize: 11, color: _muted)),
        ),
        _nav(AppSection.picker, Icons.colorize_rounded, '取色器', '01'),
        const SizedBox(height: 6),
        _nav(AppSection.ruler, Icons.straighten_rounded, '屏幕尺子', '02'),
        const Spacer(),
        _nav(AppSection.settings, Icons.tune_rounded, '偏好设置', ''),
        const SizedBox(height: 20),
        const Divider(color: _line),
        const SizedBox(height: 13),
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: controller.permissionGranted
                      ? _accent
                      : const Color(0xFFE7B56A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                controller.initializing
                    ? '正在连接系统…'
                    : controller.permissionGranted
                    ? '屏幕访问已就绪'
                    : '等待屏幕授权',
                style: const TextStyle(fontSize: 10, color: _muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.only(left: 10),
          child: Text(
            'macOS  ·  v0.3.0',
            style: TextStyle(fontSize: 10, color: Color(0xFF646C70)),
          ),
        ),
      ],
    ),
  );

  Widget _nav(AppSection section, IconData icon, String label, String index) {
    final selected = controller.section == section;
    return Material(
      color: selected ? const Color(0xFF252C20) : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: () => controller.selectSection(section),
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 18, color: selected ? _accent : _muted),
              const SizedBox(width: 11),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? _accent : const Color(0xFFC3C9CC),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const Spacer(),
              Text(
                index,
                style: TextStyle(
                  fontSize: 9,
                  color: selected
                      ? _accent.withValues(alpha: .5)
                      : const Color(0xFF555D61),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Container(
    height: 63,
    padding: const EdgeInsets.symmetric(horizontal: 34),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        const Text('工作台', style: TextStyle(fontSize: 11, color: _muted)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('/', style: TextStyle(color: _line)),
        ),
        Text(switch (controller.section) {
          AppSection.picker => '取色器',
          AppSection.ruler => '屏幕尺子',
          AppSection.settings => '偏好设置',
        }, style: const TextStyle(fontSize: 11)),
        const Spacer(),
        const Icon(Icons.desktop_mac_outlined, size: 14, color: _muted),
        const SizedBox(width: 8),
        const Text('为屏幕上的细节而造', style: TextStyle(fontSize: 10, color: _muted)),
      ],
    ),
  );
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.index,
    required this.title,
    required this.description,
    this.action,
  });
  final String index, title, description;
  final Widget? action;
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
        if (action != null) ...[const SizedBox(width: 14), action!],
      ],
    ),
  );
}

class _PickerPage extends StatelessWidget {
  const _PickerPage({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final color = controller.selectedColor;
    final swatch = Color.fromARGB(255, color.r, color.g, color.b);
    final light = swatch.computeLuminance() > .4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          index: '01 / COLOR PICKER',
          title: '带走屏幕上的颜色',
          description: '瞄准一个像素，取色、复制，一气呵成。',
          action: FilledButton.icon(
            onPressed: controller.busy || controller.initializing
                ? null
                : controller.pickColor,
            icon: const Icon(Icons.colorize_rounded, size: 17),
            label: Text(controller.busy ? '工具使用中…' : '开始取色'),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => _editColor(context, controller, color),
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('编辑颜色'),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: controller.continuousPicker,
                  onChanged: controller.busy
                      ? null
                      : controller.setContinuousPicker,
                ),
                const Text('连续取色 · Esc 结束', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: _line),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 10,
                  child: Container(
                    color: swatch,
                    constraints: const BoxConstraints(minHeight: 242),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.colors.isEmpty ? '预览色' : '当前颜色',
                          style: TextStyle(
                            fontSize: 11,
                            color: light ? Colors.black54 : Colors.white70,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          color.hex,
                          style: TextStyle(
                            fontSize: 31,
                            letterSpacing: -1.2,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Menlo',
                            color: light
                                ? const Color(0xFF182008)
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'sRGB  /  ${color.r} · ${color.g} · ${color.b}',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Menlo',
                            color: light ? Colors.black54 : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 11,
                  child: Padding(
                    padding: const EdgeInsets.all(23),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '颜色数值',
                          style: TextStyle(color: _muted, fontSize: 10),
                        ),
                        const SizedBox(height: 14),
                        for (final f in ColorFormat.values)
                          _ColorRow(
                            format: f,
                            value: color.formatted(f),
                            onCopy: () {
                              controller.setFormat(f);
                              controller.copyColor();
                            },
                          ),
                        const SizedBox(height: 12),
                        const Divider(color: _line, height: 1),
                        const SizedBox(height: 13),
                        Wrap(
                          spacing: 6,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              '自动复制',
                              style: TextStyle(fontSize: 10, color: _muted),
                            ),
                            for (final f in ColorFormat.values)
                              _Chip(
                                label: f.label,
                                selected: controller.format == f,
                                onTap: () => controller.setFormat(f),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Hint(
          icon: Icons.keyboard_command_key_rounded,
          text:
              '${controller.shortcuts.picker.label} 唤起 · 滚轮缩放 · 方向键逐像素移动 · Enter 确认 · Esc 取消',
        ),
        const SizedBox(height: 29),
        _SectionTitle(
          title: '最近取色',
          subtitle: '${controller.colors.length} / 64',
          onClear: controller.colors.isEmpty ? null : controller.clearColors,
        ),
        const SizedBox(height: 14),
        if (controller.colors.isEmpty)
          const _Empty(
            icon: Icons.palette_outlined,
            title: '你的调色板，从这里开始',
            description: '从屏幕取到的颜色会保存在这里，点击色卡即可再次复制。',
          )
        else
          _ColorGrid(controller: controller, saved: false),
        const SizedBox(height: 12),
        _ExportColors(controller: controller, saved: false),
        const SizedBox(height: 28),
        _SectionTitle(
          title: '我的调色板',
          subtitle: '${controller.palette.length} 色 · 收藏与命名',
        ),
        const SizedBox(height: 14),
        if (controller.palette.isEmpty)
          const _Empty(
            icon: Icons.bookmark_border,
            title: '留下值得复用的颜色',
            description: '在色卡菜单中收藏或命名，颜色会保留在调色板中。',
          )
        else
          _ColorGrid(controller: controller, saved: true),
        const SizedBox(height: 12),
        _ExportColors(controller: controller, saved: true),
      ],
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.format,
    required this.value,
    required this.onCopy,
  });
  final ColorFormat format;
  final String value;
  final VoidCallback onCopy;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onCopy,
    borderRadius: BorderRadius.circular(5),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              format.label,
              style: const TextStyle(fontSize: 9, color: _muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.copy_rounded, color: _muted, size: 13),
        ],
      ),
    ),
  );
}

class _RulerPage extends StatelessWidget {
  const _RulerPage({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _PageHeading(
        index: '02 / SCREEN RULER',
        title: '让距离精确到像素',
        description: '手动框选，或沿颜色边界自动测量间距。',
        action: FilledButton.icon(
          onPressed: controller.busy || controller.initializing
              ? null
              : controller.startRuler,
          icon: const Icon(Icons.straighten_rounded, size: 18),
          label: Text(controller.busy ? '工具使用中…' : '开始测量'),
        ),
      ),
      Row(
        children: [
          for (final mode in RulerMode.values) ...[
            if (mode.index != 0) const SizedBox(width: 10),
            Expanded(
              child: _ModeCard(
                mode: mode,
                selected: controller.mode == mode,
                onTap: () => controller.selectMode(mode),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 18),
      Container(
        height: 184,
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _line),
        ),
        child: CustomPaint(
          painter: _RulerIllustration(controller.mode),
          child: const SizedBox.expand(),
        ),
      ),
      const SizedBox(height: 16),
      _Hint(
        icon: Icons.info_outline_rounded,
        text: controller.mode == RulerMode.rectangle
            ? '拖拽框选；Shift 保留多个标注。也可按 Enter 定起点，方向键移动，再按 Enter 确认。浮动栏或 1–4 切换模式；编辑标注可选择、删除、撤销和导出图片。'
            : '自动识别同色边界；滚轮调容差，方向键逐像素移动，Enter 复制。浮动栏或 1–4 切换模式，Esc 取消。',
      ),
      const SizedBox(height: 28),
      _SectionTitle(
        title: '测量记录',
        subtitle: '像素 px / 逻辑点 pt',
        onClear: controller.measurements.isEmpty
            ? null
            : controller.clearMeasurements,
      ),
      const SizedBox(height: 14),
      if (controller.measurements.isEmpty)
        const _Empty(
          icon: Icons.square_foot_rounded,
          title: '下一次测量，从这里开始',
          description: '支持不同缩放比例的显示器，同时保留像素和逻辑点尺寸。',
        )
      else
        Container(
          decoration: BoxDecoration(
            color: _panel,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              for (final record in controller.measurements)
                _MeasurementRow(
                  record: record,
                  onCopy: () => controller.copyMeasurement(record),
                ),
            ],
          ),
        ),
    ],
  );
}

const _modeLabels = {
  RulerMode.rectangle: '矩形',
  RulerMode.horizontal: '水平',
  RulerMode.vertical: '垂直',
  RulerMode.cross: '交叉',
};
const _modeIcons = {
  RulerMode.rectangle: Icons.crop_free_rounded,
  RulerMode.horizontal: Icons.swap_horiz_rounded,
  RulerMode.vertical: Icons.swap_vert_rounded,
  RulerMode.cross: Icons.open_with_rounded,
};

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });
  final RulerMode mode;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFF252D1E) : _panel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: selected ? _accent.withValues(alpha: .65) : _line,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _modeIcons[mode],
              size: 18,
              color: selected ? _accent : _muted,
            ),
            const SizedBox(width: 8),
            Text(
              _modeLabels[mode]!,
              style: TextStyle(
                fontSize: 12,
                color: selected ? _accent : const Color(0xFFD4D9D6),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({required this.record, required this.onCopy});
  final MeasurementRecord record;
  final VoidCallback onCopy;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onCopy,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
      child: Row(
        children: [
          Icon(_modeIcons[record.measurement.mode], size: 17, color: _accent),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.measurement.pixelLabel,
                  style: const TextStyle(fontFamily: 'Menlo', fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '${record.measurement.pointLabel}  ·  ${record.displayName}',
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            '${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontFamily: 'Menlo',
              fontSize: 10,
              color: _muted,
            ),
          ),
          const SizedBox(width: 20),
          const Icon(Icons.copy_rounded, size: 14, color: _muted),
        ],
      ),
    ),
  );
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
        text: 'fruler 0.3.0 · Flutter 界面与 Dart 测量核心 · macOS 14+',
      ),
    ],
  );
  Widget _editableShortcut(BuildContext context, bool picker) => Row(
    children: [
      Text(picker ? '取色器' : '矩形测量', style: const TextStyle(fontSize: 12)),
      const Spacer(),
      OutlinedButton(
        onPressed:
            controller.busy ||
                controller.initializing ||
                controller.savingShortcuts ||
                controller.recordingShortcut
            ? null
            : () => _recordShortcut(context, picker),
        child: Text(
          (picker ? controller.shortcuts.picker : controller.shortcuts.ruler)
              .label,
        ),
      ),
    ],
  );

  Future<void> _recordShortcut(BuildContext context, bool picker) async {
    if (!await controller.beginShortcutRecording()) return;
    ShortcutChord? chord;
    try {
      if (context.mounted) {
        chord = await showDialog<ShortcutChord>(
          context: context,
          builder: (_) => _ShortcutDialog(
            tool: picker ? '取色器' : '矩形测量',
            controller: controller,
          ),
        );
      }
    } finally {
      await controller.endShortcutRecording();
    }
    if (chord != null) await controller.setShortcut(picker, chord);
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
              child,
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(5),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF343E27) : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: selected ? const Color(0xFF526238) : _line),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, color: selected ? _accent : _muted),
      ),
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

class _Footer extends StatelessWidget {
  const _Footer({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 34),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        const Icon(Icons.shield_outlined, size: 11, color: Color(0xFF737E74)),
        const SizedBox(width: 7),
        const Text(
          '本地处理 · 无需联网',
          style: TextStyle(fontSize: 9, color: Color(0xFF737E74)),
        ),
        const Spacer(),
        Text(
          controller.busy ? '屏幕工具运行中' : '细节，尽在掌握',
          style: const TextStyle(fontSize: 9, color: Color(0xFF737E74)),
        ),
      ],
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(7)),
      paint,
    );
    paint
      ..color = const Color(0xFF1B2412)
      ..strokeWidth = size.width * .1
      ..strokeCap = StrokeCap.square;
    final s = size.width;
    canvas.drawLine(Offset(s * .29, s * .75), Offset(s * .29, s * .27), paint);
    canvas.drawLine(Offset(s * .29, s * .27), Offset(s * .73, s * .27), paint);
    canvas.drawLine(Offset(s * .29, s * .49), Offset(s * .59, s * .49), paint);
    paint.strokeWidth = s * .04;
    canvas.drawLine(Offset(s * .48, s * .26), Offset(s * .48, s * .35), paint);
    canvas.drawLine(Offset(s * .66, s * .26), Offset(s * .66, s * .35), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RulerIllustration extends CustomPainter {
  const _RulerIllustration(this.mode);
  final RulerMode mode;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF363D3D);
    for (double x = 18; x < size.width; x += 18) {
      for (double y = 18; y < size.height; y += 18) {
        canvas.drawCircle(Offset(x, y), .7, paint);
      }
    }
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 + 5),
      width: 236,
      height: 88,
    );
    paint.color = const Color(0xFF2B3324);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      paint,
    );
    paint
      ..color = const Color(0xFF5A6649)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      paint,
    );
    paint
      ..color = _accent
      ..strokeWidth = 1.2;
    if (mode == RulerMode.rectangle) {
      canvas.drawRect(rect.inflate(8), paint);
      for (final p in [
        rect.topLeft - const Offset(8, 8),
        rect.topRight + const Offset(8, -8),
        rect.bottomLeft + const Offset(-8, 8),
        rect.bottomRight + const Offset(8, 8),
      ]) {
        canvas.drawRect(
          Rect.fromCenter(center: p, width: 5, height: 5),
          Paint()..color = _accent,
        );
      }
    }
    if (mode != RulerMode.vertical) {
      final y = rect.top - 20;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
      canvas.drawLine(
        Offset(rect.left, y - 5),
        Offset(rect.left, y + 5),
        paint,
      );
      canvas.drawLine(
        Offset(rect.right, y - 5),
        Offset(rect.right, y + 5),
        paint,
      );
      _text(canvas, '宽度', Offset(rect.center.dx, y - 20), _accent);
    }
    if (mode != RulerMode.horizontal) {
      final x = rect.right + 23;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
      canvas.drawLine(Offset(x - 5, rect.top), Offset(x + 5, rect.top), paint);
      canvas.drawLine(
        Offset(x - 5, rect.bottom),
        Offset(x + 5, rect.bottom),
        paint,
      );
      _text(canvas, '高度', Offset(x + 24, rect.center.dy - 6), _accent);
    }
    _text(
      canvas,
      mode == RulerMode.rectangle ? '拖拽框选 · 精确测量' : '光标处的连续同色区域',
      Offset(rect.center.dx, rect.center.dy - 6),
      const Color(0xFF9DA88E),
    );
  }

  void _text(Canvas canvas, String text, Offset center, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy));
  }

  @override
  bool shouldRepaint(_RulerIllustration oldDelegate) =>
      oldDelegate.mode != mode;
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
