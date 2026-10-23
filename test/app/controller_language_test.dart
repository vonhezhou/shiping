import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/l10n/app_language.dart';

import '../fake_desktop.dart';

class _LocaleDesktop extends FakeDesktop {
  _LocaleDesktop(this.locale);
  Locale locale;
  String? rejectedLocale;
  Completer<void>? pendingEnglish;
  Completer<void>? pendingLoad;
  final configuredLocales = <String>[];
  @override
  Locale get systemLocale => locale;
  @override
  Future<String?> loadState() async {
    await pendingLoad?.future;
    return super.loadState();
  }

  @override
  Future<void> configureLocale(String languageCode) async {
    configuredLocales.add(languageCode);
    if (languageCode == 'en') await pendingEnglish?.future;
    if (languageCode == rejectedLocale) {
      throw PlatformException(code: 'locale_failed');
    }
  }
}

void main() {
  test('恢复语言偏好并将解析后的同一语言交给原生', () async {
    final desktop = _LocaleDesktop(const Locale('zh', 'CN'))
      ..saved = jsonEncode({'version': 1, 'language': 'en'});
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    expect(controller.language, AppLanguage.en);
    expect(controller.locale, const Locale('en'));
    expect(desktop.configuredLocales, ['en']);
    await controller.copyColor();
    expect(controller.notice, startsWith('Copied '));
  });

  test('未知偏好回退跟随系统，中文区域归一化，其余语言使用英文', () async {
    for (final (system, expected) in [
      (const Locale('zh', 'TW'), const Locale('zh')),
      (const Locale('de', 'DE'), const Locale('en')),
    ]) {
      final desktop = _LocaleDesktop(system)
        ..saved = jsonEncode({'version': 1, 'language': 'future-language'});
      final controller = AppController(desktop);
      try {
        await controller.initialize();
        expect(controller.language, AppLanguage.system);
        expect(controller.locale, expected);
        expect(desktop.configuredLocales, [expected.languageCode]);
      } finally {
        controller.dispose();
        await desktop.input.close();
      }
    }
  });

  test('只有有效界面语言变化才通知locale，显式语言不随系统变化', () async {
    final desktop = _LocaleDesktop(const Locale('zh'));
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    var localeChanges = 0;
    controller.localeChanges.addListener(() => localeChanges++);
    await controller.copyColor();
    await controller.setLanguage(AppLanguage.zh);
    expect(localeChanges, 0);
    expect(controller.notice, isNull);
    expect(jsonDecode(desktop.saved!)['language'], 'zh');
    await controller.updateSystemLocale(const Locale('en', 'GB'));
    expect(controller.locale, const Locale('zh'));
    expect(localeChanges, 0);
    await controller.setLanguage(AppLanguage.system);
    expect(controller.locale, const Locale('en'));
    expect(localeChanges, 1);
    await controller.updateSystemLocale(const Locale('fr'));
    expect(localeChanges, 1);
  });

  test('原生切语言失败保留原语言与配置，并清除旧提示', () async {
    final desktop = _LocaleDesktop(const Locale('zh'));
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    await controller.setLanguage(AppLanguage.zh);
    await controller.copyColor();
    desktop.rejectedLocale = 'en';
    await controller.setLanguage(AppLanguage.en);
    expect(controller.language, AppLanguage.zh);
    expect(controller.locale, const Locale('zh'));
    expect(jsonDecode(desktop.saved!)['language'], 'zh');
    expect(controller.error, '无法切换语言，已保留原设置。');
    expect(controller.notice, isNull);
    expect(
      desktop.configuredLocales.skip(desktop.configuredLocales.length - 2),
      ['en', 'zh'],
    );
  });

  test('启动时原生不接受已保存语言则恢复系统语言', () async {
    final desktop = _LocaleDesktop(const Locale('zh'))
      ..saved = jsonEncode({'version': 1, 'language': 'en'})
      ..rejectedLocale = 'en';
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    expect(controller.language, AppLanguage.system);
    expect(controller.locale, const Locale('zh'));
    expect(desktop.configuredLocales, ['en', 'zh']);
    expect(controller.error, '无法切换语言，已保留原设置。');
  });

  test('快速切换按顺序等待原生，最终保留最后一次选择', () async {
    final desktop = _LocaleDesktop(const Locale('zh'));
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    desktop.pendingEnglish = Completer<void>();
    final english = controller.setLanguage(AppLanguage.en);
    final chinese = controller.setLanguage(AppLanguage.zh);
    await Future<void>.delayed(Duration.zero);
    expect(desktop.configuredLocales, ['zh', 'en']);
    expect(controller.locale, const Locale('zh'));
    desktop.pendingEnglish!.complete();
    await Future.wait([english, chinese]);
    expect(desktop.configuredLocales, ['zh', 'en', 'zh']);
    expect(controller.locale, const Locale('zh'));
    expect(controller.language, AppLanguage.zh);
    expect(jsonDecode(desktop.saved!)['language'], 'zh');
  });

  test('启动期间系统语言通知等待偏好恢复，不覆盖已保存的显式语言', () async {
    final desktop = _LocaleDesktop(const Locale('zh'))
      ..saved = jsonEncode({'version': 1, 'language': 'zh'})
      ..pendingLoad = Completer<void>()
      ..pendingEnglish = Completer<void>();
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    final initializing = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    final systemChanged = controller.updateSystemLocale(const Locale('en'));
    await Future<void>.delayed(Duration.zero);
    desktop.pendingLoad!.complete();
    await initializing;
    desktop.pendingEnglish!.complete();
    await systemChanged;
    expect(controller.language, AppLanguage.zh);
    expect(controller.locale, const Locale('zh'));
    expect(desktop.configuredLocales, ['zh']);
  });

  test('系统语言变化立即刷新活动浮层描述，不改变工具协议或输出格式', () async {
    final desktop = _LocaleDesktop(const Locale('zh'));
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    await controller.pickColor();
    expect(desktop.lastOverlay!['pickerActions'], startsWith('左键：'));
    final output = controller.formatColor(controller.selectedColor);
    await controller.updateSystemLocale(const Locale('en'));
    expect(desktop.lastOverlay!['pickerActions'], startsWith('Left:'));
    expect(desktop.lastOverlay!['tool'], 'picker');
    expect(desktop.lastOverlay!['colorOutputName'], 'HEX');
    expect(controller.formatColor(controller.selectedColor), output);
    expect(controller.busy, true);
  });

  test('本地化校验错误与动态参数，语言切换不改变复制数据', () async {
    final desktop = _LocaleDesktop(const Locale('zh'));
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    FormatException? validation;
    try {
      const ColorOutput(
        id: 'test',
        name: 'Test',
        template: '%ZZ',
      ).render(const RgbColor(1, 2, 3));
    } on FormatException catch (error) {
      validation = error;
    }
    expect(controller.describeError(validation!), '未知占位符：%ZZ');
    await controller.copyColor();
    final copied = desktop.clipboard;
    await controller.setLanguage(AppLanguage.en);
    expect(controller.describeError(validation), 'Unknown placeholder: %ZZ');
    await controller.copyColor();
    expect(desktop.clipboard, copied);
  });
}
